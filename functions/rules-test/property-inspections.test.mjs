import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createInspectionService } from '../property-inspections.js';
import { inspectionFiles } from '../inspection-files.js';

const projectId = 'demo-trustkeyper-rules';
let app;
let database;
let bucket;
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, 'inspection-emulator');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  await database.doc('users/inspection-broker').set({ roles: ['broker'], approvalStatus: 'approved', displayName: 'Test Broker' });
  await database.doc('users/inspection-admin').set({ roles: ['admin'] });
  await database.doc('properties/inspection-flat').set({ brokerUid: 'inspection-broker', address: 'Emulator Photo Test' });
});
after(async () => { if (app) await deleteApp(app); });
function service(uid) {
  return createInspectionService({ auth: { uid }, files: inspectionFiles(bucket), store: {
    timestamp: () => FieldValue.serverTimestamp(), transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      list: async (path, limit) => (await transaction.get(database.collection(path).orderBy('createdAt', 'desc').limit(limit))).docs
        .map(document => ({ ...document.data(), id: document.id })),
      set: (path, value) => transaction.set(database.doc(path), value),
      update: (path, value) => transaction.update(database.doc(path), value),
    })),
  } });
}

test('real private photo storage freezes a generation, removes tokens, publishes once and permits audited admin review', async () => {
  const broker = service('inspection-broker'); const admin = service('inspection-admin');
  const grant = await broker.begin({ propertyId: 'inspection-flat', role: 'broker', room: 'Kitchen', title: 'Test sink tap',
    note: '', source: 'camera', operationId: 'e'.repeat(32) });
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  await bucket.file(grant.path).save(png, { resumable: false, metadata: { contentType: 'image/png',
    metadata: { firebaseStorageDownloadTokens: 'TEST-NOT-PUBLIC' } } });
  await broker.submit(grant); await broker.submit(grant);
  const list = await broker.list({ propertyId: 'inspection-flat' });
  assert.equal(list.checks.length, 1);
  assert.equal(list.checks[0].actorName, 'Test Broker'); assert.equal(list.checks[0].status, 'submitted');
  assert.equal((await bucket.file(grant.path).exists())[0], false);
  const image = await broker.readPhoto({ propertyId: 'inspection-flat', checkId: grant.checkId });
  assert.deepEqual(Buffer.from(image.base64, 'base64'), png);
  await admin.review({ propertyId: 'inspection-flat', checkId: grant.checkId, version: 1,
    status: 'flagged', note: 'This sink tap needs a repair.', operationId: 'f'.repeat(32) });
  assert.equal((await broker.list({ propertyId: 'inspection-flat' })).checks[0].status, 'flagged');
  await database.doc('users/inspection-broker').update({ paused: true });
  await assert.rejects(broker.readPhoto({ propertyId: 'inspection-flat', checkId: grant.checkId }), { code: 'permission-denied' });
});

test('photo adapter rejects mismatched content headers, public tokens and wrong private paths', async () => {
  const files = inspectionFiles(bucket); const id = 'd'.repeat(32);
  const source = `inspectionUploads/inspection-broker/${id}/photo`;
  await bucket.file(source).save(Buffer.from('not a png image'), { resumable: false, metadata: { contentType: 'image/png' } });
  await assert.rejects(files.snapshot('inspection-broker', id), { code: 'invalid-argument' });
  await assert.rejects(files.read(id, { path: 'some-other-private-file', generation: '1' }), { code: 'not-found' });
  await bucket.file(source).delete();
});
