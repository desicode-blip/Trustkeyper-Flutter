import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAccountClosureService } from '../account-closure.js';

function fixture() {
  let clock = 1000000;
  const records = new Map([['users/customer', { roles: ['broker'], paused: false, approvalStatus: 'approved' }],
    ['users/admin', { roles: ['admin'] }]]);
  const related = { agreements: [], payouts: [], rentPaymentIntents: [], moveOutRefundRequests: [] };
  const calls = []; let disableFailure = false;
  const store = {
    transaction: async handler => handler({ get: async path => structuredClone(records.get(path)),
      set: (path, value) => records.set(path, structuredClone(value)),
      update: (path, value) => records.set(path, { ...records.get(path), ...structuredClone(value) }),
      related: async name => structuredClone(related[name]),
    }),
    pending: async () => [...records].filter(([path, value]) => path.startsWith('accountClosures/') &&
      ['closing', 'closed', 'restoring'].includes(value.status)).map(([, value]) => value),
  };
  const identity = { disable: async uid => { calls.push(['disable', uid]); if (disableFailure) throw new Error('TEST provider outage'); },
    revoke: async uid => calls.push(['revoke', uid]), enable: async uid => calls.push(['enable', uid]) };
  const service = (uid = 'customer', fresh = true) => createAccountClosureService({
    auth: uid ? { uid, token: { auth_time: fresh ? clock / 1000 : 1 } } : null,
    store, identity, now: () => clock,
  });
  return { records, related, calls, service, identity, setTime: value => { clock = value; },
    failDisable: value => { disableFailure = value; } };
}
const consent = { operationId: 'test-operation', confirmed: true, reason: 'stopped', note: '' };
test('closure needs actual final consent, fresh own login and no active signed obligation', async () => {
  const data = fixture(); const account = data.service();
  await assert.rejects(data.service(null).read(), { code: 'unauthenticated' });
  await assert.rejects(data.service('admin').close(consent), { code: 'permission-denied' });
  await assert.rejects(account.close({ ...consent, confirmed: false }), { code: 'invalid-argument' });
  await assert.rejects(data.service('customer', false).close(consent), { code: 'unauthenticated' });
  data.related.agreements.push({ status: 'active', agreementCopy: { mode: 'externally_signed' } });
  assert.equal((await account.read()).canClose, false);
  await assert.rejects(account.close(consent));
  assert.equal(data.calls.length, 0);
});
test('real unsettled recipient payouts and unknown payment history block; test captures do not fabricate money due', async () => {
  const data = fixture();
  data.related.payouts = [{ mode: 'test', amountPaise: 6300000, status: 'processing', recipientUid: 'customer' }];
  assert.equal((await data.service().read()).duePaise, 0);
  data.related.payouts.push({ mode: 'live', recipientUid: 'customer', status: 'failed', amountPaise: 1100000 });
  assert.equal((await data.service().read()).duePaise, 1100000);
  assert.equal((await data.service().read()).canClose, false);
  data.related.payouts = [{ status: 'pending', amountPaise: 1000 }];
  assert.equal((await data.service().read()).canClose, false);
  data.related.payouts = [];
  data.related.rentPaymentIntents = [{ mode: 'live', status: 'creation_unknown' }];
  assert.equal((await data.service().read()).canClose, false);
});
test('confirmed closure disables Auth, revokes sessions, pauses access and retains shared legal records', async () => {
  const data = fixture();
  data.records.set('agreements/history', { status: 'completed', privateLegalAudit: 'TEST' });
  const result = await data.service().close(consent);
  assert.equal(result.closed, true);
  assert.equal(result.recordsRetained, true);
  assert.equal(data.records.get('users/customer').paused, true);
  assert.equal(data.records.get('users/customer').accountClosure.status, 'closed');
  assert.deepEqual(data.calls, [['disable', 'customer'], ['revoke', 'customer']]);
  assert.ok(data.records.has('agreements/history'));
  assert.equal((await data.service().close(consent)).closed, true);
  assert.equal(data.calls.length, 2);
});
test('uncertain Auth disable remains paused, does not claim closed, and can resume after reopening', async () => {
  const data = fixture(); data.failDisable(true);
  await assert.rejects(data.service().close(consent), { code: 'unavailable' });
  assert.equal(data.records.get('users/customer').accountClosure.status, 'closing');
  assert.equal(data.records.get('users/customer').paused, true);
  data.failDisable(false);
  assert.equal((await data.service().close({ ...consent, operationId: 'new-reopen-operation' })).closed, true);
});
test('only an active admin restores within seven days, retaining original roles and approvals', async () => {
  const data = fixture();
  await data.service().close(consent);
  await assert.rejects(data.service().list(), { code: 'permission-denied' });
  await assert.rejects(data.service().restore({ uid: 'customer' }), { code: 'permission-denied' });
  assert.equal((await data.service('admin').list()).requests.length, 1);
  assert.equal((await data.service('admin').restore({ uid: 'customer' })).restored, true);
  assert.equal(data.records.get('users/customer').paused, false);
  assert.deepEqual(data.records.get('users/customer').roles, ['broker']);
  assert.equal(data.records.get('users/customer').approvalStatus, 'approved');
  assert.equal((await data.service('admin').list()).requests.length, 0);
  await data.service().close({ ...consent, operationId: 'second' });
  data.setTime(1000000 + 8 * 86400000);
  await assert.rejects(data.service('admin').restore({ uid: 'customer' }));
});

