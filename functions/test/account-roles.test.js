import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAccountRoleService } from '../account-roles.js';
function fixture(profile = { roles: ['owner'], displayName: 'TEST owner' }, uid = 'user') {
  const records = new Map([['users/user', structuredClone(profile)]]);
  const service = createAccountRoleService({ auth: uid ? { uid } : {}, now: () => 100,
    store: { transaction: async handler => handler({ get: async path => structuredClone(records.get(path)),
      set: (path, data) => records.set(path, data), update: (path, data) => records.set(path, { ...records.get(path), ...data }) }) } });
  return { service, records };
}
test('roles come from the server and selecting another device never changes global session state', async () => {
  const flow = fixture({ roles: ['broker', 'owner'], approvalStatus: 'approved' });
  assert.deepEqual((await flow.service.read()).roles, ['broker', 'owner']);
  assert.equal((await flow.service.select({ role: 'owner' })).route, '/owner');
  assert.equal((await flow.service.select({ role: 'broker' })).route, '/broker');
  assert.equal(flow.records.size, 1); assert.equal(flow.records.get('users/user').activeRole, undefined);
});
test('adding a customer role is idempotent and never grants a home or broker approval', async () => {
  const flow = fixture();
  assert.equal((await flow.service.add({ role: 'broker', approvalStatus: 'approved' })).route, '/broker/approval');
  await flow.service.add({ role: 'broker' });
  assert.deepEqual(flow.records.get('users/user').roles, ['owner', 'broker']);
  assert.equal(flow.records.get('users/user').approvalStatus, 'pending');
  assert.equal(flow.records.get('users/user').participantUids, undefined);
  assert.equal(flow.records.get('users/user/roleEvents/broker').grantsHomeAccess, false);
});
test('unknown, admin, unregistered, anonymous, paused and missing roles cannot be selected', async () => {
  const flow = fixture();
  await assert.rejects(flow.service.select({ role: 'tenant' }), { code: 'permission-denied' });
  await assert.rejects(flow.service.add({ role: 'admin' }), { code: 'invalid-argument' });
  for (const options of [{ roles: ['admin'] }, { roles: ['owner'], paused: true }, undefined]) {
    const current = fixture(options); if (options === undefined) current.records.delete('users/user');
    await assert.rejects(current.service.read(), { code: 'permission-denied' });
  }
  await assert.rejects(fixture({}, null).service.read(), { code: 'unauthenticated' });
});
