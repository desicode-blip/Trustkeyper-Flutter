import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { createHash } from 'node:crypto';
import { createTenancyService } from '../tenancy-workflow.js';
import { createInspectionService } from '../property-inspections.js';
import { inspectionFiles } from '../inspection-files.js';
import { reviewSnapshot } from '../agreement-review.js';
import { approvalDigest } from '../agreement-approvals.js';

let app;
let database;
let bucket;
const time = Date.parse('2026-10-10T12:00:00+05:30');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const base = { agreementId: 'emulator-tenancy', role: 'broker' };
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  app = initializeApp({ projectId: 'demo-trustkeyper-rules', storageBucket: 'demo-trustkeyper-rules.appspot.com' }, 'tenancy-emulator');
  database = getFirestore(app); bucket = getStorage(app).bucket();
  const owner = { id: 'emulator-owner', name: 'TEST Owner', phone: '+911111111111', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 };
  const tenant = { id: 'emulator-tenant', name: 'TEST Tenant', phone: '+912222222222', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 };
  const agreement = { schemaVersion: 2, propertyId: 'emulator-tenancy-flat', propertyAddress: 'Emulator TEST Flat 402', propertyDetails: { rooms: '2 BHK' },
    revision: 1, status: 'signed_copy_received', owners: [owner], tenants: [tenant], monthlyRentPaise: 2200000,
    monthlyMaintenancePaise: 0, securityDepositPaise: 4400000, startDateISO: '2026-10-01T00:00:00.000Z', endDateISO: '2027-08-31T00:00:00.000Z',
    rentDueDay: 5, lockInMonths: 6, noticeMonths: 1, ownerBrokeragePaise: 0, tenantBrokeragePaise: 0,
    brokerUid: 'emulator-broker', participantUids: ['emulator-broker', 'emulator-owner', 'emulator-tenant'] };
  agreement.agreementCopy = { mode: 'externally_signed', revision: 1, digest: approvalDigest(reviewSnapshot(agreement)),
    people: [{ ...owner, uid: owner.id, role: 'owner' }, { ...tenant, uid: tenant.id, role: 'tenant' }] };
  await database.doc('agreements/emulator-tenancy').set(agreement);
  await database.doc('properties/emulator-tenancy-flat').set({ brokerUid: 'emulator-broker', participantUids: ['emulator-broker'], address: agreement.propertyAddress });
  for (const [uid, roles] of [['emulator-broker', ['broker']], ['emulator-owner', ['owner']], ['emulator-tenant', ['tenant']]]) {
    await database.doc(`users/${uid}`).set({ roles, approvalStatus: 'approved', displayName: `TEST ${roles[0]}` });
  }
});
after(async () => { if (app) await deleteApp(app); });
function store() {
  return { timestamp: () => FieldValue.serverTimestamp(), transaction: handler => database.runTransaction(transaction => handler({
    get: async path => (await transaction.get(database.doc(path))).data(),
    list: async (path, limit) => (await transaction.get(database.collection(path).orderBy('createdAt', 'desc').limit(limit))).docs.map(document => ({ ...document.data(), id: document.id })),
    set: (path, value) => transaction.set(database.doc(path), value), update: (path, value) => transaction.update(database.doc(path), value),
  })) };
}
function tenancy(uid) {
  return createTenancyService({ store: store(), now: () => time, code: () => '654321', auth: { uid,
    token: { phone_number: uid === 'emulator-tenant' ? '+912222222222' : '+911111111111', firebase: { sign_in_provider: 'phone' } } } });
}

