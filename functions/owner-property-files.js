import { createHash } from 'node:crypto';
import { validateImportedPages } from './agreement-import-files.js';
import { OwnerPropertyError } from './owner-properties.js';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export function ownerPropertyFiles(bucket) {
  async function read(file) {
    if (!/^ownerPropertyPhotos\/[a-f0-9]{64}\/[a-f0-9]{64}\/[0-4]$/.test(file.path ?? '') ||
      !/^\d+$/.test(file.generation ?? '') || !['image/jpeg', 'image/png'].includes(file.contentType) ||
      !Number.isSafeInteger(file.size) || file.size <= 0 || file.size > 10485760) {
      throw new OwnerPropertyError('not-found', 'This private photo is unavailable.');
    }
    const version = bucket.file(file.path, { generation: file.generation });
    const [metadata] = await version.getMetadata();
    if (String(metadata.generation) !== file.generation || Number(metadata.size) !== file.size ||
      metadata.contentType !== file.contentType || metadata.metadata?.firebaseStorageDownloadTokens) {
      throw new OwnerPropertyError('not-found', 'This private photo cannot be confirmed.');
    }
    const [bytes] = await version.download({ start: 0, end: file.size - 1 });
    if (bytes.length !== file.size || hash(bytes) !== file.sha256) throw new OwnerPropertyError('internal', 'Photo integrity check failed.');
    return bytes.toString('base64');
  }
  return {
    read,
    cleanup: (grant, uploadId) => Promise.all(grant.specs.map((_, index) =>
      bucket.file(`ownerPropertyUploads/${grant.uid}/${uploadId}/${index}`).delete({ ignoreNotFound: true }))),
    async snapshot(grant, uploadId) {
      const result = [];
      for (const [index, spec] of grant.specs.entries()) {
        const destination = bucket.file(`ownerPropertyPhotos/${grant.propertyId}/${uploadId}/${index}`);
        let metadata;
        try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
        if (!metadata) {
          const source = bucket.file(`ownerPropertyUploads/${grant.uid}/${uploadId}/${index}`);
          let original;
          try { [original] = await source.getMetadata(); } catch (error) {
            if (error.code === 404) throw new OwnerPropertyError('invalid-argument', 'A photo has not uploaded. Retry.');
            throw error;
          }
          if (Number(original.size) !== spec.size || original.contentType !== spec.contentType) {
            throw new OwnerPropertyError('invalid-argument', 'An uploaded photo changed. Retry the original photos.');
          }
          const version = bucket.file(source.name, { generation: original.generation });
          const [bytes] = await version.download({ start: 0, end: spec.size - 1 });
          if (bytes.length !== spec.size || hash(bytes) !== spec.sha256) throw new OwnerPropertyError('invalid-argument', 'Photo integrity check failed.');
          try { await validateImportedPages(bytes, spec.contentType); } catch {
            throw new OwnerPropertyError('invalid-argument', 'A photo cannot be opened or is too small. Take a clear photo again.');
          }
          await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: spec.contentType,
            cacheControl: 'private, no-store', metadata: { sha256: spec.sha256, firebaseStorageDownloadTokens: null } })
            .catch(error => { if (error.code !== 412) throw error; });
          [metadata] = await destination.getMetadata();
        }
        const file = { path: destination.name, generation: String(metadata.generation), contentType: spec.contentType,
          size: spec.size, sha256: spec.sha256 };
        await read(file); result.push(file);
      }
      return result;
    },
  };
}
