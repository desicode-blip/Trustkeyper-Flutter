import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createProfileEmailBinding } from '../profile-email.js';
import { createEmailOtpService } from '../email-otp.js';

function fixture(options = {}) {
  const user = { uid: 'phone-user', phoneNumber: '+910000000000', ...options.user };
  const updates = [];
  const profiles = [];
  const auth = {
    getUser: async uid => { assert.equal(uid, user.uid); return user; },
    getUserByEmail: async () => {
      if (options.existing) return options.existing;
      throw Object.assign(new Error('Not found'), { code: 'auth/user-not-found' });
    },
    updateUser: async (uid, data) => {
      if (options.updateError) throw options.updateError;
      updates.push({ uid, ...data });
    },
  };
  const binding = createProfileEmailBinding({
    auth, uid: options.uid === undefined ? user.uid : options.uid,
    authTime: options.authTime === undefined ? 100 : options.authTime,
    now: () => 100000,
    getProfile: async () => options.profile,
    updateProfile: async (uid, email) => profiles.push({ uid, email }),
  });
  return { binding, updates, profiles };
}

test('binds verified email to phone UID without creating another user', async () => {
  const flow = fixture({ profile: { roles: ['broker'] } });
  assert.deepEqual(await flow.binding.link(' AJAY@example.com '), {
    uid: 'phone-user', email: 'ajay@example.com', verified: true,
  });
  assert.deepEqual(flow.updates, [{ uid: 'phone-user', email: 'ajay@example.com', emailVerified: true }]);
  assert.deepEqual(flow.profiles, [{ uid: 'phone-user', email: 'ajay@example.com' }]);
});

test('missing or stale authentication cannot bind an email', async () => {
  for (const options of [{ uid: null }, { authTime: null }, { authTime: -900 }, { authTime: 200 }]) {
    const flow = fixture(options);
    await assert.rejects(flow.binding.link('ajay@example.com'), { code: 'unauthenticated' });
    assert.equal(flow.updates.length, 0);
  }
});

test('disabled, paused, admin and non-phone accounts are rejected', async () => {
  for (const options of [
    { user: { disabled: true } }, { profile: { paused: true } },
    { profile: { roles: ['admin'] } }, { user: { customClaims: { admin: true } } },
    { user: { customClaims: { roles: ['admin'] } } }, { user: { phoneNumber: null } },
  ]) {
    const flow = fixture(options);
    await assert.rejects(flow.binding.link('ajay@example.com'), { code: 'permission-denied' });
    assert.equal(flow.updates.length, 0);
  }
});

test('existing email identities are never automatically merged', async () => {
  const flow = fixture({ existing: { uid: 'someone-else' } });
  await assert.rejects(flow.binding.link('ajay@example.com'), { code: 'already-exists' });
  assert.equal(flow.updates.length, 0);
});

test('existing account email cannot be changed through onboarding', async () => {
  const flow = fixture({ user: { email: 'original@example.com' } });
  await assert.rejects(flow.binding.link('ajay@example.com'), { code: 'failed-precondition' });
  assert.equal(flow.updates.length, 0);
});

test('same UID is idempotent; new profiles are not fabricated', async () => {
  const flow = fixture({ existing: { uid: 'phone-user' }, user: { email: 'ajay@example.com' } });
  await flow.binding.link('ajay@example.com');
  assert.equal(flow.updates.length, 1);
  assert.equal(flow.profiles.length, 0);
});

test('concurrent Auth email collision is a safe recoverable error', async () => {
  const flow = fixture({ updateError: Object.assign(new Error('Collision'), { code: 'auth/email-already-exists' }) });
  await assert.rejects(flow.binding.link('ajay@example.com'), { code: 'already-exists' });
  assert.equal(flow.profiles.length, 0);
});

test('binding occurs only after a valid code and cannot be replayed', async () => {
  const flow = fixture();
  const documents = new Map();
  const service = createEmailOtpService({
    purpose: 'profile-email', subjectUid: flow.binding.uid,
    secret: 'test-only-secret-with-at-least-32-characters', now: () => 100000,
    generateCode: () => '123456', generateId: () => 'profile-challenge',
    store: { transaction: handler => handler({
      get: async path => documents.get(path), set: (path, value) => documents.set(path, value),
    }) },
    sendMail: async () => {}, issueToken: flow.binding.link,
  });
  const challenge = await service.request({ email: 'ajay@example.com', ip: 'test' });
  assert.equal(flow.updates.length, 0);
  await assert.rejects(service.verify({ ...challenge, email: 'ajay@example.com', code: '000000' }), { code: 'invalid-argument' });
  assert.equal(flow.updates.length, 0);
  assert.deepEqual(await service.verify({ ...challenge, email: 'ajay@example.com', code: '123456' }), {
    uid: 'phone-user', email: 'ajay@example.com', verified: true,
  });
  await assert.rejects(service.verify({ ...challenge, email: 'ajay@example.com', code: '123456' }), { code: 'failed-precondition' });
  assert.equal(flow.updates.length, 1);
});
