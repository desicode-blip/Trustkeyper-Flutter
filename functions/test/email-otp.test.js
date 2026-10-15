import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEmailOtpService, normalizeEmail } from '../email-otp.js';

function fixture(options = {}) {
  const documents = new Map();
  const messages = [];
  const issued = [];
  let timestamp = 100000;
  let sequence = 0;
  let deliveryFails = false;
  let queue = Promise.resolve();
  const settings = {
    secret: 'test-only-secret-with-at-least-32-characters',
    now: () => timestamp, generateCode: () => '123456',
    generateId: () => `challenge-${++sequence}`,
    store: {
      transaction: handler => {
        const pending = queue.then(async () => {
          const snapshot = structuredClone(documents);
          const result = await handler({
            get: async path => snapshot.get(path),
            set: (path, data) => snapshot.set(path, data),
          });
          documents.clear();
          for (const [path, data] of snapshot) documents.set(path, data);
          return result;
        });
        queue = pending.catch(() => {});
        return pending;
      },
    },
    sendMail: async message => {
      if (deliveryFails) throw new Error('Provider unavailable');
      messages.push(message);
    },
    issueToken: async email => {
      issued.push(email);
      return { customToken: 'test-custom-token' };
    },
  };
  const service = createEmailOtpService({ ...settings, ...options });
  return { service, documents, messages, issued,
    scoped: scope => createEmailOtpService({ ...settings, ...scope }),
    advance: milliseconds => { timestamp += milliseconds; },
    failDelivery: () => { deliveryFails = true; },
    request: email => service.request({ email: email ?? 'ajay@example.com', ip: 'test-ip' }),
    verify: challenge => service.verify({ email: 'ajay@example.com', code: '123456', ...challenge }),
  };
}

test('request delivers six digits and verification returns a token once', async () => {
  const flow = fixture();
  const challenge = await flow.request(' AJAY@example.com ');
  assert.equal(flow.messages[0].email, 'ajay@example.com');
  assert.equal(flow.messages[0].code, '123456');
  assert.equal(challenge.code, undefined);
  assert.equal(JSON.stringify([...flow.documents]).includes('123456'), false);
  assert.deepEqual(await flow.verify(challenge), { customToken: 'test-custom-token' });
  await assert.rejects(flow.verify(challenge), { code: 'failed-precondition' });
  assert.deepEqual(flow.issued, ['ajay@example.com']);
});

test('failed delivery never returns a sent challenge or signs anyone in', async () => {
  const flow = fixture();
  flow.failDelivery();
  await assert.rejects(flow.request(), { code: 'unavailable' });
  await assert.rejects(flow.verify({ challengeId: 'challenge-1' }), { code: 'failed-precondition' });
  assert.equal(flow.issued.length, 0);
});

test('wrong codes persist attempts and lock after five guesses', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  for (let attempt = 0; attempt < 4; attempt++) {
    await assert.rejects(flow.verify({ ...challenge, code: '000000' }), { code: 'invalid-argument' });
  }
  await assert.rejects(flow.verify({ ...challenge, code: '000000' }), { code: 'resource-exhausted' });
  await assert.rejects(flow.verify(challenge), { code: 'resource-exhausted' });
  assert.equal(flow.issued.length, 0);
});

test('codes expire after five minutes', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  assert.equal(challenge.expiresInSeconds, 300);
  flow.advance(300000);
  await assert.rejects(flow.verify(challenge), { code: 'failed-precondition' });
});

test('five incorrect codes block resend for fifteen minutes', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  for (let attempt = 0; attempt < 5; attempt++) {
    await assert.rejects(flow.verify({ ...challenge, code: '000000' }));
  }
  flow.advance(60000);
  await assert.rejects(flow.request(), { code: 'resource-exhausted' });
  flow.advance(840000);
  await flow.request();
  assert.equal(flow.messages.length, 2);
});

test('resend cooldown and replacement prevent old codes from signing in', async () => {
  const flow = fixture();
  const first = await flow.request();
  await assert.rejects(flow.request(), { code: 'resource-exhausted' });
  flow.advance(60000);
  const second = await flow.request();
  await assert.rejects(flow.verify(first), { code: 'failed-precondition' });
  assert.deepEqual(await flow.verify(second), { customToken: 'test-custom-token' });
});

test('simultaneous verification consumes the challenge exactly once', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  const outcomes = await Promise.allSettled([flow.verify(challenge), flow.verify(challenge)]);
  assert.equal(outcomes.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(flow.issued.length, 1);
});

test('challenge is bound to its email address', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  await assert.rejects(flow.verify({ ...challenge, email: 'other@example.com' }), { code: 'failed-precondition' });
  assert.equal(flow.issued.length, 0);
});

test('email hourly quota limits repeated delivery', async () => {
  const flow = fixture();
  for (let request = 0; request < 5; request++) {
    await flow.request();
    flow.advance(60000);
  }
  await assert.rejects(flow.request(), { code: 'resource-exhausted' });
  assert.equal(flow.messages.length, 5);
});

test('IP quota limits delivery to many different addresses', async () => {
  const flow = fixture();
  for (let request = 0; request < 20; request++) await flow.request(`person${request}@example.com`);
  await assert.rejects(flow.request('extra@example.com'), { code: 'resource-exhausted' });
});

test('invalid addresses are rejected before any delivery', async () => {
  assert.equal(normalizeEmail(' AJAY@example.com '), 'ajay@example.com');
  const flow = fixture();
  await assert.rejects(flow.request('invalid\n@example.com'), { code: 'invalid-argument' });
  assert.equal(flow.messages.length, 0);
});

test('profile challenges cannot sign in or verify another phone account', async () => {
  const flow = fixture({ purpose: 'profile-email', subjectUid: 'phone-user' });
  const challenge = await flow.request();
  const input = { email: 'ajay@example.com', code: '123456', ...challenge };
  await assert.rejects(flow.scoped({ purpose: 'sign-in' }).verify(input), { code: 'failed-precondition' });
  await assert.rejects(flow.scoped({ purpose: 'profile-email', subjectUid: 'other-user' }).verify(input), { code: 'failed-precondition' });
  assert.equal(flow.issued.length, 0);
  assert.deepEqual(await flow.verify(challenge), { customToken: 'test-custom-token' });
});

test('profile scope shares the email cooldown with sign-in', async () => {
  const flow = fixture();
  await flow.request();
  await assert.rejects(flow.scoped({ purpose: 'profile-email', subjectUid: 'phone-user' })
    .request({ email: 'ajay@example.com', ip: 'other-ip' }), { code: 'resource-exhausted' });
  assert.equal(flow.messages.length, 1);
});

test('legacy sign-in challenges remain valid but cannot bind a phone account', async () => {
  const flow = fixture();
  const challenge = await flow.request();
  for (const document of flow.documents.values()) {
    if (document.challengeId) { delete document.purpose; delete document.subjectUid; }
  }
  await assert.rejects(flow.scoped({ purpose: 'profile-email', subjectUid: 'phone-user' })
    .verify({ email: 'ajay@example.com', code: '123456', ...challenge }), { code: 'failed-precondition' });
  await flow.verify(challenge);
  assert.equal(flow.issued.length, 1);
});
