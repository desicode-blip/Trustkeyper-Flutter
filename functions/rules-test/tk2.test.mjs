// TrustKeeper 2 Firestore rules. Run: firebase emulators:exec --only firestore "npm --prefix functions run test:rules"
import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp } from 'firebase/firestore';

let env;
const pub = { id: 'l1', t: 'Prestige Highfield', a: 'Gachibowli, Hyderabad', r: '2 BHK', rent: 30000, fee: 150, bn: 'Suresh', brokerUid: 'broker', active: true };
const db = uid => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-tk2',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
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

test('owner invite: owner claims it once and adds the house under the broker', async () => {
  await assertSucceeds(getDoc(doc(db(), 'tk2Invites/i1')));
  await assertFails(setDoc(doc(db('owner'), 'tk2Listings/o1'), { ...pub, id: 'o1', ownerUid: 'owner', inviteId: 'i1' }));
  await assertSucceeds(updateDoc(doc(db('owner'), 'tk2Invites/i1'), { ownerUid: 'owner', ownerName: 'Hari' }));
  await assertFails(updateDoc(doc(db('stranger'), 'tk2Invites/i1'), { ownerUid: 'stranger' }));
  await assertSucceeds(setDoc(doc(db('owner'), 'tk2Listings/o1'), { ...pub, id: 'o1', ownerUid: 'owner', inviteId: 'i1' }));
  await assertSucceeds(setDoc(doc(db('owner'), 'tk2Private/o1'), { brokerUid: 'broker', ownerUid: 'owner', listing: { door: '402' } }));
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Private/o1')));
  await assertFails(getDoc(doc(db('stranger'), 'tk2Private/o1')));
});

test('visit: tenant books at the listed fee; broker cannot mark it done or read the code', async () => {
  const visit = { listingId: 'l1', brokerUid: 'broker', customerUid: 'tenant', customerName: 'Ravi', customerPhone: '+91 90000 00000',
    at: Date.now() + 86400000, fee: 150, status: 'booked', createdAt: serverTimestamp() };
  await assertFails(setDoc(doc(db('tenant'), 'tk2Visits/cheap'), { ...visit, fee: 0 }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Visits/fake'), { ...visit, brokerUid: 'other' }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Visits/done'), { ...visit, status: 'done' }));
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'tk2Listings/off'), { ...pub, id: 'off', active: false }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Visits/offv'), { ...visit, listingId: 'off' }));
  await assertSucceeds(setDoc(doc(db('tenant'), 'tk2Visits/v1'), visit));
  await assertSucceeds(setDoc(doc(db('tenant'), 'tk2Visits/v1/secret/code'), { code: '4821' }));
  await assertFails(getDoc(doc(db('broker'), 'tk2Visits/v1/secret/code')));
  await assertSucceeds(getDoc(doc(db('tenant'), 'tk2Visits/v1/secret/code')));
  await assertSucceeds(getDoc(doc(db('broker'), 'tk2Visits/v1')));
  await assertFails(getDoc(doc(db('other'), 'tk2Visits/v1')));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Visits/v1'), { status: 'done' }));
  await assertSucceeds(updateDoc(doc(db('broker'), 'tk2Visits/v1'), { gatePass: 'https://example.test/pass.jpg' }));
  // Within 5 minutes the tenant gets the refund status.
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Visits/v1'), { status: 'customerCancelled' }));
  // After 5 minutes only the late cancel (no refund) is allowed.
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Visits/old'), { status: 'customerCancelled' }));
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Visits/old'), { status: 'customerCancelledLate' }));
  await assertFails(deleteDoc(doc(db('broker'), 'tk2Visits/old')));
});

test('tenant journey: the tenant writes their own; the broker of the house reads it', async () => {
  const trip = { customerUid: 'tenant', brokerUid: 'broker', listingId: 'l1', answers: { step: 2 } };
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

test('deal: tenant starts it at the listed token; each person writes only their own part; owner claims once', async () => {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'tk2Listings/d1'), { ...pub, id: 'd1', tk: 20000 }));
  const deal = { listingId: 'd1', brokerUid: 'broker', tenantUid: 'tenant', ownerUid: null, title: '2 BHK', token: 20000, rent: 30000, deposit: 60000, b: {}, t: { tokenPaid: true }, o: {} };
  await assertFails(setDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { ...deal, token: 100 }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { ...deal, brokerUid: 'other' }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { ...deal, b: { docsOk: { tenant: true } } }));
  await assertFails(setDoc(doc(db('tenant'), 'tk2Deals/other_d1'), deal));
  await assertSucceeds(setDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), deal));
  // Own part only.
  await assertSucceeds(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { t: { tokenPaid: true, docsAt: 5 } }));
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { b: { docsOk: { tenant: true } } }));
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { token: 1 }));
  await assertSucceeds(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { b: { docsOk: { tenant: true } }, ownerName: 'Hari' }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { t: { paid: true } }));
  await assertFails(updateDoc(doc(db('broker'), 'tk2Deals/tenant_d1'), { o: { feePaid: true } }));
  // Owner: claims from the link once, then writes only 'o'.
  await assertFails(updateDoc(doc(db('tenant'), 'tk2Deals/tenant_d1'), { ownerUid: 'tenant' }));
  await assertFails(updateDoc(doc(db('owner'), 'tk2Deals/tenant_d1'), { o: { feePaid: true } }));
  await assertSucceeds(getDoc(doc(db('owner'), 'tk2Deals/tenant_d1')));
  await assertSucceeds(updateDoc(doc(db('owner'), 'tk2Deals/tenant_d1'), { ownerUid: 'owner' }));
  await assertFails(updateDoc(doc(db('stranger'), 'tk2Deals/tenant_d1'), { ownerUid: 'stranger' }));
  await assertFails(getDoc(doc(db('stranger'), 'tk2Deals/tenant_d1')));
  await assertSucceeds(updateDoc(doc(db('owner'), 'tk2Deals/tenant_d1'), { o: { reply: { v: 1, ok: true } } }));
  await assertFails(updateDoc(doc(db('owner'), 'tk2Deals/tenant_d1'), { t: { paid: true } }));
  await assertFails(deleteDoc(doc(db('broker'), 'tk2Deals/tenant_d1')));
  // The broker can start one after a visit, with nothing filled for the others.
  await assertSucceeds(setDoc(doc(db('broker'), 'tk2Deals/b1'), { ...deal, tenantUid: 'tenant2', t: {} }));
  await assertFails(setDoc(doc(db('broker'), 'tk2Deals/b2'), { ...deal, tenantUid: 'tenant2' }));
});

test('society playbook: first broker creates it; later edits only propose', async () => {
  await assertSucceeds(setDoc(doc(db('broker'), 'tk2Playbooks/prestige-highfield'), { name: 'Prestige Highfield', brokerUid: 'broker', checked: false, steps: [{ k: 'email' }] }));
  await assertFails(setDoc(doc(db('other'), 'tk2Playbooks/x'), { name: 'X', brokerUid: 'other', checked: true, steps: [] }));
  await assertSucceeds(getDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield')));
  await assertFails(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { steps: [] }));
  await assertFails(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { checked: true }));
  await assertSucceeds(updateDoc(doc(db('other'), 'tk2Playbooks/prestige-highfield'), { proposed: { brokerUid: 'other', steps: [{ k: 'visit' }] } }));
});
