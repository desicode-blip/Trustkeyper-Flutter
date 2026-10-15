import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEmailTokenIssuer } from '../email-identity.js';

function identityFixture({ user, profile } = {}) {
  const created = [], updated = [], tokens = [];
  const auth = {
    getUserByEmail: async () => {
      if (!user) throw { code: 'auth/user-not-found' };
      return user;
    },
    createUser: async data => {
      created.push(data);
      return { uid: 'new-user', ...data };
    },
    updateUser: async (uid, data) => { updated.push({ uid, ...data }); },
    createCustomToken: async (uid, claims) => { tokens.push({ uid, claims }); return `token-for-${uid}`; },
  };
  return { created, updated, tokens,
    issue: createEmailTokenIssuer({ auth, getProfile: async () => profile }),
  };
}

test('existing email identity keeps its UID and verifies its email', async () => {
  const flow = identityFixture({ user: { uid: 'existing-user', emailVerified: false } });
  assert.deepEqual(await flow.issue('ajay@example.com'), { customToken: 'token-for-existing-user' });
  assert.deepEqual(flow.updated, [{ uid: 'existing-user', emailVerified: true }]);
  assert.equal(flow.created.length, 0);
});

test('first-time verified email creates an identity without seeded profile data', async () => {
  const flow = identityFixture();
  assert.deepEqual(await flow.issue('ajay@example.com'), { customToken: 'token-for-new-user' });
  assert.deepEqual(flow.created, [{ email: 'ajay@example.com', emailVerified: true }]);
  assert.deepEqual(flow.tokens, [{ uid: 'new-user', claims: { trustkeyper_email_otp: true } }]);
});

test('email login carries only the phone already verified on the same Auth identity', async () => {
  const flow = identityFixture({ user: { uid: 'linked', emailVerified: true, phoneNumber: '+911111111111' },
    profile: { roles: ['owner'], phone: '+919999999999' } });
  await flow.issue('owner@example.com');
  assert.deepEqual(flow.tokens, [{ uid: 'linked', claims: {
    trustkeyper_email_otp: true, trustkeyper_verified_phone: '+911111111111',
  } }]);
});

test('unverified profile contact never becomes a verified phone claim', async () => {
  const flow = identityFixture({ user: { uid: 'email-only', emailVerified: true },
    profile: { roles: ['tenant'], phone: '+912222222222' } });
  await flow.issue('tenant@example.com');
  assert.deepEqual(flow.tokens, [{ uid: 'email-only', claims: { trustkeyper_email_otp: true } }]);
});

test('admin email OTP cannot bypass separate admin authentication', async () => {
  const flow = identityFixture({ user: { uid: 'admin-user', emailVerified: true }, profile: { roles: ['admin'] } });
  await assert.rejects(flow.issue('admin@example.com'), { code: 'permission-denied' });
  assert.equal(flow.tokens.length, 0);
});

test('disabled and paused users receive no sign-in token', async () => {
  for (const settings of [
    { user: { uid: 'disabled', disabled: true } },
    { user: { uid: 'paused' }, profile: { paused: true } },
  ]) {
    const flow = identityFixture(settings);
    await assert.rejects(flow.issue('ajay@example.com'), { code: 'permission-denied' });
    assert.equal(flow.tokens.length, 0);
  }
});
