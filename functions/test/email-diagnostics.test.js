import assert from 'node:assert/strict';
import test from 'node:test';
import { emailFailureMetadata } from '../email-diagnostics.js';

test('email diagnostics identify known permission failures without request data', () => {
  const error = Object.assign(new Error('private@example.com code 654321'), {
    code: 'auth/insufficient-permission', name: 'FirebaseAuthError',
    request: { code: '654321', token: 'private-token' },
  });
  assert.deepEqual(emailFailureMetadata('verifyEmailOtp', error), {
    operation: 'verifyEmailOtp', code: 'auth/insufficient-permission', type: 'FirebaseAuthError',
  });
});

test('email diagnostics never echo arbitrary codes, names, operations or messages', () => {
  const metadata = emailFailureMetadata('private@example.com', {
    name: 'private-token', code: '654321', message: 'private-password', stack: 'private-stack',
  });
  assert.deepEqual(metadata, { operation: 'unknown', code: 'unknown', type: 'unknown' });
});

test('email diagnostics tolerate non-error throws and preserve approved operation names', () => {
  assert.deepEqual(emailFailureMetadata('verifyProfileEmailOtp', null), {
    operation: 'verifyProfileEmailOtp', code: 'unknown', type: 'unknown',
  });
});