test('a pending real or unknown refund blocks closure; only an actual same-payer test payment is exempt', async () => {
  const data = fixture();
  data.related.moveOutRefundRequests = [{ status: 'requested', paymentId: 'pay_fixture', mode: 'test' }];
  assert.equal((await data.service().read()).canClose, false);
  data.records.set('payments/pay_fixture', { mode: 'test', payerUid: 'someone-else' });
  assert.equal((await data.service().read()).canClose, false);
  data.records.set('payments/pay_fixture', { mode: 'test', payerUid: 'customer' });
  assert.equal((await data.service().read()).canClose, true);
  data.records.set('payments/pay_fixture', { mode: 'live', payerUid: 'customer' });
  assert.equal((await data.service().read()).canClose, false);
});

test('concurrent closure retry and restoration cannot race Auth disable against enable', async () => {
  const data = fixture();
  let release, started;
  const begun = new Promise(resolve => { started = resolve; });
  const held = new Promise(resolve => { release = resolve; });
  data.identity.disable = async uid => { data.calls.push(['disable', uid]); started(); await held; };
  const first = data.service().close(consent);
  await begun;
  await assert.rejects(data.service().close(consent), { code: 'unavailable' });
  await assert.rejects(data.service('admin').restore({ uid: 'customer' }));
  assert.deepEqual(data.calls, [['disable', 'customer']]);
  release();
  assert.equal((await first).closed, true);
  assert.equal((await data.service('admin').restore({ uid: 'customer' })).restored, true);
  assert.equal((await data.service('admin').restore({ uid: 'customer' })).restored, true);
  assert.equal(data.calls.filter(([action]) => action === 'enable').length, 1);
});

test('admin can finish an uncertain already-consented closure but cannot start one for a customer', async () => {
  const data = fixture();
  await assert.rejects(data.service('admin').finish({ uid: 'customer' }));
  data.failDisable(true);
  await assert.rejects(data.service().close(consent));
  await assert.rejects(data.service().finish({ uid: 'customer' }), { code: 'permission-denied' });
  await assert.rejects(data.service('admin').restore({ uid: 'customer' }));
  data.failDisable(false);
  assert.equal((await data.service('admin').finish({ uid: 'customer' })).closed, true);
  assert.equal(data.records.get('users/customer').accountClosure.status, 'closed');
});

test('uncertain restoration stays paused, retries the same transition and does not extend the original deadline', async () => {
  const data = fixture();
  await data.service().close(consent);
  const deadline = data.records.get('accountClosures/customer').restoreUntilMs;
  data.identity.enable = async () => { throw new Error('TEST ambiguous enable'); };
  await assert.rejects(data.service('admin').restore({ uid: 'customer' }), { code: 'unavailable' });
  assert.equal(data.records.get('users/customer').paused, true);
  assert.equal(data.records.get('accountClosures/customer').restoreUntilMs, deadline);
  data.setTime(deadline + 1);
  data.identity.enable = async uid => data.calls.push(['enable', uid]);
  assert.equal((await data.service('admin').restore({ uid: 'customer' })).restored, true);
});

test('an outage does not consume the seven-day restoration window before closure is actually confirmed', async () => {
  const data = fixture();
  data.failDisable(true);
  await assert.rejects(data.service().close(consent));
  const confirmedAtMs = 1000000 + 8 * 86400000;
  data.setTime(confirmedAtMs);
  data.failDisable(false);
  const result = await data.service('admin').finish({ uid: 'customer' });
  assert.equal(result.restoreUntilMs, confirmedAtMs + 7 * 86400000);
  assert.equal(data.records.get('accountClosures/customer').closedAtMs, confirmedAtMs);
  assert.equal((await data.service('admin').restore({ uid: 'customer' })).restored, true);
});
