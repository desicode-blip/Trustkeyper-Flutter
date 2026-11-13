// TrustKeeper 2 Firestore rules. Run: firebase emulators:exec --only firestore "npm --prefix functions run test:rules"
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp, where, writeBatch } from 'firebase/firestore';
import { getBytes, getDownloadURL, ref, uploadBytes } from 'firebase/storage';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { createTk2FileFinalizer } from '../tk2.js';

let env;
const projectId = process.env.GCLOUD_PROJECT ?? 'demo-trustkeyper-tk2';
const pub = { id: 'l1', t: 'Prestige Highfield', a: 'Gachibowli, Hyderabad', r: '2 BHK', rent: 30000, fee: 150, bn: 'Suresh', brokerUid: 'broker', active: true };
const context = (uid, claims) => uid ? env.authenticatedContext(uid, claims) : env.unauthenticatedContext();
const db = (uid, claims) => context(uid, claims).firestore();
const phone = '+919000000123';
const phoneProof = { phone_number: phone, firebase: { sign_in_provider: 'phone' } };
const ownerEmail = 'owner@example.test';
const emailProof = { email: ownerEmail, email_verified: true, firebase: { sign_in_provider: 'custom' } };

before(async () => {
  assert.match(projectId, /^demo-/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  env = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile(new URL('../../storage.rules', import.meta.url), 'utf8') } });
  await env.withSecurityRulesDisabled(async context => {
    const f = context.firestore();
    await setDoc(doc(f, 'tk2Listings/l1'), pub);
    await setDoc(doc(f, 'tk2Private/l1'), { brokerUid: 'broker', listing: { door: 'B-1204', ownerName: 'Hari' } });
    await setDoc(doc(f, 'tk2Invites/i1'), { brokerUid: 'broker', brokerName: 'Suresh', houseName: 'Flat 402' });
    await setDoc(doc(f, 'tk2Visits/old'), { listingId: 'l1', brokerUid: 'broker', customerUid: 'tenant', status: 'booked', fee: 150,
      at: 1, createdAt: Timestamp.fromMillis(Date.now() - 10 * 60 * 1000) });
  });
});
after(async () => env?.cleanup());

