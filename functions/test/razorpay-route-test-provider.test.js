import { test } from 'node:test';
import assert from 'node:assert/strict';
import { razorpayRouteTestProvider, routeTransferState } from '../razorpay-route-test-provider.js';

const key = 'rzp_test_FixtureOnly';
const secret = 'fixture-only-secret-not-a-real-credential';
function fixture(reply, status = 200) {
  const calls = [];
  const provider = razorpayRouteTestProvider(key, secret, async (url, options) => {
    calls.push({ url, ...options });
    return { ok: status === 200, status, json: async () => structuredClone(reply) };
  });
  return { provider, calls };
}
test('Route adapter rejects live credentials and invalid IDs without a network write', async () => {
  assert.throws(() => razorpayRouteTestProvider('rzp_live_FixtureOnly', secret));
  const { provider, calls } = fixture({});
  await assert.rejects(provider.linkedAccount('../accounts'));
  await assert.rejects(provider.transfer('trf_one/unsafe'));
  await assert.rejects(provider.createHeldTransfers('pay_one', [
    { accountId: 'acc_one', amountPaise: 1.2, operationId: 'fixture' },
  ]));
  assert.equal(calls.length, 0);
});
test('readiness requires the actual activated Route configuration, not a client assertion', async () => {
  const replies = [{ id: 'acc_one', type: 'route', status: 'created' },
    { id: 'acc_prd_one', account_id: 'acc_one', product_name: 'route', activation_status: 'needs_clarification' }];
  const provider = razorpayRouteTestProvider(key, secret, async () =>
    ({ ok: true, json: async () => replies.shift() }));
  assert.equal((await provider.readiness('acc_one', 'acc_prd_one')).ready, false);
  const mismatch = fixture({ id: 'acc_other', type: 'route' });
  await assert.rejects(mismatch.provider.linkedAccount('acc_one'), { code: 'failed-precondition' });
});
test('activated configuration is unusable for an unknown or suspended linked account', async () => {
  for (const status of ['created', 'suspended', undefined]) {
    const replies = [{ id: 'acc_one', type: 'route', ...(status ? { status } : {}) },
      { id: 'acc_prd_one', account_id: 'acc_one', product_name: 'route', activation_status: 'activated' }];
    const provider = razorpayRouteTestProvider(key, secret, async () =>
      ({ ok: true, json: async () => replies.shift() }));
    assert.equal((await provider.readiness('acc_one', 'acc_prd_one')).ready, status === 'created');
  }
});
test('payment transfers are held and INR with a reserved operation; no auto-release or payout claim', async () => {
  const { provider, calls } = fixture({ entity: 'collection', items: [{ id: 'trf_one', status: 'pending' }] });
  const result = await provider.createHeldTransfers('pay_one', [
    { accountId: 'acc_one', amountPaise: 12345, operationId: 'reserved-operation' },
  ]);
  assert.equal(result[0].status, 'pending');
  assert.equal(calls[0].url, 'https://api.razorpay.com/v1/payments/pay_one/transfers');
  assert.equal(calls[0].method, 'POST');
  assert.deepEqual(JSON.parse(calls[0].body).transfers[0], {
    account: 'acc_one', amount: 12345, currency: 'INR', on_hold: true,
    notes: { tk_route_operation: 'reserved-operation' },
  });
});
test('settlement hold changes use PATCH; uncertain responses do not encourage another transfer', async () => {
  const { provider, calls } = fixture({ id: 'trf_one', on_hold: false });
  await provider.hold('trf_one', false);
  assert.equal(calls[0].method, 'PATCH');
  assert.deepEqual(JSON.parse(calls[0].body), { on_hold: false });
  await assert.rejects(fixture({}, 503).provider.transfer('trf_one'), { code: 'unavailable' });
  await assert.rejects(fixture({}, 403).provider.linkedAccount('acc_one'), { code: 'failed-precondition' });
  await assert.rejects(fixture({}).provider.transfers('pay_one'), { code: 'unavailable' });
});
test('a processed transfer is not money in the bank until the matching settlement is processed', () => {
  const transfer = { id: 'trf_one', entity: 'transfer', status: 'processed', currency: 'INR',
    amount: 10000, amount_reversed: 0, on_hold: false, recipient_settlement_id: 'setl_one' };
  assert.equal(routeTransferState(transfer), 'awaiting_settlement');
  assert.equal(routeTransferState({ ...transfer, on_hold: true }), 'held');
  assert.equal(routeTransferState(transfer, { id: 'setl_other', entity: 'settlement', status: 'processed' }),
    'awaiting_settlement');
  assert.equal(routeTransferState(transfer, { id: 'setl_one', entity: 'settlement', status: 'processed' }), 'settled');
  assert.equal(routeTransferState({ ...transfer, amount_reversed: 1 }), 'partially_reversed');
  assert.equal(routeTransferState({ ...transfer, amount_reversed: 10000 }), 'reversed');
});
