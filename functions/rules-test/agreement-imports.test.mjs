import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { PDFDocument } from 'pdf-lib';
import { createHash } from 'node:crypto';
import { createAgreementImportService } from '../agreement-imports.js';
import { agreementImportFiles } from '../agreement-import-files.js';

const projectId = 'demo-trustkeyper-rules';
const brokerUid = 'import-test-broker';
const adminUid = 'import-test-admin';
let environment;
let app;
let database;
let bucket;
let pdf;
let request;
let upload;
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  environment = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') } });
  app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, 'agreement-import-test');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  await database.doc(`users/${brokerUid}`).set({ roles: ['broker'], approvalStatus: 'approved', phone: '+919999999999' });
  await database.doc(`users/${adminUid}`).set({ roles: ['admin'] });
  await database.doc('users/import-test-other').set({ roles: ['broker'], approvalStatus: 'approved', phone: '+918888888888' });
  const document = await PDFDocument.create(); document.addPage().drawText('EMULATOR TEST ONLY · no legal signatures');
  pdf = Buffer.from(await document.save());
  request = { operationId: 'c'.repeat(32), pagesReviewed: true,
    files: [{ contentType: 'application/pdf', size: pdf.length, sha256: createHash('sha256').update(pdf).digest('hex') }],
    signers: [{ name: 'TEST Owner', phone: '+911111111111', role: 'owner' }, { name: 'TEST Tenant', phone: '+912222222222', role: 'tenant' }] };
});
after(async () => { if (environment) await environment.cleanup(); if (app) await deleteApp(app); });
function service(uid) {
  return createAgreementImportService({ auth: { uid, token: { phone_number: '+919999999999', firebase: { sign_in_provider: 'phone' } } },
    files: agreementImportFiles(bucket), store: {
      list: async (collection, ownerUid, limit) => {
        let query = database.collection(collection); if (ownerUid) query = query.where('brokerUid', '==', ownerUid);
        return (await query.limit(limit).get()).docs.map(document => ({ ...document.data(), id: document.id }));
      },
      transaction: handler => database.runTransaction(transaction => handler({
        get: async path => (await transaction.get(database.doc(path))).data(),
        set: (path, data) => transaction.set(database.doc(path), data),
        update: (path, data) => transaction.update(database.doc(path), data),
      })),
    } });
}

test('signing import grants enforce UID, phone proof, exact type, index and size in real Storage rules', async () => {
  upload = await service(brokerUid).begin(request);
  const broker = environment.authenticatedContext(brokerUid, { phone_number: '+919999999999', firebase: { sign_in_provider: 'phone' } });
  const other = environment.authenticatedContext('import-test-other', { phone_number: '+918888888888', firebase: { sign_in_provider: 'phone' } });
  await assertSucceeds(uploadBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0]), pdf, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(other.storage(`gs://${projectId}.appspot.com`), upload.paths[0]), pdf, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0].replace(/\/0$/, '/1')), pdf, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0]), pdf, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0]), pdf.subarray(0, 20), { contentType: 'application/pdf' }));
  await assertFails(getBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0])));
  await assertFails(getDoc(doc(broker.firestore(), `agreementImportUploads/${upload.uploadId}`)));
  await assertFails(setDoc(doc(broker.firestore(), `agreementImports/${upload.requestId}`), { status: 'completed' }));
});

test('real transactional completion creates an immutable private PDF, counts pages and clears upload tokens', async () => {
  const completed = await service(brokerUid).complete({ uploadId: upload.uploadId });
  assert.equal(completed.ready, true);
  const saved = (await database.doc(`agreementImports/${upload.requestId}`).get()).data();
  assert.equal(saved.status, 'received'); assert.equal(saved.pageCount, 1);
  const [metadata] = await bucket.file(saved.sourceFile.path).getMetadata();
  assert.equal(Boolean(metadata.metadata?.firebaseStorageDownloadTokens), false);
  const read = await service(brokerUid).read({ requestId: upload.requestId });
  assert.deepEqual(Buffer.from(read.base64, 'base64'), pdf);
  await service(brokerUid).complete({ uploadId: upload.uploadId });
  const broker = environment.authenticatedContext(brokerUid, { phone_number: '+919999999999', firebase: { sign_in_provider: 'phone' } });
  await assertFails(getBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), saved.sourceFile.path)));
  await assertFails(uploadBytes(ref(broker.storage(`gs://${projectId}.appspot.com`), upload.paths[0]), pdf, { contentType: 'application/pdf' }));
});

test('actual team stages require an externally completed original, private signed copy and no test tenancy activation', async () => {
  const admin = service(adminUid);
  for (const [revision, status] of [[2, 'stamp_preparing'], [3, 'ready_to_sign'], [4, 'signing']]) {
    await admin.record({ requestId: upload.requestId, revision, status, reference: 'EMULATOR external reference', note: 'TEST evidence only' });
  }
  const document = await PDFDocument.create(); document.addPage().drawText('TEST published copy · not legally signed');
  const signed = Buffer.from(await document.save());
  const grant = await admin.beginSigned({ requestId: upload.requestId, revision: 5, operationId: 'd'.repeat(32),
    originalChecked: true, allPartiesSigned: true,
    file: { contentType: 'application/pdf', size: signed.length, sha256: createHash('sha256').update(signed).digest('hex') } });
  const adminContext = environment.authenticatedContext(adminUid);
  await assertSucceeds(uploadBytes(ref(adminContext.storage(`gs://${projectId}.appspot.com`), grant.paths[0]), signed, { contentType: 'application/pdf' }));
  await admin.complete({ uploadId: grant.uploadId });
  const result = await service(brokerUid).read({ requestId: upload.requestId, signed: true });
  assert.deepEqual(Buffer.from(result.base64, 'base64'), signed);
  assert.equal((await database.doc(`agreementImports/${upload.requestId}`).get()).data().status, 'completed');
  assert.equal((await database.doc(`tenancies/${upload.requestId}`).get()).exists, false);
});