test('public listing: anyone reads one by id; only the broker writes; private fields are refused', async () => {
  await assertSucceeds(getDoc(doc(db(), 'tk2Listings/l1')));
  await assertSucceeds(setDoc(doc(db('broker'), 'tk2Listings/l2'), { ...pub, id: 'l2' }));
  await assertFails(setDoc(doc(db('broker'), 'tk2Listings/l3'), { ...pub, id: 'l3', door: 'B-1204' }));
  await assertFails(setDoc(doc(db('broker'), 'tk2Listings/l4'), { ...pub, id: 'l4', fee: 900 }));
  await assertFails(setDoc(doc(db('other'), 'tk2Listings/l5'), { ...pub, id: 'l5' }));
  await assertFails(updateDoc(doc(db('other'), 'tk2Listings/l1'), { rent: 1 }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Listings/l1'), { brokerUid: 'other' }));
  await assertSucceeds(updateDoc(doc(db('broker'), 'tk2Listings/l1'), { rent: 31000 }));
});

test('private listing (door no., owner, keys): broker only', async () => {
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Private/l1')));
  for (const uid of [null, 'tenant', 'other']) await assertFails(getDoc(doc(db(uid), 'tk2Private/l1')));
  await assertFails(setDoc(doc(db('other'), 'tk2Private/l1x'), { brokerUid: 'other' }));
});

test('owner invite: a forwarded link cannot be opened or claimed with a different identity', async () => {
  const invite = 'tk2Invites/bound';
  const listing = { ...pub, id: 'o1', ownerUid: 'owner', inviteId: 'bound' };
  const owner = db('owner', emailProof);
  await assertFails(updateDoc(doc(owner, 'tk2Invites/i1'), { ownerUid: 'owner' }));
  await assertSucceeds(setDoc(doc(db('broker'), invite), { brokerUid: 'broker', houseName: 'Flat 402', recipient: ownerEmail }));
  await assertFails(getDoc(doc(db(), invite)));
  for (const user of [db('stranger', phoneProof), db('owner', { ...emailProof, email_verified: false })]) {
    await assertFails(getDoc(doc(user, invite)));
    await assertFails(updateDoc(doc(user, invite), { ownerUid: 'owner' }));
  }
  await assertFails(updateDoc(doc(db('broker'), invite), { recipient: 'wrong@example.test' }));
  await assertFails(setDoc(doc(owner, 'tk2Listings/o1'), listing));
  await assertSucceeds(getDoc(doc(owner, invite)));
  await assertSucceeds(updateDoc(doc(owner, invite), { ownerUid: 'owner', ownerName: 'Hari' }));
  await assertFails(updateDoc(doc(db('stranger', emailProof), invite), { ownerUid: 'stranger' }));
  const photo = 'tk2/listings/o1/photo.png';
  const image = new Uint8Array([137, 80, 78, 71]);
  const ownerStorage = context('owner', emailProof).storage();
  await assertFails(uploadBytes(ref(ownerStorage, photo), image, { contentType: 'image/png' }));
  await assertSucceeds(setDoc(doc(owner, 'tk2Listings/o1'), { ...listing, active: false }));
  await assertSucceeds(uploadBytes(ref(ownerStorage, photo), image, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(context('stranger').storage(), photo), image, { contentType: 'image/png' }));
  const batch = writeBatch(owner);
  batch.set(doc(owner, 'tk2Listings/o1'), listing);
  batch.set(doc(owner, 'tk2Private/o1'), { brokerUid: 'broker', ownerUid: 'owner', inviteId: 'bound', listing: { door: '402' } });
  batch.update(doc(owner, invite), { listingId: 'o1' });
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(owner, invite), { listingId: 'other' }));
  await assertFails(setDoc(doc(owner, 'tk2Listings/o2'), { ...listing, id: 'o2' }));
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Private/o1')));
  await assertFails(getDoc(doc(db('stranger'), 'tk2Private/o1')));
  await assertFails(updateDoc(doc(owner, 'tk2Private/o1'), { ownerContact: phone }));
  await assertFails(setDoc(doc(db('broker'), 'tk2Listings/forged'), { ...listing, id: 'forged' }));

  const phoneInvite = 'tk2Invites/by-phone';
  await assertSucceeds(setDoc(doc(db('broker'), phoneInvite), { brokerUid: 'broker', recipient: phone }));
  await assertFails(updateDoc(doc(db('owner', { phone_number: phone }), phoneInvite), { ownerUid: 'owner' }));
  await assertSucceeds(updateDoc(doc(db('phone-owner', phoneProof), phoneInvite), { ownerUid: 'phone-owner' }));
});

test('visit: tenant books at the listed fee; broker cannot mark it done or read the code', async () => {
  const tenant = db('tenant', phoneProof);
  const visit = { listingId: 'l1', brokerUid: 'broker', customerUid: 'tenant', customerName: 'Ravi', customerPhone: phone,
    at: Date.now() + 86400000, fee: 150, status: 'booked', createdAt: serverTimestamp() };
  function book(database, id, fields = {}) {
    const batch = writeBatch(database);
    batch.set(doc(database, `tk2Visits/${id}`), { ...visit, ...fields });
    batch.set(doc(database, `tk2Visits/${id}/secret/code`), { code: '4821' });
    return batch.commit();
  }
  await assertFails(book(tenant, 'cheap', { fee: 0 }));
  await assertFails(book(tenant, 'fake', { brokerUid: 'other' }));
  await assertFails(book(tenant, 'done', { status: 'done' }));
  await assertFails(book(tenant, 'forged-phone', { customerPhone: '+919000000124' }));
  await assertFails(book(db('tenant'), 'no-otp'));
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'tk2Listings/off'), { ...pub, id: 'off', active: false }));
  await assertFails(book(tenant, 'offv', { listingId: 'off' }));
  await assertFails(setDoc(doc(tenant, 'tk2Visits/no-code'), visit));
  await assertSucceeds(book(tenant, 'v1'));
  await assertFails(getDoc(doc(db('broker'), 'tk2Visits/v1/secret/code')));
  await assertSucceeds(getDoc(doc(db('tenant'), 'tk2Visits/v1/secret/code')));
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Visits/v1')));
  await assertFails(getDoc(doc(db('other'), 'tk2Visits/v1')));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Visits/v1'), { status: 'done' }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Visits/v1'), { failedCodes: 0, codeLockUntil: 0 }));
  await assertSucceeds(updateDoc(doc(db('broker'), 'tk2Visits/v1'), { gatePass: 'https://example.test/pass.jpg' }));
  // Within 5 minutes the tenant gets the refund status.
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Visits/v1'), { status: 'customerCancelledLate' }));
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Visits/v1'), { status: 'customerCancelled' }));
  // After 5 minutes only the late cancel (no refund) is allowed.
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Visits/old'), { status: 'customerCancelled' }));
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Visits/old'), { status: 'customerCancelledLate' }));
  await assertFails(deleteDoc(doc(db('broker'), 'tk2Visits/old')));
});

