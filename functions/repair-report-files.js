import { createHash } from 'node:crypto';
import { RepairError } from './repair-reports.js';

export function repairReportFiles(bucket) {
  return {
    async read(photo) {
      if (!/^issues\/[a-f0-9]{32}\/photos\/[0-3]$/.test(photo.path) ||
        !/^\d+$/.test(photo.generation) || !['image/jpeg', 'image/png'].includes(photo.contentType) ||
        !Number.isSafeInteger(photo.size) || photo.size <= 0 || photo.size > 10 * 1024 * 1024) {
        throw new RepairError('not-found', 'This report photo is unavailable.');
      }
      const version = bucket.file(photo.path, { generation: photo.generation });
      try {
        const [metadata] = await version.getMetadata();
        if (String(metadata.generation) !== photo.generation || metadata.contentType !== photo.contentType ||
          Number(metadata.size) !== photo.size || !photo.md5Hash || metadata.md5Hash !== photo.md5Hash ||
          metadata.metadata?.firebaseStorageDownloadTokens) {
          throw new RepairError('not-found', 'This private photo could not be confirmed.');
        }
        const [bytes] = await version.download({ start: 0, end: photo.size - 1 });
        if (bytes.length !== photo.size || createHash('md5').update(bytes).digest('base64') !== photo.md5Hash) {
          throw new RepairError('internal', 'This photo could not be verified. Try again.');
        }
        return { path: photo.path, contentType: photo.contentType, size: photo.size, base64: bytes.toString('base64') };
      } catch (error) {
        if (error.code === 404) throw new RepairError('not-found', 'This report photo is unavailable.');
        throw error;
      }
    },
    async cleanup(uid, reportId) {
      await Promise.all(Array.from({ length: 4 }, (_, index) =>
        bucket.file(`repairUploads/${uid}/${reportId}/${index}`).delete({ ignoreNotFound: true })));
    },
    async snapshot(uid, reportId, count) {
      const photos = [];
      for (let index = 0; index < count; index++) {
        const destination = bucket.file(`issues/${reportId}/photos/${index}`);
        let metadata;
        try { [metadata] = await destination.getMetadata(); }
        catch (error) { if (error.code !== 404) throw error; }
        if (!metadata) {
          const upload = bucket.file(`repairUploads/${uid}/${reportId}/${index}`);
          let original;
          try { [original] = await upload.getMetadata(); }
          catch (error) {
            if (error.code === 404) throw new RepairError('invalid-argument', 'A photo has not finished uploading. Retry sending.');
            throw error;
          }
          if (!['image/jpeg', 'image/png'].includes(original.contentType) ||
            Number(original.size) <= 0 || Number(original.size) > 10 * 1024 * 1024) {
            throw new RepairError('invalid-argument', 'Choose JPG or PNG photos up to 10 MB.');
          }
          const version = bucket.file(upload.name, { generation: original.generation });
          const [header] = await version.download({ start: 0, end: 15 });
          const valid = original.contentType === 'image/png'
            ? header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
            : header.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
          if (!valid) throw new RepairError('invalid-argument', 'The photo type does not match its contents.');
          try {
            await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 },
              contentType: original.contentType, cacheControl: 'private, no-store', metadata: {
                displayName: `Repair photo ${index + 1}`, sourceGeneration: String(original.generation),
                firebaseStorageDownloadTokens: null,
              } });
          } catch (error) { if (error.code !== 412) throw error; }
          [metadata] = await destination.getMetadata();
        }
        if (!['image/jpeg', 'image/png'].includes(metadata.contentType) ||
          !metadata.metadata?.sourceGeneration || metadata.metadata?.firebaseStorageDownloadTokens ||
          Number(metadata.size) <= 0 || Number(metadata.size) > 10 * 1024 * 1024) {
          throw new RepairError('internal', 'The private photo could not be confirmed. Retry sending.');
        }
        photos.push({ path: destination.name, name: `Repair photo ${index + 1}`,
          contentType: metadata.contentType, size: Number(metadata.size), generation: String(metadata.generation),
          md5Hash: metadata.md5Hash ?? '' });
      }
      return photos;
    },
  };
}
