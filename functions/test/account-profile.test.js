import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAccountProfileService } from '../account-profile.js';

function fixture() {
  const records = new Map([['users/customer', { roles: ['broker'], approvalStatus: 'pending',
    displayName: 'TEST name', phone: 'forged-profile-phone', email: '', city: '', reraNumber: '' }]]);
  const person = { uid: 'customer', phoneNumber: '+919999999999', email: 'test@example.invalid', emailVerified: true, disabled: false };
  const store = { transaction: async handler => handler({ get: async path => records.get(path),
    update: (path, value) => records.set(path, { ...records.get(path), ...value }) }) };
  const identity = { read: async () => person, updateName: async (_, displayName) => { person.displayName = displayName; } };
  return { records, person, service: auth => createAccountProfileService({ auth, store, identity, now: () => 100 }) };
}
test('profile uses actual Auth phone/email rather than forged profile proof; no bank verification is fabricated', async () => {
  const { service } = fixture();
  const result = await service({ uid: 'customer' }).read();
  assert.equal(result.phone, '+919999999999');
  assert.equal(result.emailVerified, true);
  assert.equal(result.bankVerified, false);
});
test('profile fields save and reopen without changing roles, approval or bank status', async () => {
  const { service, records } = fixture();
  const account = service({ uid: 'customer' });
  const result = await account.save({ displayName: ' TEST updated ', city: ' Hyderabad ', reraNumber: 'TEST-RERA',
    email: 'test@example.invalid', roles: ['admin'], approvalStatus: 'approved', bankVerified: true });
  assert.equal(result.displayName, 'TEST updated');
  assert.equal((await account.read()).city, 'Hyderabad');
  assert.deepEqual(records.get('users/customer').roles, ['broker']);
  assert.equal(records.get('users/customer').approvalStatus, 'pending');
  assert.equal(records.get('users/customer').bankVerified, undefined);
});
test('unverified new email, missing name, long fields, disabled identity and anonymous/paused profile are rejected', async () => {
  const { service, records, person } = fixture();
  const account = service({ uid: 'customer' });
  await assert.rejects(account.save({ displayName: 'TEST', email: 'other@example.invalid' }));
  await assert.rejects(account.save({ displayName: '', email: '' }), { code: 'invalid-argument' });
  await assert.rejects(account.save({ displayName: 'TEST', city: 'x'.repeat(101) }), { code: 'invalid-argument' });
  await assert.rejects(service(null).read(), { code: 'unauthenticated' });
  await assert.rejects(service(null).save({ displayName: 'TEST' }), { code: 'unauthenticated' });
  person.disabled = true;
  await assert.rejects(account.read(), { code: 'permission-denied' });
  person.disabled = false; records.get('users/customer').paused = true;
  await assert.rejects(account.save({ displayName: 'TEST' }), { code: 'permission-denied' });
});
