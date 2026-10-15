import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeApp as initializeClientApp, deleteApp as deleteClientApp } from 'firebase/app';
import { getAuth as getClientAuth, connectAuthEmulator, PhoneAuthCredential, signInWithCredential, signOut } from 'firebase/auth';
import { createAccountProfileService } from '../account-profile.js';
import { createAccountClosureService } from '../account-closure.js';

test('actual phone identity, Firestore transactions, profile persistence, account disable and restoration preserve one customer UID', async () => {
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  const projectId = 'demo-trustkeyper-rules';
  const adminApp = initializeApp({ projectId }, 'account-lifecycle-admin');
  const clientApp = initializeClientApp({ projectId, apiKey: 'emulator-only-key' }, 'account-lifecycle-client');
  const admin = getAuth(adminApp), database = getFirestore(adminApp), client = getClientAuth(clientApp);
  connectAuthEmulator(client, 'http://127.0.0.1:9099', { disableWarnings: true });
  const uid = 'account-close-e2e', adminUid = 'account-close-admin-e2e', phone = '+918000000045';
  const paths = [`users/${uid}`, `users/${adminUid}`, `accountClosures/${uid}`, 'agreements/account-close-retained-e2e'];
  let operation;
  const store = {
    transaction: handler => database.runTransaction(transaction => handler({
      get: async path => (await transaction.get(database.doc(path))).data(),
      set: (path, values) => transaction.set(database.doc(path), values),
      update: (path, values) => transaction.update(database.doc(path), values),
      related: async (collection, field, person, array) => (await transaction.get(database.collection(collection)
        .where(field, array ? 'array-contains' : '==', person).limit(1001))).docs.map(document => document.data()),
    })),
    pending: async () => (await database.collection('accountClosures')
      .where('status', 'in', ['closing', 'closed', 'restoring']).get()).docs.map(document => document.data()),
  };
  const identity = { read: person => admin.getUser(person), updateName: (person, displayName) => admin.updateUser(person, { displayName }),
    disable: person => admin.updateUser(person, { disabled: true }), enable: person => admin.updateUser(person, { disabled: false }),
    revoke: person => admin.revokeRefreshTokens(person) };
  async function credential() {
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=emulator-only-key',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phoneNumber: phone }) });
    assert.equal(response.ok, true);
    const { sessionInfo } = await response.json();
    const codes = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${projectId}/verificationCodes`);
    const code = (await codes.json()).verificationCodes.find(value => value.sessionInfo === sessionInfo);
    assert.ok(code);
    const result = PhoneAuthCredential.fromJSON({ verificationId: sessionInfo, verificationCode: code.code });
    assert.ok(result);
    return result;
  }
  try {
    await admin.createUser({ uid, phoneNumber: phone, email: 'account-close@example.invalid', emailVerified: true });
    await database.doc(`users/${uid}`).set({ roles: ['owner'], displayName: 'TEST original', paused: false });
    await database.doc(`users/${adminUid}`).set({ roles: ['admin'], paused: false });
    const login = await signInWithCredential(client, await credential());
    assert.equal(login.user.uid, uid);
    const claims = (await login.user.getIdTokenResult()).claims;
    const auth = { uid, token: claims };
    const details = createAccountProfileService({ auth, store, identity });
    await details.save({ displayName: 'TEST saved', city: 'TEST Hyderabad', email: 'account-close@example.invalid', reraNumber: '' });
    assert.equal((await details.read()).displayName, 'TEST saved');
    assert.equal((await admin.getUser(uid)).displayName, 'TEST saved');
    const account = createAccountClosureService({ auth, store, identity });
    await database.doc(paths[3]).set({ participantUids: [uid], status: 'active', agreementCopy: { mode: 'externally_signed' } });
    assert.equal((await account.read()).canClose, false);
    await assert.rejects(account.close({ confirmed: true, operationId: 'emulator-close' }));
    assert.equal((await admin.getUser(uid)).disabled, false);
    await database.doc(paths[3]).update({ status: 'completed' });
    assert.equal((await account.close({ confirmed: true, operationId: 'emulator-close' })).closed, true);
    operation = (await database.doc(`accountClosures/${uid}`).get()).data().operation;
    assert.equal((await admin.getUser(uid)).disabled, true);
    assert.equal((await database.doc(`users/${uid}`).get()).data().paused, true);
    assert.equal((await database.doc(paths[3]).get()).exists, true);
    await assert.rejects(details.read(), { code: 'permission-denied' });
    await signOut(client);
    await assert.rejects(signInWithCredential(client, await credential()), { code: 'auth/user-disabled' });
    const team = createAccountClosureService({ auth: { uid: adminUid }, store, identity });
    assert.equal((await team.restore({ uid })).restored, true);
    assert.equal((await admin.getUser(uid)).disabled, false);
    const returned = await signInWithCredential(client, await credential());
    assert.equal(returned.user.uid, uid);
    assert.equal((await details.read()).displayName, 'TEST saved');
    assert.deepEqual((await database.doc(`users/${uid}`).get()).data().roles, ['owner']);
    assert.equal((await team.list()).requests.some(value => value.uid === uid), false);
  } finally {
    if (operation) paths.push(`adminAuditLogs/account_closure_${operation}`, `adminAuditLogs/account_closed_${operation}`, `adminAuditLogs/account_restored_${operation}`);
    await Promise.all(paths.map(path => database.doc(path).delete()));
    await admin.deleteUser(uid).catch(() => {});
    await signOut(client);
    await Promise.all([deleteClientApp(clientApp), deleteApp(adminApp)]);
  }
});
