import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc } from 'firebase/firestore';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { createManagerCallbackService } from '../manager-callbacks.js';

let environment;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-trustkeyper-rules',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    for (const [uid, profile] of [
      ['callback-owner', { roles: ['owner'], phone: '+911111111111' }],
      ['callback-other', { roles: ['owner'], phone: '+913333333333' }],
      ['callback-admin', { roles: ['admin'] }],
      ['callback-paused', { roles: ['owner'], phone: '+914444444444', paused: true }],
    ]) await setDoc(doc(database, `users/${uid}`), profile);
    await setDoc(doc(database, 'ownerCallbacks/callback-owner'), { ownerUid: 'callback-owner', status: 'requested', version: 1 });
    await setDoc(doc(database, 'ownerManagers/callback-owner'), { managerUid: 'callback-admin', email: 'test@trustkeyper.com' });
  });
});
test('actual Firestore transactions persist callback confirmation and missed-call rescheduling without granting property access', async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:/);
  const app = initializeApp({ projectId: 'demo-trustkeyper-rules' }, 'callback-integration');
  try {
    const database = getFirestore(app);
    let clock = Date.parse('2026-10-10T05:30:00Z');
    let operation = 0;
    const store = { transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, data) => transaction.set(database.doc(path), data),
    })) };
    const owner = createManagerCallbackService({ auth: { uid: 'callback-owner', token: { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } } }, store, now: () => clock });
    const team = createManagerCallbackService({ auth: { uid: 'callback-admin' }, store, phoneForUser: async () => '+911111111111', now: () => clock });
    async function save(service, action, payload = {}, admin = false) {
      const version = (await database.doc('ownerCallbacks/callback-owner').get()).data()?.version ?? 0;
      return service.record({ action, payload, version, operationId: (++operation).toString(16).padStart(32, '0'), ...(admin ? { ownerUid: 'callback-owner' } : {}) });
    }
    await save(owner, 'request', { topic: 'tenant', window: 'soon' });
    await save(team, 'assign', { managerUid: 'callback-admin', phone: '+918088516875', email: 'help@trustkeyper.com' }, true);
    await save(team, 'confirm', { scheduledAtMs: clock + 10 * 60000 }, true);
    assert.equal((await owner.read()).callback.status, 'confirmed');
    clock += 10 * 60000;
    await save(team, 'missed', { note: 'TEST called the verified phone; no answer.' }, true);
    assert.equal((await owner.read()).callback.status, 'missed');
    await save(owner, 'request', { topic: 'tenant', window: 'tomorrow_morning' });
    const current = await owner.read();
    assert.equal(current.callback.status, 'requested'); assert.equal(current.callback.scheduledAtMs, null);
    assert.deepEqual((await database.doc('users/callback-owner').get()).data().roles, ['owner']);
    assert.equal((await database.doc('ownerCallbacks/callback-owner').collection('events').get()).size, 5);
  } finally { await deleteApp(app); }
});
after(async () => environment?.cleanup());
test('callback clients read only their own verified-phone request and cannot assign or forge outcomes', async () => {
  const phone = { phone_number: '+911111111111', firebase: { sign_in_provider: 'phone' } };
  const owner = environment.authenticatedContext('callback-owner', phone).firestore();
  const other = environment.authenticatedContext('callback-other', { ...phone, phone_number: '+913333333333' }).firestore();
  const admin = environment.authenticatedContext('callback-admin').firestore();
  const wrongProvider = environment.authenticatedContext('callback-owner', { ...phone, firebase: { sign_in_provider: 'password' } }).firestore();
  await assertSucceeds(getDoc(doc(owner, 'ownerCallbacks/callback-owner')));
  await assertSucceeds(getDoc(doc(admin, 'ownerCallbacks/callback-owner')));
  for (const database of [other, wrongProvider, environment.unauthenticatedContext().firestore(),
    environment.authenticatedContext('callback-paused', { ...phone, phone_number: '+914444444444' }).firestore()]) {
    await assertFails(getDoc(doc(database, 'ownerCallbacks/callback-owner')));
  }
  for (const database of [owner, admin]) {
    await assertFails(setDoc(doc(database, 'ownerCallbacks/callback-owner'), { status: 'completed', version: 99 }));
    for (const path of ['ownerManagers/callback-owner', 'callbackOperations/private', 'callbackLimits/callback-owner', 'ownerCallbacks/callback-owner/events/private']) {
      await assertFails(getDoc(doc(database, path)));
      await assertFails(setDoc(doc(database, path), { forged: true }));
    }
  }
});
