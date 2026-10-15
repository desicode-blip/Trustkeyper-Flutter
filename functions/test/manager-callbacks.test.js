import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createManagerCallbackService, callbackWindow } from '../manager-callbacks.js';

function fixture() {
  let clock = Date.parse('2026-10-10T04:30:00Z');
  let sequence = 0;
  const records = new Map([
    ['users/owner', { roles: ['owner'], phone: '+911111111111', displayName: 'TEST Owner' }],
    ['users/other', { roles: ['owner'], phone: '+913333333333' }],
    ['users/manager', { roles: ['admin'], displayName: 'TEST Manager' }],
    ['users/admin', { roles: ['admin'], displayName: 'TEST Team' }],
    ['users/tenant', { roles: ['tenant'], phone: '+912222222222' }],
  ]);
  const store = { transaction: async handler => {
    const copy = structuredClone(records);
    let written = false;
    const result = await handler({
      get: async path => { assert.equal(written, false); return structuredClone(copy.get(path)); },
      list: async prefix => [...copy].filter(([path]) => path.startsWith(`${prefix}/`) && path.split('/').length === 2).map(([, data]) => data),
      set: (path, data) => { written = true; copy.set(path, structuredClone(data)); },
    });
    records.clear(); for (const [path, value] of copy) records.set(path, value);
    return result;
  } };
  function service(uid = 'owner', token = { phone_number: records.get(`users/${uid}`)?.phone, firebase: { sign_in_provider: 'phone' } }) {
    return createManagerCallbackService({ auth: uid ? { uid, token } : null, store,
      phoneForUser: async ownerUid => ownerUid === 'owner' ? '+911111111111' : '+913333333333', now: () => clock });
  }
  function input(action, payload = {}, ownerUid) {
    return { action, payload, ...(ownerUid ? { ownerUid } : {}), version: records.get(`ownerCallbacks/${ownerUid ?? 'owner'}`)?.version ?? 0,
      operationId: (++sequence).toString(16).padStart(32, '0') };
  }
  return { records, service, input, advance: millis => { clock += millis; }, time: () => clock };
}

test('callback slots use India working hours and reject past/out-of-hours requests', () => {
  const evening = Date.parse('2026-10-10T14:20:00Z');
  assert.throws(() => callbackWindow('soon', evening), { code: 'invalid-argument' });
  assert.throws(() => callbackWindow('made_up', evening), { code: 'invalid-argument' });
  assert.equal(new Date(callbackWindow('tomorrow_morning', evening).fromMs).toISOString(), '2026-10-11T03:30:00.000Z');
});

