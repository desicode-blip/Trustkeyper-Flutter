import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { doc, getDoc, updateDoc, setDoc, serverTimestamp } from 'firebase/firestore';
import { createAgreementRenewalService } from '../agreement-renewals.js';
import { reviewSnapshot } from '../agreement-review.js';
import { approvalDigest } from '../agreement-approvals.js';

let app;
let database;
let environment;
before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  environment = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-rules', firestore: {
    host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  } });
  app = initializeApp({ projectId: 'demo-trustkeyper-rules' }, 'renewal-emulator');
  database = getFirestore(app);
});
after(async () => { await environment?.cleanup(); if (app) await deleteApp(app); });

test('real renewal transaction isolates the draft, freezes linkage/start and rejects client-forged renewals', async () => {
  const owner = { id: 'renew-owner', name: 'TEST Owner', phone: '+911111111111', email: '', rentSharePaise: 0, depositSharePaise: 0 };
  const tenant = { id: 'renew-tenant', name: 'TEST Tenant', phone: '+912222222222', email: '', rentSharePaise: 2200000, depositSharePaise: 4400000 };
  const source = { schemaVersion: 2, propertyId: 'renew-home', propertyAddress: 'TEST 402, Emulator Towers',
    brokerUid: 'renew-broker', participantUids: ['renew-broker', 'renew-owner', 'renew-tenant'], status: 'active', revision: 1,
    owners: [owner], tenants: [tenant], monthlyRentPaise: 2200000, monthlyMaintenancePaise: 0,
    securityDepositPaise: 4400000, ownerBrokeragePaise: 0, tenantBrokeragePaise: 0,
    startDateISO: '2025-11-01T00:00:00.000', endDateISO: '2026-09-30T00:00:00.000', rentDueDay: 5, lockInMonths: 6, noticeMonths: 1 };
  const digest = approvalDigest(reviewSnapshot(source));
  source.agreementCopy = { agreementId: 'renew-source', revision: 1, mode: 'externally_signed', digest,
    uploadId: 'emulator-original', file: { generation: 'EMULATOR-ONLY', sha256: 'a'.repeat(64) } };
  await database.doc('agreements/renew-source').set(source);
  await database.doc('properties/renew-home').set({ brokerUid: 'renew-broker', participantUids: source.participantUids });
  await database.doc('users/renew-broker').set({ roles: ['broker'], approvalStatus: 'approved' });
  await database.doc('users/renew-owner').set({ roles: ['owner'] });
  const service = createAgreementRenewalService({ auth: { uid: 'renew-broker' }, store: {
    timestamp: () => FieldValue.serverTimestamp(), transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
      update: (path, data) => transaction.update(database.doc(path), data),
    })),
  } });
  const input = { sourceAgreementId: 'renew-source', revision: 1, digest, operationId: 'd'.repeat(32) };
  const result = await service.create(input);
  assert.equal((await service.create({ ...input, operationId: 'e'.repeat(32) })).agreementId, result.agreementId);
  const broker = environment.authenticatedContext('renew-broker').firestore();
  const ownerDatabase = environment.authenticatedContext('renew-owner').firestore();
  const reference = doc(broker, `agreements/${result.agreementId}`);
  await assertSucceeds(getDoc(reference));
  await assertFails(getDoc(doc(ownerDatabase, `agreements/${result.agreementId}`)));
  await assertFails(updateDoc(reference, { renewalSourceId: 'another', revision: 2 }));
  await assertFails(updateDoc(reference, { startDateISO: '2026-09-01T00:00:00.000', revision: 2 }));
  await assertFails(updateDoc(reference, { propertyId: 'another-home', revision: 2 }));
  await assertSucceeds(updateDoc(reference, { monthlyMaintenancePaise: 100000, revision: 2, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(broker, 'agreements/renew-source'), { activeRenewalId: 'forged' }));
  const draft = (await database.doc(`agreements/${result.agreementId}`).get()).data();
  await assertFails(setDoc(doc(broker, 'agreements/forged-renewal'), { ...draft, revision: 1,
    effectiveDate: draft.effectiveDate.toDate(), endDate: draft.endDate.toDate(),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  assert.equal(draft.agreementCopy, undefined);
  assert.deepEqual(draft.participantUids, ['renew-broker']);
  assert.equal((await database.doc('agreements/renew-source').get()).data().status, 'active');
});
