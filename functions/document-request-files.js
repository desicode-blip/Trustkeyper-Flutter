import { DocumentRequestError } from './document-requests.js';

const slots = { aadhaar: ['aadhaarFront', 'aadhaarBack'], pan: ['pan'], bank: ['bankProof'],
  linkedin: [], all: ['aadhaarFront', 'aadhaarBack', 'pan', 'bankProof'] };
export function documentRequestFiles(database, bucket) {
  return { async cleanup(id, uploadId) {
    const request = (await database.doc(`brokerDocumentRequests/${id}`).get()).data();
    if (!request || !slots[request.type]) return;
    await Promise.all(slots[request.type].map(kind => bucket.file(`brokerDocumentRequests/${id}/uploads/${uploadId}/${kind}`).delete({ ignoreNotFound: true })));
  }, async snapshot(id, uploadId) {
    const request = (await database.doc(`brokerDocumentRequests/${id}`).get()).data();
    if (!request || !slots[request.type]) throw new DocumentRequestError('failed-precondition', 'Document request unavailable.');
    const result = {};
    for (const kind of request.uploadSlots ?? slots[request.type]) {
      const destination = bucket.file(`brokerDocumentRequests/${id}/submissions/${uploadId}/${kind}`);
      let metadata;
      try { [metadata] = await destination.getMetadata(); }
      catch (error) { if (error.code !== 404) throw error; }
      if (!metadata) {
        const upload = bucket.file(`brokerDocumentRequests/${id}/uploads/${uploadId}/${kind}`);
        let original;
        try { [original] = await upload.getMetadata(); }
        catch (error) { if (error.code === 404) throw new DocumentRequestError('invalid-argument', 'Add every required page before sending.'); throw error; }
        if (Number(original.size) <= 0 || Number(original.size) > 10 * 1024 * 1024 ||
          !['application/pdf', 'image/jpeg', 'image/png'].includes(original.contentType)) {
          throw new DocumentRequestError('invalid-argument', 'Choose JPG, PNG or PDF files up to 10 MB.');
        }
        const version = bucket.file(upload.name, { generation: original.generation });
        const [header] = await version.download({ start: 0, end: 15 });
        const valid = original.contentType === 'application/pdf' ? header.subarray(0, 5).toString() === '%PDF-' :
          original.contentType === 'image/png' ? header.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) :
            header.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
        if (!valid) throw new DocumentRequestError('invalid-argument', 'The file type does not match its contents.');
        try { await version.copy(destination, { preconditionOpts: { ifGenerationMatch: 0 }, contentType: original.contentType,
          cacheControl: 'private, no-store', metadata: {
          displayName: String(original.metadata?.displayName ?? 'Document').slice(0, 200),
          sourceGeneration: String(original.generation), firebaseStorageDownloadTokens: null,
        } }); }
        catch (error) { if (error.code !== 412) throw error; }
        [metadata] = await destination.getMetadata();
      }
      if (metadata.metadata?.firebaseStorageDownloadTokens || !metadata.metadata?.sourceGeneration) {
        throw new DocumentRequestError('internal', 'The private document snapshot could not be confirmed. Retry sending.');
      }
      if (!['application/pdf', 'image/jpeg', 'image/png'].includes(metadata.contentType) ||
        typeof metadata.metadata?.displayName !== 'string' || Number(metadata.size) <= 0 || Number(metadata.size) > 10 * 1024 * 1024) {
        throw new DocumentRequestError('internal', 'The private document metadata could not be confirmed. Retry sending.');
      }
      result[kind] = { path: destination.name, name: metadata.metadata.displayName, contentType: metadata.contentType,
        size: Number(metadata.size), generation: String(metadata.generation), md5Hash: metadata.md5Hash ?? '' };
    }
    return result;
  } };
}
