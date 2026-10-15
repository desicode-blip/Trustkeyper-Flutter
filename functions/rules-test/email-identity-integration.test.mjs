import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { initializeApp as initializeClientApp, deleteApp as deleteClientApp } from 'firebase/app';
import { getAuth as getClientAuth, connectAuthEmulator, signInWithCustomToken,
  linkWithCredential, PhoneAuthCredential, signInWithCredential, signOut } from 'firebase/auth';
import { createEmailTokenIssuer } from '../email-identity.js';
import { createProfileEmailBinding } from '../profile-email.js';
import { verifiedPhone } from '../verified-phone.js';

test('actual Firebase custom email tokens preserve linked phone proof and never borrow profile text', async () => {
  assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '', /^127\.0\.0\.1:9099$/);
  const projectId = 'demo-trustkeyper-rules';
  const adminApp = initializeApp({ projectId }, 'email-token-integration');
  const auth = getAuth(adminApp);
  const clientApp = initializeClientApp({ projectId, apiKey: 'emulator-only-key' }, 'email-token-client');
  const client = getClientAuth(clientApp);
  connectAuthEmulator(client, 'http://127.0.0.1:9099', { disableWarnings: true });
  const accounts = [];
  try {
    const linked = await auth.createUser({ uid: 'email-linked-fixture', email: 'linked@example.com',
      emailVerified: false, phoneNumber: '+918000000001' });
    accounts.push(linked.uid);
    const issue = createEmailTokenIssuer({ auth, getProfile: async () => ({ roles: ['owner'], phone: '+918000000009' }) });
    const issued = await issue(linked.email);
    const login = await signInWithCustomToken(client, issued.customToken);
    const token = await login.user.getIdTokenResult();
    assert.equal(login.user.uid, linked.uid);
    assert.equal(token.claims.email_verified, true);
    assert.equal(token.claims.firebase.sign_in_provider, 'custom');
    assert.equal(token.claims.phone_number, '+918000000001');
    assert.equal(verifiedPhone({ uid: login.user.uid, token: token.claims }), '+918000000001');
    const created = await issue('email-only@example.com');
    const emailOnly = await signInWithCustomToken(client, created.customToken);
    accounts.push(emailOnly.user.uid);
    const emailToken = await emailOnly.user.getIdTokenResult();
    assert.equal(emailToken.claims.email_verified, true);
    assert.equal(emailToken.claims.trustkeyper_email_otp, true);
    assert.equal(verifiedPhone({ uid: emailOnly.user.uid, token: emailToken.claims }), null);
  } finally {
    for (const uid of accounts) await auth.deleteUser(uid);
    await deleteClientApp(clientApp);
    await deleteApp(adminApp);
  }
});

test('email-first and phone-first verified identities return to exactly the same Firebase UID', async () => {
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  const projectId = 'demo-trustkeyper-rules';
  const adminApp = initializeApp({ projectId }, 'bidirectional-link-admin');
  const auth = getAuth(adminApp);
  const clientApp = initializeClientApp({ projectId, apiKey: 'emulator-only-key' }, 'bidirectional-link-client');
  const client = getClientAuth(clientApp);
  connectAuthEmulator(client, 'http://127.0.0.1:9099', { disableWarnings: true });
  const accounts = [];
  const issue = createEmailTokenIssuer({ auth, getProfile: async () => undefined });
  async function phoneCredential(phone) {
    const sent = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=emulator-only-key', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phoneNumber: phone }),
    });
    assert.equal(sent.status, 200);
    const { sessionInfo } = await sent.json();
    const codes = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${projectId}/verificationCodes`);
    assert.equal(codes.status, 200);
    const code = (await codes.json()).verificationCodes.find(entry => entry.sessionInfo === sessionInfo);
    assert.ok(code);
    const credential = PhoneAuthCredential.fromJSON({ verificationId: sessionInfo, verificationCode: code.code });
    assert.ok(credential);
    return credential;
  }
  try {
    const first = await signInWithCustomToken(client, (await issue('email-first-link@example.com')).customToken);
    const emailUid = first.user.uid;
    accounts.push(emailUid);
    await linkWithCredential(first.user, await phoneCredential('+918000000021'));
    assert.equal(client.currentUser.uid, emailUid);
    assert.equal((await auth.getUser(emailUid)).phoneNumber, '+918000000021');
    const linkedToken = await client.currentUser.getIdTokenResult(true);
    assert.equal(verifiedPhone({ uid: emailUid, token: linkedToken.claims }), '+918000000021');
    await signOut(client);
    const phoneLogin = await signInWithCredential(client, await phoneCredential('+918000000021'));
    assert.equal(phoneLogin.user.uid, emailUid);
    assert.equal(phoneLogin.user.email, 'email-first-link@example.com');
    await signOut(client);
    const emailLogin = await signInWithCustomToken(client, (await issue('email-first-link@example.com')).customToken);
    assert.equal(emailLogin.user.uid, emailUid);
    const token = await emailLogin.user.getIdTokenResult();
    assert.equal(verifiedPhone({ uid: emailUid, token: token.claims }), '+918000000021');

    const phoneFirst = await signInWithCredential(client, await phoneCredential('+918000000022'));
    const phoneUid = phoneFirst.user.uid;
    accounts.push(phoneUid);
    const binding = createProfileEmailBinding({ auth, uid: phoneUid,
      authTime: Math.floor(Date.now() / 1000), getProfile: async () => undefined,
      updateProfile: async () => assert.fail('No profile exists yet'),
    });
    await binding.link('phone-first-link@example.com');
    await signOut(client);
    const linkedEmail = await signInWithCustomToken(client, (await issue('phone-first-link@example.com')).customToken);
    assert.equal(linkedEmail.user.uid, phoneUid);
    await signOut(client);
    const linkedPhone = await signInWithCredential(client, await phoneCredential('+918000000022'));
    assert.equal(linkedPhone.user.uid, phoneUid);
    assert.equal(linkedPhone.user.email, 'phone-first-link@example.com');
    await signOut(client);
    const unrelated = await signInWithCustomToken(client, (await issue('unrelated-link@example.com')).customToken);
    accounts.push(unrelated.user.uid);
    const conflictingCredential = await phoneCredential('+918000000021');
    await assert.rejects(linkWithCredential(unrelated.user, conflictingCredential), error =>
      ['auth/credential-already-in-use', 'auth/account-exists-with-different-credential'].includes(error.code));
    assert.equal(client.currentUser.uid, unrelated.user.uid);
    assert.equal((await auth.getUser(emailUid)).email, 'email-first-link@example.com');
    assert.equal((await auth.getUser(unrelated.user.uid)).phoneNumber, undefined);
  } finally {
    for (const uid of accounts) await auth.deleteUser(uid);
    await deleteClientApp(clientApp);
    await deleteApp(adminApp);
  }
});
