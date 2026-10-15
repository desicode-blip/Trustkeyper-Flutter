import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createResendEmailSender } from '../resend-email.js';

const input = { email: 'owner@example.com', code: '012345', challengeId: 'single-use-challenge' };
const settings = { apiKey: 'provider-test-fixture', from: 'TrustKeyper <noreply@trustkeyper.com>' };

test('email provider sends the complete code with a bounded request and idempotency', async () => {
  const send = createResendEmailSender({ ...settings, fetchRequest: async (url, request) => {
    assert.equal(url, 'https://api.resend.com/emails');
    assert.equal(request.method, 'POST');
    assert.equal(request.headers['Idempotency-Key'], input.challengeId);
    assert.equal(request.headers.Authorization, `Bearer ${settings.apiKey}`);
    const body = JSON.parse(request.body);
    assert.deepEqual(body.to, [input.email]);
    assert.equal(body.from, settings.from);
    assert.ok(body.text.includes(input.code));
    assert.ok(body.html.includes(input.code));
    assert.ok(request.signal instanceof AbortSignal);
    return { ok: true, json: async () => ({ id: 'provider-message-id' }) };
  } });
  assert.deepEqual(await send(input), { id: 'provider-message-id' });
});

test('provider rejection does not expose credentials or claim successful sending', async () => {
  const send = createResendEmailSender({ ...settings, fetchRequest: async () => ({ ok: false }) });
  await assert.rejects(send(input), { message: 'Email provider rejected delivery.' });
});

test('malformed successful response is not delivery acceptance', async () => {
  for (const result of [{}, { id: '' }, { id: 123 }]) {
    const send = createResendEmailSender({ ...settings, fetchRequest: async () => ({ ok: true, json: async () => result }) });
    await assert.rejects(send(input), { message: 'Email provider did not confirm acceptance.' });
  }
});

test('invalid OTP and missing configuration never reach the provider', async () => {
  let requests = 0;
  const fetchRequest = async () => { requests++; throw new Error('Should not send'); };
  for (const [configuration, request] of [
    [{ ...settings, apiKey: '' }, input], [settings, { ...input, code: '12345' }],
    [settings, { ...input, challengeId: '' }],
  ]) await assert.rejects(createResendEmailSender({ ...configuration, fetchRequest })(request));
  assert.equal(requests, 0);
});
