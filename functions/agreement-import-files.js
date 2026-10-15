import { createHash } from 'node:crypto';
import { AgreementImportError } from './agreement-imports.js';
import { cameraOrientation, cameraPageLayout } from './camera-orientation.js';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const maximum = 20 * 1024 * 1024;
export async function validateImportedPages(bytes, contentType) {
  try {
    const { PDFDocument, pushGraphicsState, concatTransformationMatrix, popGraphicsState } = await import('pdf-lib');
    if (contentType === 'application/pdf') {
      if (bytes.subarray(0, 5).toString() !== '%PDF-' ||
        !bytes.subarray(Math.max(0, bytes.length - 1024)).includes(Buffer.from('%%EOF'))) throw new Error();
      const document = await PDFDocument.load(bytes);
      if (document.isEncrypted || document.getPageCount() < 1 || document.getPageCount() > 40) throw new Error();
      return { pageCount: document.getPageCount(), bytes };
    }
    const document = await PDFDocument.create();
    const imageBytes = Uint8Array.from(bytes);
    const image = contentType === 'image/png' ? await document.embedPng(imageBytes) : await document.embedJpg(imageBytes);
    if (image.width < 300 || image.height < 300 || image.width * image.height > 50000000) throw new Error();
    const layout = cameraPageLayout(contentType === 'image/jpeg' ? cameraOrientation(bytes) : 1, image.width, image.height);
    const page = document.addPage([layout.width, layout.height]);
    page.pushOperators(pushGraphicsState(), concatTransformationMatrix(...layout.matrix));
    page.drawImage(image, { x: 0, y: 0, width: image.width, height: image.height });
    page.pushOperators(popGraphicsState());
    return { pageCount: 1, bytes: Buffer.from(await document.save()) };
  } catch {
    throw new AgreementImportError('invalid-argument', 'A page cannot be opened. Use an unlocked PDF (1–40 pages) or clear JPG/PNG photos.');
  }
}

export function agreementImportFiles(bucket) {
  async function read(file) {
    if (!/^agreementImportFiles\/[a-f0-9]{64}\/(source|signed)\/[a-f0-9]{64}\.pdf$/.test(file.path ?? '') ||
      !/^\d+$/.test(file.generation ?? '') || !Number.isSafeInteger(file.size) || file.size <= 0 || file.size > maximum) {
      throw new AgreementImportError('not-found', 'This private PDF is unavailable.');
    }
    const version = bucket.file(file.path, { generation: file.generation });
    const [metadata] = await version.getMetadata();
    if (String(metadata.generation) !== file.generation) throw new AgreementImportError('not-found', 'The private PDF version cannot be confirmed.');
    if (Number(metadata.size) !== file.size) throw new AgreementImportError('not-found', 'The private PDF size cannot be confirmed.');
    if (metadata.contentType !== 'application/pdf') throw new AgreementImportError('not-found', 'The private PDF file type cannot be confirmed.');
    if (metadata.metadata?.firebaseStorageDownloadTokens) throw new AgreementImportError('not-found', 'The private PDF access settings cannot be confirmed.');
    const [bytes] = await version.download({ start: 0, end: file.size - 1 });
    if (bytes.length !== file.size || hash(bytes) !== file.sha256) {
      throw new AgreementImportError('internal', 'PDF integrity check failed. Retry.');
    }
    return bytes.toString('base64');
  }
  return {
    read,
    cleanup: (grant, uploadId) => Promise.all(grant.specs.map((_, index) =>
      bucket.file(`agreementImportUploads/${grant.uid}/${uploadId}/${index}`).delete({ ignoreNotFound: true }))),
    async snapshot(grant, uploadId) {
      const destination = bucket.file(`agreementImportFiles/${grant.requestId}/${grant.kind}/${uploadId}.pdf`);
      let metadata;
      try { [metadata] = await destination.getMetadata(); } catch (error) { if (error.code !== 404) throw error; }
      if (!metadata) {
        const { PDFDocument } = await import('pdf-lib');
        const output = await PDFDocument.create();
        let single;
        for (const [index, spec] of grant.specs.entries()) {
          const source = bucket.file(`agreementImportUploads/${grant.uid}/${uploadId}/${index}`);
          let sourceMetadata;
          try { [sourceMetadata] = await source.getMetadata(); } catch (error) {
            if (error.code === 404) throw new AgreementImportError('invalid-argument', 'A page has not uploaded. Retry the same send.');
            throw error;
          }
          if (Number(sourceMetadata.size) !== spec.size || sourceMetadata.contentType !== spec.contentType) {
            throw new AgreementImportError('invalid-argument', 'An uploaded page does not match your selection.');
          }
          const [bytes] = await bucket.file(source.name, { generation: sourceMetadata.generation })
            .download({ start: 0, end: spec.size - 1 });
          if (bytes.length !== spec.size || hash(bytes) !== spec.sha256) {
            throw new AgreementImportError('invalid-argument', 'The uploaded pages changed. Retry the original files.');
          }
          const validated = await validateImportedPages(bytes, spec.contentType);
          if (spec.contentType === 'application/pdf') single = validated;
          else {
            const document = await PDFDocument.load(validated.bytes);
            for (const page of await output.copyPages(document, [0])) output.addPage(page);
          }
        }
        const result = single ?? { pageCount: output.getPageCount(), bytes: Buffer.from(await output.save()) };
        if (result.bytes.length > maximum) throw new AgreementImportError('invalid-argument', 'Combined pages exceed 20 MB. Use smaller clear photos.');
        await destination.save(result.bytes, { resumable: false, preconditionOpts: { ifGenerationMatch: 0 },
          contentType: 'application/pdf', metadata: { cacheControl: 'private, no-store',
            metadata: { sha256: hash(result.bytes), pageCount: String(result.pageCount), firebaseStorageDownloadTokens: '' } } })
          .catch(error => { if (error.code !== 412) throw error; });
        [metadata] = await destination.getMetadata();
      }
      if (metadata.metadata?.firebaseStorageDownloadTokens) {
        [metadata] = await destination.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } },
          { preconditionOpts: { ifMetagenerationMatch: metadata.metageneration } });
      }
      const file = { path: destination.name, generation: String(metadata.generation), size: Number(metadata.size),
        sha256: metadata.metadata?.sha256, pageCount: Number(metadata.metadata?.pageCount) };
      if (!/^[a-f0-9]{64}$/.test(file.sha256 ?? '') || !Number.isSafeInteger(file.pageCount) || file.pageCount < 1 || file.pageCount > 40) {
        throw new AgreementImportError('internal', 'The saved pages could not be confirmed.');
      }
      await read(file);
      return file;
    },
  };
}
