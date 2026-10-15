import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeApp as initializeClientApp, deleteApp as deleteClientApp } from 'firebase/app';
import { getAuth as getClientAuth, connectAuthEmulator, PhoneAuthCredential, signInWithCredential,
  signInWithCustomToken, signOut } from 'firebase/auth';
import { createAccountEmailBinding } from '../account-email.js';
import { createEmailOtpService } from '../email-otp.js';
import { createEmailTokenIssuer } from '../email-identity.js';

test('normal verified email editing, email login and phone OTP retain one Auth UID and its Firestore records', async () => {
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  const projectId = 'demo-trustkeyper-rules';
  const adminApp = initializeApp({ projectId }, 'account-email-admin');
  const clientApp = initializeClientApp({ projectId, apiKey: 'emulator-only-key' }, 'account-email-client');
  const auth = getAuth(adminApp), database = getFirestore(adminApp), client = getClientAuth(clientApp);
  connectAuthEmulator(client, 'http://127.0.0.1:9099', { disableWarnings: true });
  const uid = 'account-email-e2e', phone = '+918000000046';
  const oldEmail = 'account-email-old@example.invalid', email = 'account-email-new@example.invalid';
  const paths = [`users/${uid}`, 'agreements/account-email-retained'];
  const challenges = new Set();
  const getProfile = async person => (await database.doc(`users/${person}`).get()).data();
  const store = { transaction: handler => database.runTransaction(transaction => handler({
    get: async path => (await transaction.get(database.doc(path))).data(),
    set: (path, values) => { challenges.add(path); transaction.set(database.doc(path), values); },
  })) };
  async function phoneLogin() {
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=emulator-only-key',
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ phoneNumber: phone }) });
    assert.equal(response.ok, true);
    const { sessionInfo } = await response.json();
    const codes = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${projectId}/verificationCodes`);
    const code = (await codes.json()).verificationCodes.find(value => value.sessionInfo === sessionInfo);
    const credential = PhoneAuthCredential.fromJSON({ verificationId: sessionInfo, verificationCode: code.code });
    return signInWithCredential(client, credential);
  }
  try {
    await auth.createUser({ uid, phoneNumber: phone, email: oldEmail, emailVerified: true });
    await database.doc(paths[0]).set({ roles: ['broker', 'owner'], approvalStatus: 'approved', email: oldEmail });
    await database.doc(paths[1]).set({ participantUids: [uid], status: 'completed' });
    const login = await phoneLogin();
    const claims = (await login.user.getIdTokenResult()).claims;
    const binding = await createAccountEmailBinding({ auth, uid, authTime: claims.auth_time, getProfile,
      updateProfile: (person, address) => database.doc(`users/${person}`).update({ email: address }) }, email);
    let delivered;
    const service = createEmailOtpService({ store, purpose: 'account-email', subjectUid: uid,
      subjectContext: binding.identityContext, secret: 'account-email-emulator-only-secret-at-least-32-characters',
      sendMail: async message => { delivered = message; }, issueToken: binding.link });
    const challenge = await service.request({ email, ip: 'email-emulator-only' });
    assert.equal((await auth.getUser(uid)).email, oldEmail);
    await assert.rejects(service.verify({ email, ...challenge, code: 'not-a-code' }), { code: 'invalid-argument' });
    const verified = await service.verify({ email, ...challenge, code: delivered.code });
    const refreshed = await signInWithCustomToken(client, verified.customToken);
    assert.equal(refreshed.user.uid, uid);
    assert.equal(refreshed.user.email, email);
    assert.equal(refreshed.user.phoneNumber, phone);
    assert.equal(refreshed.user.emailVerified, true);
    await assert.rejects(auth.getUserByEmail(oldEmail), { code: 'auth/user-not-found' });
    assert.equal((await auth.getUserByEmail(email)).uid, uid);
    await signOut(client);
    const issuer = createEmailTokenIssuer({ auth, getProfile });
    const emailSession = await issuer(email);
    assert.equal((await signInWithCustomToken(client, emailSession.customToken)).user.uid, uid);
    await signOut(client);
    assert.equal((await phoneLogin()).user.uid, uid);
    assert.deepEqual((await getProfile(uid)).roles, ['broker', 'owner']);
    assert.equal((await getProfile(uid)).approvalStatus, 'approved');
    assert.deepEqual((await database.doc(paths[1]).get()).data().participantUids, [uid]);
  } finally {
    await Promise.all([...paths, ...challenges].map(path => database.doc(path).delete()));
    await auth.deleteUser(uid).catch(() => {});
    await signOut(client);
    await Promise.all([deleteClientApp(clientApp), deleteApp(adminApp)]);
  }
});