test('tenant journey: the tenant writes their own; the broker of the house reads it', async () => {
  const trip = { customerUid: 'tenant', brokerUid: 'broker', listingId: 'l1', answers: { step: 2 } };
  await assertFails(setDoc(doc(db('tenant'), 'tk2Trips/tenant_l1'), { ...trip, brokerUid: 'other' }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Trips/other_l1'), trip));
  await assertSucceeds(setDoc(doc(db('tenant'), 'tk2Trips/tenant_l1'), trip));
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Trips/tenant_l1')));
  await assertFails(getDoc(doc(db('other'), 'tk2Trips/tenant_l1')));
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Trips/tenant_l1'), { brokerUid: 'other' }));
});

test('broker profile is private to the broker', async () => {
  await assertSucceeds(setDoc(doc(db('broker'), 'tk2Brokers/broker'), { name: 'Suresh', defaultToken: 15000 }));
  await assertFails(getDoc(doc(db('other'), 'tk2Brokers/broker')));
});

test('deal: each party writes their own part and owner access requires a matching verified identity', async () => {
  const path = 'tk2Deals/tenant_d1';
  const deal = { listingId: 'd1', brokerUid: 'broker', tenantUid: 'tenant', ownerUid: null, title: '2 BHK', token: 20000, rent: 30000, deposit: 60000, b: {}, t: {}, o: {} };
  await assertFails(setDoc(doc(db('tenant'), path), deal));
  await assertFails(setDoc(doc(db('broker'), path), deal));
  await assertFails(setDoc(doc(db('tenant'), path), { ...deal, completion: { t: { tokenPaid: true } } }));
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(), 'tk2Listings/d1'), { ...pub, id: 'd1', tk: 20000 });
    await setDoc(doc(c.firestore(), 'tk2Private/d1'), { brokerUid: 'broker', ownerContact: phone });
    await setDoc(doc(c.firestore(), path), deal);
  });
  // Own part only.
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { t: { docsAt: 5 } }));
  for (const data of [{ t: { paid: true } }, { t: { signed: 'Ravi' } }, { completion: { t: { paid: true } } }]) {
    await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), data));
  }
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { b: { docsOk: { tenant: true } } }));
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { token: 1 }));
  await assertSucceeds(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { b: { docsOk: { tenant: true } }, ownerName: 'Hari' }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { t: { paid: true } }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { o: { feePaid: true } }));
  await assertSucceeds(getDoc(doc(db('broker'), path)));
  await assertSucceeds(getDoc(doc(db('tenant'), path)));
  await assertFails(updateDoc(doc(db('tenant', phoneProof), path), { verifiedOwnerUid: 'tenant' }));
  await assertFails(updateDoc(doc(db('broker', phoneProof), path), { verifiedOwnerUid: 'broker' }));
  await assertFails(updateDoc(doc(db('stranger', { phone_number: phone }), path), { verifiedOwnerUid: 'stranger' }));
  await assertFails(updateDoc(doc(db('stranger', emailProof), path), { verifiedOwnerUid: 'stranger' }));
  await assertFails(getDoc(doc(db('stranger'), path)));
  const owner = db('manual-owner', phoneProof);
  await assertFails(getDoc(doc(owner, path)));
  await assertFails(updateDoc(doc(owner, path), { verifiedOwnerUid: 'manual-owner', o: { paid: true } }));
  const file = 'tk2/deals/tenant_d1/stamp.pdf';
  const brokerStorage = context('broker').storage();
  const data = new Uint8Array([37, 80, 68, 70]);
  await assertFails(uploadBytes(ref(brokerStorage, file), data, { contentType: 'application/pdf' }));
  await assertSucceeds(uploadBytes(ref(brokerStorage, `tk2Uploads/broker/${file}`), data, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(context('stranger').storage(), `tk2Uploads/broker/${file}`), data, { contentType: 'application/pdf' }));
  await assertFails(getDownloadURL(ref(brokerStorage, `tk2Uploads/broker/${file}`)));
  const app = initializeApp({ projectId, storageBucket: projectId }, 'tk2-file-finalizer');
  try {
    const bucket = getStorage(app).bucket();
    const finalize = createTk2FileFinalizer({ getRecord: async () => deal, bucket });
    await assertFails(finalize({ uid: 'stranger' }, file));
    await assertSucceeds(finalize({ uid: 'broker' }, file));
    const [metadata] = await bucket.file(file).getMetadata();
    assert.ok(!metadata.metadata?.firebaseStorageDownloadTokens);
    assert.equal(metadata.cacheControl, 'private, no-store');
    await assertSucceeds(finalize({ uid: 'broker' }, file));
  } finally {
    await deleteApp(app);
  }
  const media = new URL(`http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${projectId}/o/${encodeURIComponent(file)}?alt=media`);
  assert.equal((await fetch(media)).status, 403);
  await assertFails(getBytes(ref(context('manual-owner', phoneProof).storage(), file)));
  await assertSucceeds(updateDoc(doc(owner, path), { verifiedOwnerUid: 'manual-owner' }));
  await assertSucceeds(getDoc(doc(owner, path)));
  await assertSucceeds(getDocs(query(collection(owner, 'tk2Deals'), where('verifiedOwnerUid', '==', 'manual-owner'))));
  await assertFails(getDocs(collection(owner, 'tk2Deals')));
  await assertSucceeds(getBytes(ref(context('manual-owner').storage(), file)));
  await assertSucceeds(getBytes(ref(context('tenant').storage(), file)));
  await assertFails(getBytes(ref(context('stranger').storage(), file)));
  await assertFails(updateDoc(doc(db('stranger', phoneProof), path), { verifiedOwnerUid: 'stranger' }));
  await assertSucceeds(updateDoc(doc(owner, path), { o: { reply: { v: 1, ok: true } } }));
  await assertSucceeds(updateDoc(doc(owner, path), { o: { repairApprovals: { repair: true } } }));
  for (const o of [{ feePaid: true }, { signed: 'Hari' }, { rep: { repair: { paid: true } } }]) {
    await assertFails(updateDoc(doc(owner, path), { o }));
  }
  await assertFails(updateDoc(doc(owner, path), { t: { paid: true } }));
  await assertFails(deleteDoc(doc(db('broker'), 'tk2Deals/tenant_d1')));
});

