import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { moveOutFixture } from '../test/helpers/move-out-fixture.js';
import { createMoveOutService } from '../move-out-workflow.js';
import { createTenancyService } from '../tenancy-workflow.js';
import { createInspectionService } from '../property-inspections.js';
import { inspectionFiles } from '../inspection-files.js';

let app;
let database;
let bucket;
const time = Date.parse('2026-11-10T12:00:00+05:30');
let operation = 0;
const input = { agreementId: 'move-out-home', role: 'broker' };
const fixture = moveOutFixture();
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  app = initializeApp({ projectId: 'demo-trustkeyper-rules', storageBucket: 'demo-trustkeyper-rules.appspot.com' }, 'move-out-emulator');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  for (const [path, data] of fixture.records) await database.doc(path).set(data);
});
after(async () => { if (app) await deleteApp(app); });
const store = { transaction: handler => database.runTransaction(transaction => handler({
  get: async path => (await transaction.get(database.doc(path))).data(),
  set: (path, data) => transaction.set(database.doc(path), data), update: (path, data) => transaction.update(database.doc(path), data),
})), timestamp: () => FieldValue.serverTimestamp() };
function service(uid) { return createMoveOutService({ auth: fixture.auth(uid), store, now: () => time, code: () => '654321',
  tenancy: createTenancyService({ auth: fixture.auth(uid), store, now: () => time }) }); }
async function record(action, payload, uid = 'broker') {
  const version = (await database.doc('moveOuts/move-out-home').get()).data().version;
  return service(uid).record({ ...input, role: uid === 'flatmate' ? 'tenant' : uid, version,
    operationId: (++operation).toString(16).padStart(32, '0'), action, payload });
}

test('real private move-out photo generations, transactions, counts, report, disputes and refund request are authoritative', async () => {
  const broker = service('broker');
  const before = (await database.doc('tenancies/move-out-home').get()).data();
  const state = await broker.read(input);
  const inspection = createInspectionService({ auth: fixture.auth('broker'), store, files: inspectionFiles(bucket), now: () => time });
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  for (const room of state.rooms) for (const item of room.items) {
    const grant = await inspection.begin({ propertyId: state.propertyId, agreementId: input.agreementId, role: 'broker',
      purpose: 'move_out', itemId: item.id, room: room.room, title: item.title, note: '', source: 'camera', operationId: (++operation).toString(16).padStart(32, '0') });
    await bucket.file(grant.path).save(png, { resumable: false, metadata: { contentType: 'image/png' } });
    await inspection.submit({ checkId: grant.checkId });
    await record('compare', { itemId: item.id, checkId: grant.checkId, condition: item.id === state.rooms[0].items[0].id ? 'repair' : 'same',
      costPaise: item.id === state.rooms[0].items[0].id ? 350000 : 0, note: 'TEST actual damaged door comparison.' });
  }
  const meters = {};
  for (const kind of ['electricity', 'water']) {
    const grant = await inspection.begin({ propertyId: state.propertyId, agreementId: input.agreementId, role: 'broker', purpose: 'move_out_meter',
      itemId: kind, room: 'Fixtures & fittings', title: `${kind} meter`, note: '', source: 'camera', operationId: (++operation).toString(16).padStart(32, '0') });
    await bucket.file(grant.path).save(png, { resumable: false, metadata: { contentType: 'image/png' } });
    await inspection.submit({ checkId: grant.checkId }); meters[kind] = { checkId: grant.checkId, reading: '120' };
  }
  await record('meters', meters);
  await record('keys', { personId: 'tenant', counts: before.keys });
  const issued = await service('tenant').issueCode({ ...input, role: 'tenant', countsConfirmed: true });
  await record('confirm_keys', { challengeId: issued.challengeId, code: issued.code });
  await record('publish', {});
  const report = (await broker.read(input)).report;
  await record('respond', { reportVersion: report.version, itemId: report.lines[0].id, status: 'disputed', reason: 'TEST door was damaged before move-in.' }, 'tenant');
  await record('owner_approve', { reportVersion: report.version, reviewedAllItems: true }, 'owner');
  await record('complete', { reportVersion: report.version, confirmedPhysicalHandover: true });
  await record('destination', { reportVersion: report.version, method: 'original_payment' }, 'tenant');
  await record('refund_request', { reportVersion: report.version, personId: 'tenant' }, 'admin');
  const tenant = await service('tenant').read({ ...input, role: 'tenant' });
  assert.equal(tenant.shares[0].heldPaise, 175000); assert.equal(tenant.shares[0].requestedPaise, 2025000);
  assert.equal(tenant.shares[0].refundStatus, 'awaiting_provider');
  assert.deepEqual((await database.doc('tenancies/move-out-home').get()).data(), before);
  const object = await bucket.file((await database.doc(`properties/${state.propertyId}/photoChecks/${report.lines[0].afterId}`).get()).data().file.path).getMetadata();
  assert.ok(object[0].generation);
});
