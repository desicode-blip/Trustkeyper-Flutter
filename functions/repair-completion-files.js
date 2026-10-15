import { createHash } from 'node:crypto';
import { RepairWorkflowError } from './repair-workflow.js';

const maximum = 10 * 1024 * 1024;
const allowed = ['image/jpeg', 'image/png', 'application/pdf'];
function validHeader(type, bytes) {
  return type === 'application/pdf' ? bytes.subarray(0, 5).equals(Buffer.from('%PDF-'))
    : type === 'image/png' ? bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
      : bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
}
function metadataValid(metadata, slot) {
  return allowed.includes(metadata.contentType) && (slot === 'bill' || metadata.contentType !== 'application/pdf') &&
    Number.isSafeInteger(Number(metadata.size)) && Number(metadata.size) > 0 && Number(metadata.size) <= maximum;
}
export function repairCompletionFiles(bucket) {
  return {
    async snapshot(upload) {
      const evidence = {};
      for (const slot of upload.includeBefore ? ['bill', 'before', 'after'] : ['bill', 'after']) {
        const destination = bucket.file(`issues/${upload.issueId}/evidence/${upload.uploadId}/${slot}`);
        let metadata;
        try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
        if (!metadata) {
          const source = bucket.file(`repairCompletionUploads/${upload.adminUid}/${upload.uploadId}/${slot}`);
          let original;
          try { [original] = await source.getMetadata(); }
          catch (error) {
            if (error.code === 404) throw new RepairWorkflowError('failed-precondition', `Upload the ${slot} before marking fixed.`);
            throw error;
          }
          if (!metadataValid(original, slot) || !/^\d+$/.test(String(original.generation)) || !original.md5Hash) {
            throw new RepairWorkflowError('invalid-argument', 'Choose a PDF bill and JPG/PNG photos up to 10 MB.');
          }
          const version = bucket.file(source.name, { generation: original.generation });
          const [header] = await version.download({ start: 0, end: 15 });
          if (!validHeader(original.contentType, header)) throw new RepairWorkflowError('invalid-argument', 'The file contents do not match its type.');
          try {
            await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: original.contentType,
              cacheControl: 'private, no-store', metadata: { sourceGeneration: String(original.generation),
                firebaseStorageDownloadTokens: null } });
          } catch (error) { if (error.code !== 412) throw error; }
          [metadata] = await destination.getMetadata();
          if (metadata.md5Hash !== original.md5Hash || Number(metadata.size) !== Number(original.size)) {
            throw new RepairWorkflowError('internal', 'The evidence copy could not be verified. Retry.');
          }
        }
        if (!metadataValid(metadata, slot) || !metadata.md5Hash || !metadata.metadata?.sourceGeneration ||
          metadata.metadata?.firebaseStorageDownloadTokens) throw new RepairWorkflowError('internal', 'Private evidence could not be confirmed. Retry.');
        evidence[slot] = { path: destination.name, contentType: metadata.contentType, size: Number(metadata.size),
          generation: String(metadata.generation), md5Hash: metadata.md5Hash };
      }
      return evidence;
    },
    async read(file) {
      if (!/^issues\/[\w-]{1,150}\/evidence\/[a-f0-9]{64}\/(bill|before|after)$/.test(file.path ?? '') ||
        !/^\d+$/.test(file.generation ?? '') || !metadataValid(file, file.path.split('/').at(-1))) {
        throw new RepairWorkflowError('not-found', 'This evidence is unavailable.');
      }
      const version = bucket.file(file.path, { generation: file.generation });
      const [metadata] = await version.getMetadata();
      if (String(metadata.generation) !== file.generation || metadata.md5Hash !== file.md5Hash ||
        metadata.contentType !== file.contentType || Number(metadata.size) !== file.size || metadata.metadata?.firebaseStorageDownloadTokens) {
        throw new RepairWorkflowError('not-found', 'This private file could not be confirmed.');
      }
      const [bytes] = await version.download({ start: 0, end: file.size - 1 });
      if (bytes.length !== file.size || createHash('md5').update(bytes).digest('base64') !== file.md5Hash || !validHeader(file.contentType, bytes)) {
        throw new RepairWorkflowError('internal', 'This evidence could not be verified.');
      }
      return { contentType: file.contentType, size: file.size, base64: bytes.toString('base64') };
    },
    async cleanup(upload) {
      await Promise.all(['bill', 'before', 'after'].map(slot =>
        bucket.file(`repairCompletionUploads/${upload.adminUid}/${upload.uploadId}/${slot}`).delete({ ignoreNotFound: true })));
    },
  };
}