test('a legacy owner UID does not grant access and invite-based owners can claim their listing deal', async () => {
  const path = 'tk2Deals/tenant_o1';
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), path), {
    listingId: 'o1', brokerUid: 'broker', tenantUid: 'tenant', ownerUid: 'stranger', b: {}, t: {}, o: {},
  }));
  await assertFails(getDoc(doc(db('stranger'), path)));
  await assertFails(updateDoc(doc(db('stranger'), path), { o: { feePaid: true } }));
  await assertFails(updateDoc(doc(db('stranger', emailProof), path), { verifiedOwnerUid: 'stranger' }));
  await assertSucceeds(updateDoc(doc(db('owner', emailProof), path), { verifiedOwnerUid: 'owner' }));
  await assertSucceeds(getDoc(doc(db('owner'), path)));
});

test('society playbook: first broker creates it; later edits only propose', async () => {
  await assertSucceeds(setDoc(doc(db('broker'), 'tk2Playbooks/prestige-highfield'), { name: 'Prestige Highfield', brokerUid: 'broker', checked: false, steps: [{ k: 'email' }] }));
  await assertFails(setDoc(doc(db('other'), 'tk2Playbooks/x'), { name: 'X', brokerUid: 'other', checked: true, steps: [] }));
  await assertSucceeds(getDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield')));
  await assertFails(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { steps: [] }));
  await assertFails(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { checked: true }));
  await assertSucceeds(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { proposed: { brokerUid: 'other', steps: [{ k: 'visit' }] } }));
});
