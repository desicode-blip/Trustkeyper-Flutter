import { createHash } from 'node:crypto';
import { OwnerPropertyError } from './owner-properties.js';
import { validateImportedPages } from './agreement-import-files.js';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function ownerContractFiles(bucket) {
  async function read(file) {
    if (!/^ownerContractFiles\/[a-f0-9]{64}\/(source|signed)\/[a-f0-9]{64}\.pdf$/.test(file.path ?? '') ||
      !/^\d+$/.test(file.generation ?? '') || !Number.isSafeInteger(file.size) || file.size < 1 || file.size > 20971520) {
      throw new OwnerPropertyError('not-found', 'This private contract is unavailable.');
    }
    const object = bucket.file(file.path, { generation: file.generation });
    const [metadata] = await object.getMetadata();
    if (String(metadata.generation) !== file.generation || Number(metadata.size) !== file.size ||
      metadata.contentType !== 'application/pdf' || metadata.metadata?.firebaseStorageDownloadTokens) {
      throw new OwnerPropertyError('not-found', 'The private contract cannot be confirmed.');
    }
    const [bytes] = await object.download({ start: 0, end: file.size - 1 });
    if (bytes.length !== file.size || hash(bytes) !== file.sha256) throw new OwnerPropertyError('internal', 'Contract integrity check failed.');
    return bytes.toString('base64');
  }
  return { read,
    cleanup: (grant, uploadId) => bucket.file(`ownerContractUploads/${grant.uid}/${uploadId}/contract.pdf`).delete({ ignoreNotFound: true }),
    async snapshot(grant, uploadId) {
      const destination = bucket.file(`ownerContractFiles/${grant.propertyId}/${grant.kind}/${uploadId}.pdf`);
      let metadata;
      try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
      if (!metadata) {
        const source = bucket.file(`ownerContractUploads/${grant.uid}/${uploadId}/contract.pdf`);
        let original;
        try { [original] = await source.getMetadata(); } catch (error) {
          if (error.code === 404) throw new OwnerPropertyError('invalid-argument', 'The PDF has not uploaded. Retry.');
          throw error;
        }
        if (Number(original.size) !== grant.spec.size || original.contentType !== 'application/pdf') {
          throw new OwnerPropertyError('invalid-argument', 'The PDF changed during upload.');
        }
        const version = bucket.file(source.name, { generation: original.generation });
        const [bytes] = await version.download({ start: 0, end: grant.spec.size - 1 });
        if (bytes.length !== grant.spec.size || hash(bytes) !== grant.spec.sha256) throw new OwnerPropertyError('invalid-argument', 'The PDF integrity check failed.');
        let validated;
        try { validated = await validateImportedPages(bytes, 'application/pdf'); }
        catch { throw new OwnerPropertyError('invalid-argument', 'Use an unlocked PDF with 1–40 readable pages.'); }
        await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: 'application/pdf',
          cacheControl: 'private, no-store', metadata: { sha256: grant.spec.sha256, pageCount: String(validated.pageCount), firebaseStorageDownloadTokens: null } })
          .catch(error => { if (error.code !== 412) throw error; });
        [metadata] = await destination.getMetadata();
      }
      const file = { path: destination.name, generation: String(metadata.generation), size: Number(metadata.size),
        sha256: metadata.metadata?.sha256, pageCount: Number(metadata.metadata?.pageCount) };
      if (file.sha256 !== grant.spec.sha256 || file.size !== grant.spec.size || !Number.isSafeInteger(file.pageCount) || file.pageCount < 1 || file.pageCount > 40) {
        throw new OwnerPropertyError('internal', 'The saved contract does not match the reviewed PDF.');
      }
      await read(file); return file;
    },
  };
}
