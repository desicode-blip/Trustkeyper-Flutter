import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifiedPhone } from '../verified-phone.js';

const phone = '+911111111111';
const proof = { phone_number: phone, firebase: { sign_in_provider: 'custom' },
  email: 'owner@example.com', email_verified: true, trustkeyper_email_otp: true, trustkeyper_verified_phone: phone };

test('verified phone accepts the phone provider and this server email session only', () => {
  assert.equal(verifiedPhone({ uid: 'owner', token: { phone_number: phone, firebase: { sign_in_provider: 'phone' } } }), phone);
  assert.equal(verifiedPhone({ uid: 'owner', token: proof }), phone);
});

test('email proof rejects missing, unverified, mismatched and unrelated custom credentials', () => {
  for (const change of [
    { trustkeyper_email_otp: false }, { email_verified: false }, { email: '' },
    { trustkeyper_verified_phone: '+912222222222' }, { phone_number: undefined },
    { firebase: { sign_in_provider: 'password' } }, { phone_number: '1111111111' },
  ]) assert.equal(verifiedPhone({ uid: 'owner', token: { ...proof, ...change } }), null);
  assert.equal(verifiedPhone({ token: proof }), null);
  assert.equal(verifiedPhone(null), null);
});