test('real emulator transactions and immutable photo files drive move-in; test payment never releases keys', async () => {
  const broker = tenancy('emulator-broker');
  await broker.record({ ...base, version: 0, operationId: '1'.repeat(32), action: 'rooms',
    payload: { bedrooms: 0, washrooms: 1, balcony: false, confirmedPhysicalLayout: true } });
  const photoService = createInspectionService({ auth: { uid: 'emulator-broker' }, store: store(), files: inspectionFiles(bucket), now: () => time });
  const first = await broker.read(base);
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  const meterIds = {};
  const captures = [...first.rooms.flatMap(room => room.items.map(item => ({ room: room.room, title: item.title, itemId: item.id, purpose: 'move_in' }))),
    ...['electricity', 'water'].map(kind => ({ room: 'Fixtures & fittings', title: `${kind} meter`, itemId: kind, purpose: 'move_in_meter' }))];
  for (const [index, capture] of captures.entries()) {
    const grant = await photoService.begin({ propertyId: first.propertyId, agreementId: base.agreementId, role: 'broker',
      ...capture, note: '', source: 'camera', operationId: index.toString(16).padStart(32, '0') });
    await bucket.file(grant.path).save(png, { resumable: false, metadata: { contentType: 'image/png' } });
    await photoService.submit(grant); await photoService.submit(grant);
    if (capture.purpose === 'move_in_meter') meterIds[capture.itemId] = grant.checkId;
  }
  const photosDone = await broker.read(base);
  assert.equal(photosDone.photoComplete, true);
  assert.equal(photosDone.version, 1 + captures.length);
  await broker.record({ ...base, version: photosDone.version, operationId: '2'.repeat(32), action: 'meters',
    payload: { noGas: true, electricity: { reading: '14582', checkId: meterIds.electricity }, water: { reading: '3210', checkId: meterIds.water } } });
  const keys = { personId: 'emulator-tenant', counts: { mainDoor: 2, bedrooms: 0, letterBox: 0, parkingCard: 0 } };
  await database.doc(`rentPaymentAccounts/${hash(['test', base.agreementId, 1, 'emulator-tenant'])}`).set({ depositPaid: true, paidMonths: ['2026-10'] });
  let current = await broker.read(base);
  await assert.rejects(broker.record({ ...base, action: 'keys', version: current.version, operationId: '3'.repeat(32), payload: keys }), { code: 'failed-precondition' });
  await database.doc('payments/pay_emulator_live_fixture').set({ mode: 'live', currency: 'INR', status: 'paid', providerVerified: true, captured: true,
    agreementId: base.agreementId, revision: 1, payerUid: 'emulator-tenant', depositPaise: 4400000, amountPaise: 6600000,
    lines: [{ month: '2026-10', totalPaise: 2200000 }] });
  await database.doc(`rentPaymentAccounts/${hash(['live', base.agreementId, 1, 'emulator-tenant'])}`).set({ depositPaid: true,
    paidMonths: ['2026-10'], firstPaymentMonth: '2026-10', firstPaymentId: 'pay_emulator_live_fixture' });
  await broker.record({ ...base, action: 'keys', version: current.version, operationId: '3'.repeat(32), payload: keys });
  const code = await tenancy('emulator-tenant').issueCode({ ...base, role: 'tenant', countsConfirmed: true });
  current = await broker.read(base);
  assert.equal(current.challenge.codeHash, undefined);
  await broker.record({ ...base, action: 'confirm', version: current.version, operationId: '4'.repeat(32), payload: { code: code.code, challengeId: code.challengeId } });
  assert.equal((await database.doc('properties/emulator-tenancy-flat').get()).data().occupancyStatus, 'rented');
  assert.equal((await database.doc('properties/emulator-tenancy-flat').get()).data().nextInspectionDate, '2027-01-10');
  const sample = first.rooms[0].items[0];
  const state = (await database.doc('tenancies/emulator-tenancy').get()).data();
  const photo = (await database.doc(`properties/${first.propertyId}/photoChecks/${state.photoSlots[`move_in:${sample.id}`]}`).get()).data();
  assert.deepEqual(Buffer.from((await photoService.readPhoto({ propertyId: first.propertyId, checkId: state.photoSlots[`move_in:${sample.id}`] })).base64, 'base64'), png);
  assert.ok(photo.file.generation);
  assert.equal((await database.collection('payouts').where('agreementId', '==', base.agreementId).get()).size, 0);
});