test('linked email session can request callbacks, but profile-only phone cannot', async () => {
  const flow = fixture();
  const token = { firebase: { sign_in_provider: 'custom' }, phone_number: '+911111111111',
    email: 'owner@example.com', email_verified: true, trustkeyper_email_otp: true, trustkeyper_verified_phone: '+911111111111' };
  const result = await flow.service('owner', token).record(flow.input('request', { topic: 'property', window: 'soon' }));
  assert.equal(result.callback.phone, '+911111111111');
  await assert.rejects(flow.service('owner', { ...token, trustkeyper_verified_phone: undefined }).read(), { code: 'permission-denied' });
});
test('owner requests verified-phone callbacks; no invented manager or confirmed booking', async () => {
  const flow = fixture();
  const result = await flow.service().record(flow.input('request', { topic: 'property', window: 'soon', phone: '+919999999999' }));
  assert.equal(result.callback.phone, '+911111111111');
  assert.equal(result.callback.status, 'requested'); assert.equal(result.manager, null);
  assert.equal(result.callback.scheduledAtMs, null); assert.equal(result.deliveryStatus, 'in_app_only');
  assert.equal((await flow.service('other').read()).callback, null);
  assert.equal(flow.records.has('users/owner/property'), false);
});
test('admin assignment, confirmed slot, missed attempt and owner reschedule are audited', async () => {
  const flow = fixture();
  await flow.service().record(flow.input('request', { topic: 'tenant', window: 'soon' }));
  await flow.service('admin').record(flow.input('assign', { managerUid: 'manager', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner'));
  let record = flow.records.get('ownerCallbacks/owner');
  await flow.service('admin').record(flow.input('confirm', { scheduledAtMs: record.requestedFromMs }, 'owner'));
  assert.equal((await flow.service().read()).manager.name, 'TEST Manager');
  await assert.rejects(flow.service('admin').record(flow.input('missed', { note: 'TEST no answer on verified phone' }, 'owner')), { code: 'failed-precondition' });
  flow.advance(10 * 60000);
  await flow.service('admin').record(flow.input('missed', { note: 'TEST no answer on verified phone' }, 'owner'));
  assert.equal((await flow.service().read()).callback.status, 'missed');
  await flow.service().record(flow.input('request', { topic: 'tenant', window: 'tomorrow_morning' }));
  record = flow.records.get('ownerCallbacks/owner');
  assert.equal(record.status, 'requested'); assert.equal(record.attemptedAtMs, null);
  assert.equal([...flow.records.keys()].filter(path => path.includes('/events/')).length, 5);
});
test('changed versions and changed retry payloads never overwrite existing requests', async () => {
  const flow = fixture();
  const request = flow.input('request', { topic: 'plan', window: 'soon' });
  const first = await flow.service().record(request);
  assert.deepEqual(await flow.service().record(request), first);
  await assert.rejects(flow.service().record({ ...request, payload: { topic: 'tenant', window: 'soon' } }), { code: 'already-exists' });
  await assert.rejects(flow.service().record({ ...flow.input('cancel'), version: 0 }), { code: 'aborted' });
  assert.equal(flow.records.get('ownerCallbacks/owner').status, 'requested');
  await flow.service().record(flow.input('cancel'));
  assert.equal((await flow.service().record(request)).callback.status, 'cancelled');
});
test('paused, wrong-provider, other-role and owner team escalation are denied', async () => {
  const flow = fixture();
  await assert.rejects(flow.service(null).read(), { code: 'unauthenticated' });
  await assert.rejects(flow.service('tenant').read(), { code: 'permission-denied' });
  await assert.rejects(flow.service().list(), { code: 'permission-denied' });
  await assert.rejects(flow.service('owner', { phone_number: '+913333333333', firebase: { sign_in_provider: 'phone' } }).read(), { code: 'permission-denied' });
  await assert.rejects(flow.service('owner', { phone_number: '+911111111111', firebase: { sign_in_provider: 'password' } }).read(), { code: 'permission-denied' });
  await assert.rejects(flow.service().record(flow.input('assign', { managerUid: 'admin' }, 'other')), { code: 'permission-denied' });
  flow.records.get('users/owner').paused = true;
  await assert.rejects(flow.service().read(), { code: 'permission-denied' });
});
test('manager must be active team; invalid contact, expired confirmation and future outcomes fail', async () => {
  const flow = fixture();
  await flow.service().record(flow.input('request', { topic: 'plan', window: 'soon' }));
  await assert.rejects(flow.service('admin').record(flow.input('assign', { managerUid: 'tenant', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner')), { code: 'permission-denied' });
  await assert.rejects(flow.service('admin').record(flow.input('assign', { managerUid: 'manager', phone: 'invalid', email: 'fake@example.com' }, 'owner')), { code: 'invalid-argument' });
  await flow.service('admin').record(flow.input('assign', { managerUid: 'manager', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner'));
  await assert.rejects(flow.service('admin').record(flow.input('confirm', { scheduledAtMs: flow.time() + 60 * 60000 }, 'owner')), { code: 'invalid-argument' });
  flow.records.get('users/manager').paused = true;
  assert.equal((await flow.service().read()).manager, null);
  await assert.rejects(flow.service('admin').record(flow.input('confirm', { scheduledAtMs: flow.time() + 10 * 60000 }, 'owner')), { code: 'failed-precondition' });
});
test('rescheduling is rate limited and reassigning requires fresh confirmation', async () => {
  const flow = fixture();
  await flow.service().record(flow.input('request', { topic: 'property', window: 'soon' }));
  await assert.rejects(flow.service().record(flow.input('request', { topic: 'property', window: 'soon' })), { code: 'resource-exhausted' });
  await flow.service('admin').record(flow.input('assign', { managerUid: 'manager', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner'));
  await flow.service('admin').record(flow.input('confirm', { scheduledAtMs: flow.time() + 10 * 60000 }, 'owner'));
  await flow.service('admin').record(flow.input('assign', { managerUid: 'admin', phone: '+918088516875', email: 'team@trustkeyper.com' }, 'owner'));
  assert.equal(flow.records.get('ownerCallbacks/owner').status, 'requested');
  assert.equal(flow.records.get('ownerCallbacks/owner').scheduledAtMs, null);
});
test('admin cannot treat an edited profile phone as a verified callback destination', async () => {
  const flow = fixture();
  flow.records.get('users/owner').phone = '+919999999999';
  await assert.rejects(flow.service('admin').read({ ownerUid: 'owner' }), { code: 'failed-precondition' });
  await assert.rejects(flow.service('admin').record(flow.input('assign', { managerUid: 'manager', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner')), { code: 'failed-precondition' });
});
test('different actors reusing an operation id cannot overwrite each other’s audit events', async () => {
  const flow = fixture();
  const request = flow.input('request', { topic: 'property', window: 'soon' });
  await flow.service().record(request);
  const assignment = flow.input('assign', { managerUid: 'manager', phone: '+918088516875', email: 'help@trustkeyper.com' }, 'owner');
  assignment.operationId = request.operationId;
  await flow.service('admin').record(assignment);
  assert.equal([...flow.records.keys()].filter(path => path.includes('/events/')).length, 2);
});
