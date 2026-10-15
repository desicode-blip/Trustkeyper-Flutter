import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deliverBrokerUpdate, documentSubmittedUpdate } from '../broker-updates.js';

const updateId = 'a'.repeat(64);
const path = `users/broker/updates/${updateId}`;
function fixture() {
  const data = new Map([
    ['users/broker', { roles: ['broker'], approvalStatus: 'approved' }],
    [path, { brokerUid: 'broker', kind: 'documents_received', pushState: 'pending' }],
  ]);
  const devices = [{ id: 'first', token: 'TEST_ONLY_device_token_first', enabled: true, updatedAtMs: 1000 },
    { id: 'second', token: 'TEST_ONLY_device_token_second', enabled: true, updatedAtMs: 1000 }];
  const sent = [];
  const disabled = [];
  let responses = devices.map(() => ({ success: true }));
  const store = {
    transaction: async handler => handler({
      get: async reference => data.get(reference),
      update: (reference, values) => data.set(reference, { ...data.get(reference), ...values }),
    }),
    devices: async () => devices,
    update: async (reference, values) => data.set(reference, { ...data.get(reference), ...values }),
    disableDevice: async (_, id) => { disabled.push(id); devices.find(device => device.id === id).enabled = false; },
  };
  const messaging = { sendEachForMulticast: async message => { sent.push(message); return { responses }; } };
  return { data, devices, sent, disabled, responses: value => responses = value,
    send: () => deliverBrokerUpdate({ store, messaging, now: () => 2000 }, 'broker', updateId) };
}
test('upload notices are deterministic, owner/tenant scoped and contain no document or bank secrets', () => {
  const record = { type: 'all', brokerUid: 'broker', partyName: 'TEST Tenant', role: 'tenant',
    partyId: 'tenant-2', draftId: 'draft', revision: 3, version: 2, address: 'TEST Property',
    token: 'PRIVATE', phone: 'PRIVATE', submission: { uploadId: 'upload', atMs: 1000, bankDetails: { accountNumber: 'PRIVATE' } } };
  const update = documentSubmittedUpdate('request', record);
  assert.deepEqual(documentSubmittedUpdate('request', record), update);
  assert.equal(update.data.title, 'TEST Tenant added documents');
  assert.equal(update.data.partyId, 'tenant-2');
  assert.equal(JSON.stringify(update).includes('PRIVATE'), false);
  assert.notEqual(documentSubmittedUpdate('request', { ...record, submission: { uploadId: 'replacement' } }).id, update.id);
});
test('push has generic lock-screen text and retried event never repeats accepted delivery', async () => {
  const flow = fixture();
  await flow.send(); await flow.send();
  assert.equal(flow.sent.length, 1);
  assert.deepEqual(flow.sent[0].data, { kind: 'broker_update', brokerUid: 'broker', updateId });
  assert.equal(flow.sent[0].android.notification.tag, updateId);
  assert.equal(flow.sent[0].notification.body.includes('TEST Tenant'), false);
});
test('transient failures retry only unaccepted devices', async () => {
  const flow = fixture();
  flow.responses([{ success: true }, { success: false, error: { code: 'messaging/internal-error' } }]);
  await assert.rejects(flow.send());
  assert.equal(flow.data.get(path).pushState, 'retry');
  flow.responses([{ success: true }]);
  await flow.send();
  assert.deepEqual(flow.sent[1].tokens, ['TEST_ONLY_device_token_second']);
  assert.equal(flow.data.get(path).pushState, 'accepted');
});
test('invalid tokens are disabled; paused brokers and stale devices receive no push but keep inbox', async () => {
  const flow = fixture();
  flow.responses([{ success: false, error: { code: 'messaging/registration-token-not-registered' } }, { success: true }]);
  await flow.send();
  assert.deepEqual(flow.disabled, ['first']);
  const paused = fixture();
  paused.data.set('users/broker', { roles: ['broker'], approvalStatus: 'approved', paused: true });
  await paused.send();
  assert.equal(paused.sent.length, 0);
  assert.equal(paused.data.get(path).pushState, 'blocked');
  const empty = fixture(); empty.devices.splice(0);
  await empty.send();
  assert.equal(empty.data.get(path).pushState, 'no_devices');
  assert.ok(empty.data.get(path));
});
test('active lease and incomplete gateway responses fail safely rather than reporting success', async () => {
  const flow = fixture();
  flow.data.set(path, { ...flow.data.get(path), pushState: 'sending', pushLeaseUntilMs: 2001 });
  await assert.rejects(flow.send()); assert.equal(flow.sent.length, 0);
  flow.data.set(path, { ...flow.data.get(path), pushLeaseUntilMs: 0 });
  flow.responses([]);
  await assert.rejects(flow.send()); assert.equal(flow.data.get(path).pushState, 'retry');
});
