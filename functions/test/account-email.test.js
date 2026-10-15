import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAccountEmailBinding } from '../account-email.js';
import { createEmailOtpService } from '../email-otp.js';

function fixture(options = {}) {
  const user = { uid: 'customer', email: 'old@example.com', emailVerified: true,
    phoneNumber: '+918000000046', ...options.user };
  const profile = { roles: ['broker', 'owner'], approvalStatus: 'approved', displayName: 'TEST', ...options.profile };
  const documents = new Map(), messages = [], tokens = [];
  let time = 100000, sequence = 0, profileFailure = false;
  const auth = {
    getUser: async uid => { assert.equal(uid, user.uid); return { ...user }; },
    getUserByEmail: async email => {
      if (options.collision) return { uid: 'other-customer' };
      if (user.email === email) return { ...user };
      throw Object.assign(new Error('Missing'), { code: 'auth/user-not-found' });
    },
    updateUser: async (uid, values) => {
      assert.equal(uid, user.uid);
      if (options.updateCollision) throw Object.assign(new Error('Collision'), { code: 'auth/email-already-exists' });
      Object.assign(user, values);
    },
    createCustomToken: async (uid, claims) => { tokens.push({ uid, claims }); return 'emulator-test-token'; },
  };
  const bindingOptions = { auth, uid: user.uid, authTime: options.authTime ?? 100, now: () => time,
    getProfile: async () => profile,
    updateProfile: async (uid, email) => {
      if (profileFailure) throw new Error('Profile unavailable');
      assert.equal(uid, user.uid); profile.email = email;
    } };
  async function service(email) {
    const binding = await createAccountEmailBinding(bindingOptions, email);
    return createEmailOtpService({ purpose: 'account-email', subjectUid: binding.uid, subjectContext: binding.identityContext,
      secret: 'account-email-test-secret-at-least-32-characters', now: () => time,
      generateCode: () => '123456', generateId: () => `account-challenge-${++sequence}`,
      store: { transaction: handler => handler({ get: async path => documents.get(path),
        set: (path, data) => documents.set(path, structuredClone(data)) }) },
      sendMail: async message => messages.push(message), issueToken: binding.link });
  }
  return { user, profile, documents, messages, tokens, bindingOptions,
    advance: milliseconds => { time += milliseconds; },
    failProfile: value => { profileFailure = value; },
    request: async email => (await service(email)).request({ email, ip: 'emulator' }),
    verify: async (email, challenge, code = '123456') => (await service(email)).verify({ email, ...challenge, code }) };
}

test('verified account email editing keeps the same phone UID, roles and saved profile', async () => {
  const flow = fixture();
  const challenge = await flow.request('new@example.com');
  assert.equal(flow.user.email, 'old@example.com');
  const result = await flow.verify('new@example.com', challenge);
  assert.deepEqual(result, { uid: 'customer', email: 'new@example.com', verified: true, customToken: 'emulator-test-token' });
  assert.equal(flow.user.uid, 'customer');
  assert.equal(flow.user.phoneNumber, '+918000000046');
  assert.equal(flow.profile.email, 'new@example.com');
  assert.deepEqual(flow.profile.roles, ['broker', 'owner']);
  assert.equal(flow.profile.approvalStatus, 'approved');
  assert.deepEqual(flow.tokens, [{ uid: 'customer', claims: {
    trustkeyper_email_otp: true, trustkeyper_verified_phone: '+918000000046',
  } }]);
  await assert.rejects(flow.verify('new@example.com', challenge), { code: 'failed-precondition' });
});

test('wrong code, changed address and another UID cannot change the verified identity', async () => {
  const flow = fixture();
  const challenge = await flow.request('new@example.com');
  await assert.rejects(flow.verify('new@example.com', challenge, '000000'), { code: 'invalid-argument' });
  await assert.rejects(flow.verify('wrong@example.com', challenge), { code: 'failed-precondition' });
  const stranger = { ...flow.bindingOptions, uid: 'stranger', auth: {
    ...flow.bindingOptions.auth, getUser: async () => ({ ...flow.user, uid: 'stranger' }),
  } };
  const binding = await createAccountEmailBinding(stranger, 'new@example.com');
  const service = createEmailOtpService({ purpose: 'account-email', subjectUid: binding.uid,
    subjectContext: binding.identityContext, secret: 'account-email-test-secret-at-least-32-characters', now: () => 100000,
    store: { transaction: handler => handler({ get: async path => flow.documents.get(path), set: () => assert.fail('No write') }) },
    issueToken: () => assert.fail('No identity change'), sendMail: () => assert.fail('No email') });
  await assert.rejects(service.verify({ email: 'new@example.com', ...challenge, code: '123456' }), { code: 'failed-precondition' });
  assert.equal(flow.user.email, 'old@example.com');
  assert.equal(flow.tokens.length, 0);
});

test('account change codes expire when the original email or verified phone changes', async () => {
  for (const field of ['email', 'phoneNumber']) {
    const flow = fixture();
    const challenge = await flow.request('new@example.com');
    flow.user[field] = field === 'email' ? 'changed@example.com' : '+918000000047';
    await assert.rejects(flow.verify('new@example.com', challenge), { code: 'failed-precondition' });
    assert.equal(flow.tokens.length, 0);
  }
});

test('fresh customer authentication is required and admin/closed/unconfigured accounts are denied', async () => {
  for (const options of [{ authTime: -900 }, { user: { disabled: true } }, { profile: { paused: true } },
    { profile: { roles: ['admin', 'broker'] } }, { profile: { roles: [] } }, { user: { phoneNumber: null } },
    { user: { customClaims: { admin: true } } }]) {
    const flow = fixture(options);
    await assert.rejects(flow.request('new@example.com'));
    assert.equal(flow.messages.length, 0);
    assert.equal(flow.user.email, 'old@example.com');
  }
});

test('an existing different identity and an Auth collision never merge accounts', async () => {
  const duplicate = fixture({ collision: true });
  await assert.rejects(duplicate.request('new@example.com'), { code: 'already-exists' });
  assert.equal(duplicate.messages.length, 0);
  const concurrent = fixture({ updateCollision: true });
  const challenge = await concurrent.request('new@example.com');
  await assert.rejects(concurrent.verify('new@example.com', challenge), { code: 'already-exists' });
  assert.equal(concurrent.user.email, 'old@example.com');
  assert.equal(concurrent.tokens.length, 0);
});

test('paused account and stale identity are checked again after issuing a valid code', async () => {
  const flow = fixture();
  const challenge = await flow.request('new@example.com');
  flow.profile.paused = true;
  await assert.rejects(flow.verify('new@example.com', challenge), { code: 'permission-denied' });
  assert.equal(flow.user.email, 'old@example.com');
  flow.profile.paused = false;
  const binding = await createAccountEmailBinding(flow.bindingOptions, 'new@example.com');
  flow.user.email = 'changed@example.com';
  await assert.rejects(binding.link('new@example.com'), { code: 'aborted' });
});

test('profile storage failure recovers with a fresh normal code without creating a new UID', async () => {
  const flow = fixture();
  const challenge = await flow.request('new@example.com');
  flow.failProfile(true);
  await assert.rejects(flow.verify('new@example.com', challenge));
  assert.equal(flow.user.email, 'new@example.com');
  assert.equal(flow.tokens.length, 0);
  flow.failProfile(false); flow.advance(60000);
  const retry = await flow.request('new@example.com');
  assert.equal((await flow.verify('new@example.com', retry)).uid, 'customer');
  assert.equal(flow.profile.email, 'new@example.com');
});
