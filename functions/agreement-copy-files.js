import { createHash } from 'node:crypto';
import { AgreementCopyError } from './agreement-copies.js';
const checksum = bytes => createHash('sha256').update(bytes).digest('hex');

export function agreementCopyFiles(bucket) {
  async function read(file) {
    if (!/^agreementCopies\/[\w-]{1,128}\/\d+\/[a-f0-9]{64}\.pdf$/.test(file.path) ||
        !/^\d+$/.test(file.generation) || !Number.isSafeInteger(file.size) ||
        file.size <= 0 || file.size > 20 * 1024 * 1024 || !/^[a-f0-9]{64}$/.test(file.sha256 ?? '')) {
      throw new AgreementCopyError('not-found', 'This agreement copy is unavailable.');
    }
    const version = bucket.file(file.path, { generation: file.generation });
    const [metadata] = await version.getMetadata();
    if (String(metadata.generation) !== file.generation || Number(metadata.size) !== file.size ||
        metadata.contentType !== 'application/pdf' || metadata.metadata?.firebaseStorageDownloadTokens) {
      throw new AgreementCopyError('not-found', 'This private copy could not be confirmed.');
    }
    const [bytes] = await version.download({ start: 0, end: file.size - 1 });
    if (bytes.length !== file.size || checksum(bytes) !== file.sha256) {
      throw new AgreementCopyError('internal', 'This PDF could not be verified. Retry.');
    }
    return bytes.toString('base64');
  }
  return {
    read,
    cleanup: upload => bucket.file(upload.path).delete({ ignoreNotFound: true }),
    async snapshot(upload, uploadId) {
      const destination = bucket.file(`agreementCopies/${upload.agreementId}/${upload.revision}/${uploadId}.pdf`);
      let metadata;
      try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
      if (!metadata) {
        const source = bucket.file(upload.path);
        let original;
        try { [original] = await source.getMetadata(); }
        catch (error) {
          if (error.code === 404) throw new AgreementCopyError('invalid-argument', 'The PDF has not finished uploading. Retry.');
          throw error;
        }
        if (original.contentType !== 'application/pdf' || Number(original.size) !== upload.size || upload.size > 20 * 1024 * 1024) {
          throw new AgreementCopyError('invalid-argument', 'Choose a PDF up to 20 MB.');
        }
        const version = bucket.file(upload.path, { generation: original.generation });
        const [bytes] = await version.download({ start: 0, end: upload.size - 1 });
        if (bytes.length !== upload.size || bytes.subarray(0, 5).toString() !== '%PDF-' ||
            !bytes.subarray(Math.max(0, bytes.length - 1024)).includes(Buffer.from('%%EOF')) || checksum(bytes) !== upload.sha256) {
          throw new AgreementCopyError('invalid-argument', 'The PDF contents do not match the reviewed file.');
        }
        try {
          await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: 'application/pdf',
            cacheControl: 'private, no-store', metadata: { sourceGeneration: String(original.generation),
              sha256: upload.sha256, firebaseStorageDownloadTokens: null } });
        } catch (error) { if (error.code !== 412) throw error; }
        [metadata] = await destination.getMetadata();
      }
      const file = { path: destination.name, generation: String(metadata.generation),
        size: Number(metadata.size), sha256: upload.sha256 };
      await read(file);
      return file;
    },
  };
}
