import { createHash } from 'node:crypto';
import { InspectionError } from './property-inspections.js';

function validate(metadata) {
  const size = Number(metadata.size);
  if (!['image/jpeg', 'image/png'].includes(metadata.contentType) || !Number.isSafeInteger(size) || size <= 0 || size > 10 * 1024 * 1024) {
    throw new InspectionError('invalid-argument', 'Take a JPG or PNG photo up to 10 MB.');
  }
}
function validHeader(bytes, type) {
  return type === 'image/png' ? bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
    : bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
}
export function inspectionFiles(bucket) {
  return {
    async snapshot(uid, checkId) {
      const destination = bucket.file(`inspectionPhotos/${checkId}/photo`);
      let metadata;
      try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
      if (!metadata) {
        const source = bucket.file(`inspectionUploads/${uid}/${checkId}/photo`);
        let original;
        try { [original] = await source.getMetadata(); } catch (error) {
          if (error.code === 404) throw new InspectionError('invalid-argument', 'The photo has not finished uploading. Retry saving.');
          throw error;
        }
        validate(original);
        const version = bucket.file(source.name, { generation: original.generation });
        const [header] = await version.download({ start: 0, end: 15 });
        if (!validHeader(header, original.contentType)) throw new InspectionError('invalid-argument', 'This is not a valid camera photo.');
        try {
          await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: original.contentType,
            cacheControl: 'private, no-store', metadata: { sourceUid: uid, sourceGeneration: String(original.generation),
              firebaseStorageDownloadTokens: null } });
        } catch (error) { if (error.code !== 412) throw error; }
        [metadata] = await destination.getMetadata();
      }
      validate(metadata);
      if (metadata.metadata?.sourceUid !== uid || !metadata.metadata?.sourceGeneration || metadata.metadata?.firebaseStorageDownloadTokens || !metadata.md5Hash) {
        throw new InspectionError('internal', 'The private photo could not be confirmed.');
      }
      return { path: destination.name, generation: String(metadata.generation), contentType: metadata.contentType,
        size: Number(metadata.size), md5Hash: metadata.md5Hash };
    },
    async read(checkId, file) {
      if (file.path !== `inspectionPhotos/${checkId}/photo` || !/^\d+$/.test(file.generation ?? '')) {
        throw new InspectionError('not-found', 'This photo is unavailable.');
      }
      validate(file);
      const version = bucket.file(file.path, { generation: file.generation });
      try {
        const [metadata] = await version.getMetadata();
        if (metadata.metadata?.firebaseStorageDownloadTokens || metadata.contentType !== file.contentType ||
          String(metadata.generation) !== file.generation || Number(metadata.size) !== file.size || metadata.md5Hash !== file.md5Hash) {
          throw new InspectionError('not-found', 'The private photo could not be confirmed.');
        }
        const [bytes] = await version.download({ start: 0, end: file.size - 1 });
        if (bytes.length !== file.size || !validHeader(bytes, file.contentType) || createHash('md5').update(bytes).digest('base64') !== file.md5Hash) {
          throw new InspectionError('internal', 'The photo could not be verified.');
        }
        return { contentType: file.contentType, size: file.size, base64: bytes.toString('base64') };
      } catch (error) {
        if (error.code === 404) throw new InspectionError('not-found', 'This photo is unavailable.');
        throw error;
      }
    },
    async cleanup(uid, checkId) { await bucket.file(`inspectionUploads/${uid}/${checkId}/photo`).delete({ ignoreNotFound: true }); },
  };
}
