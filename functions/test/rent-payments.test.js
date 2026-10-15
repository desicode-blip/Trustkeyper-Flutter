import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { createRentPaymentService, rentPeriods, validPaymentSignature } from '../rent-payments.js';
import { approvalDigest } from '../agreement-approvals.js';
import { reviewSnapshot } from '../agreement-review.js';
import { razorpayTestProvider } from '../razorpay-test-provider.js';

function fixture() {
  let time = Date.parse('2026-10-10T00:00:00Z');
  let events = 0;
  const agreement = { schemaVersion: 2, revision: 1, status: 'reviewed', brokerUid: 'broker', propertyAddress: 'TEST Flat 402',
    owners: [{ id: 'owner', name: 'Test Owner', phone: '+911111111111', email: '', rentSharePaise: 0, depositSharePaise: 0 }],
    tenants: [{ id: 'tenant', name: 'Test Tenant', phone: '+912222222222', email: '', rentSharePaise: 1100000, depositSharePaise: 2200000 },
      { id: 'tenant2', name: 'Test Tenant Two', phone: '+913333333333', email: '', rentSharePaise: 1100000, depositSharePaise: 2200000 }],
    monthlyRentPaise: 2200000, monthlyMaintenancePaise: 20001, securityDepositPaise: 4400000,
    ownerBrokeragePaise: 1100000, tenantBrokeragePaise: 2200000, startDateISO: '2026-10-01T00:00:00.000', endDateISO: '2027-08-31T00:00:00.000',
    rentDueDay: 5, lockInMonths: 6, noticeMonths: 1 };
  agreement.agreementCopy = { mode: 'demo', revision: 1, digest: approvalDigest(reviewSnapshot(agreement)), people: [
    { id: 'owner', uid: 'owner', phone: '+911111111111', role: 'owner' },
    { id: 'tenant', uid: 'tenant', phone: '+912222222222', role: 'tenant' },
    { id: 'tenant2', uid: 'tenant2', phone: '+913333333333', role: 'tenant' },
  ] };
  let data = new Map([['agreements/test', agreement], ['users/tenant', { roles: ['tenant'] }]]);
  const store = { transaction: async handler => {
    const next = structuredClone(data);
    let written = false;
    const result = await handler({
      get: async path => { assert.equal(written, false, 'all reads precede writes'); return next.get(path); },
      set: (path, value) => { written = true; next.set(path, structuredClone(value)); },
      update: (path, value) => { written = true; next.set(path, { ...next.get(path), ...structuredClone(value) }); },
    });
    data = next;
    return result;
  } };
  const provider = { keyId: 'rzp_test_example', keySecret: 'test-secret-at-least-24-characters', orders: [], payments: [],
    createOrder: async body => {
      const order = { ...body, id: `order_test${provider.orders.length + 1}` };
      provider.orders.push(order);
      if (provider.error) throw provider.error;
      return order;
    },
    findOrders: async receipt => provider.orders.filter(order => order.receipt === receipt),
    payment: async id => provider.payments.find(payment => payment.id === id),
    orderPayments: async id => provider.payments.filter(payment => payment.order_id === id),
  };
  const identity = (uid = 'tenant', phone = '+912222222222', signInProvider = 'phone') => ({ uid,
    token: { phone_number: phone, firebase: { sign_in_provider: signInProvider } } });
  const service = auth => createRentPaymentService({ store, provider, auth, now: () => time, eventId: () => `event${++events}` });
  const flow = service(identity());
  const input = { agreementId: 'test', revision: 1, operationId: 'one', months: ['2026-10'] };
  function payment(intent, overrides = {}) {
    const record = { id: `pay_test${provider.payments.length + 1}`, order_id: intent.orderId,
      amount: intent.amountPaise, currency: 'INR', status: 'captured', captured: true, method: 'upi', ...overrides };
    provider.payments.push(record);
    const signature = createHmac('sha256', provider.keySecret).update(`${intent.orderId}|${record.id}`).digest('hex');
    return { intentId: intent.intentId, paymentId: record.id, signature };
  }
  return { agreement, flow, input, payment, provider, service, identity, store,
    get: path => data.get(path), set: (path, value) => data.set(path, value), all: () => [...data], clock: value => { time = value; } };
}

test('tenant OTP, exact copy/digest and enabled profile required; owners cannot pay tenant shares', async () => {
  const value = fixture();
  for (const identity of [undefined, value.identity('owner', '+911111111111'), value.identity('tenant', '+919999999999'),
    value.identity('tenant', '+912222222222', 'password')]) {
    await assert.rejects(value.service(identity).quote(value.input));
  }
  value.set('users/tenant', { paused: true });
  await assert.rejects(value.flow.quote(value.input));
  value.set('users/tenant', { roles: ['tenant'] });
  value.agreement.monthlyMaintenancePaise++;
  value.set('agreements/test', value.agreement);
  await assert.rejects(value.flow.quote(value.input));
});

test('first invoice uses exact shares plus maintenance, no brokerage or client-controlled amounts', async () => {
  const value = fixture();
  const quote = await value.flow.quote(value.input);
  assert.equal(quote.firstPayment, true);
  assert.equal(quote.legalReady, false);
  const intent = await value.flow.begin({ ...value.input, amountPaise: 100 });
  assert.equal(intent.amountPaise, 3310001);
  assert.equal(intent.depositPaise, 2200000);
  assert.equal(intent.mode, 'test');
  assert.equal(value.provider.orders[0].partial_payment, false);
  assert.equal(intent.keySecret, undefined);
  assert.equal(value.provider.orders.length, 1);
  assert.equal((await value.flow.begin(value.input)).orderId, intent.orderId);
  await assert.rejects(value.flow.begin({ ...value.input, months: ['2026-11'] }), { code: 'aborted' });
  await assert.rejects(value.flow.begin({ ...value.input, operationId: 'two' }));
});

test('deposit and initial month must be collected before any advance months', async () => {
  const value = fixture();
  for (const months of [[], ['2026-11'], ['2026-10', '2026-11'], ['2026-10', '2026-10'], ['2029-01']]) {
    await assert.rejects(value.flow.begin({ ...value.input, months }));
  }
});

test('signature alone or authorized payment never reduces balances; exact captured API response required', async () => {
  const value = fixture();
  const intent = await value.flow.begin(value.input);
  const confirmation = value.payment(intent, { status: 'authorized', captured: false });
  await assert.rejects(value.flow.confirm({ ...confirmation, signature: '0'.repeat(64) }));
  assert.equal((await value.flow.confirm(confirmation)).status, 'awaiting_payment');
  assert.equal(value.all().filter(([path]) => path.startsWith('payments/')).length, 0);
  value.provider.payments[0].status = 'captured';
  value.provider.payments[0].captured = true;
  const receipt = await value.flow.confirm(confirmation);
  assert.equal(receipt.status, 'paid');
  assert.match(receipt.receiptNumber, /^TK-TEST-/);
  assert.equal(value.get('agreements/test').status, 'reviewed');
  assert.deepEqual(await value.flow.confirm(confirmation), receipt);
  assert.equal(value.all().filter(([path]) => path.startsWith('payments/')).length, 1);
  assert.equal(value.get(`payments/${confirmation.paymentId}`).deliveryStatus, 'not_sent');
});

test('captured amount, currency, order, refund and UID mismatches cannot be credited', async () => {
  for (const overrides of [{ amount: 1 }, { currency: 'USD' }, { order_id: 'order_outside' }, { amount_refunded: 1 }]) {
    const value = fixture();
    const intent = await value.flow.begin(value.input);
    await assert.rejects(value.flow.confirm(value.payment(intent, overrides)));
    assert.equal(value.all().filter(([path]) => path.startsWith('payments/')).length, 0);
  }
  const value = fixture();
  const intent = await value.flow.begin(value.input);
  await assert.rejects(value.service(value.identity('tenant2', '+913333333333')).reconcile({ intentId: intent.intentId }));
});

test('reconcile recovers a lost callback, marks each month once and permits advance payments only within term', async () => {
  const value = fixture();
  const initial = await value.flow.begin(value.input);
  value.payment(initial);
  assert.equal((await value.flow.reconcile({ intentId: initial.intentId })).status, 'paid');
  const quote = await value.flow.quote(value.input);
  assert.equal(quote.firstPayment, false);
  assert.equal(quote.depositPaise, 0);
  assert.equal(quote.periods[0].paid, true);
  await assert.rejects(value.flow.begin({ ...value.input, operationId: 'again' }));
  const advance = await value.flow.begin({ ...value.input, operationId: 'advance', months: ['2026-11', '2026-12', '2027-01'] });
  assert.equal(advance.depositPaise, 0);
  assert.equal(advance.amountPaise, 3330003);
  await value.flow.confirm(value.payment(advance));
  assert.equal((await value.flow.quote(value.input)).periods.filter(period => period.paid).length, 4);
});

test('unknown order creation is reconciled by its private receipt, never blindly created twice', async () => {
  const value = fixture();
  value.provider.error = new Error('network timeout');
  await assert.rejects(value.flow.begin(value.input));
  value.clock(Date.parse('2026-10-10T00:00:30Z'));
  const saved = value.all().find(([path]) => path.startsWith('rentPaymentIntents/'))[1];
  const recovered = await value.flow.reconcile({ intentId: saved.id });
  assert.equal(recovered.orderId, 'order_test1');
  assert.equal(value.provider.orders.length, 1);
});

test('webhook signs raw bytes and is idempotent even when a failed event arrives after capture', async () => {
  const value = fixture();
  const intent = await value.flow.begin(value.input);
  const confirmation = value.payment(intent);
  const body = Buffer.from(JSON.stringify({ event: 'payment.captured', payload: { payment: { entity: value.provider.payments[0] } } }));
  const secret = 'different-webhook-secret';
  const signature = createHmac('sha256', secret).update(body).digest('hex');
  await assert.rejects(value.flow.webhook(Buffer.concat([body, Buffer.from(' ')]), signature, secret, 'event-one'));
  assert.deepEqual(await value.flow.webhook(body, signature, secret, 'event-one'), { processed: true });
  assert.deepEqual(await value.flow.webhook(body, signature, secret, 'event-one'), { duplicate: true });
  const late = Buffer.from(JSON.stringify({ event: 'payment.failed', payload: { payment: { entity: value.provider.payments[0] } } }));
  await value.flow.webhook(late, createHmac('sha256', secret).update(late).digest('hex'), secret, 'event-two');
  assert.equal(value.get(`payments/${confirmation.paymentId}`).status, 'paid');
  assert.equal(value.all().filter(([path]) => path.startsWith('payments/')).length, 1);
});

test('capture after changed terms is recorded for reconciliation, not lost or credited to new balances', async () => {
  const value = fixture();
  const intent = await value.flow.begin(value.input);
  value.payment(intent);
  value.agreement.revision = 2;
  value.set('agreements/test', value.agreement);
  const body = Buffer.from(JSON.stringify({ event: 'payment.captured', payload: { payment: { entity: value.provider.payments[0] } } }));
  await value.flow.webhook(body, createHmac('sha256', 'secret').update(body).digest('hex'), 'secret', 'changed');
  assert.equal(value.get('payments/pay_test1').status, 'reconciliation_required');
  await value.flow.webhook(body, createHmac('sha256', 'secret').update(body).digest('hex'), 'secret', 'changed-again');
  assert.equal(value.all().filter(([path]) => path.startsWith('payments/')).length, 1);
});

test('first payment selects the current Indian calendar month, not old unpaid rent or advance months', async () => {
  const value = fixture();
  value.clock(Date.parse('2026-10-31T18:30:00Z'));
  const quote = await value.flow.quote(value.input);
  assert.equal(quote.firstPaymentMonth, '2026-11');
  await assert.rejects(value.flow.begin(value.input));
  const current = await value.flow.begin({ ...value.input, months: ['2026-11'] });
  await value.flow.confirm(value.payment(current));
  const after = await value.flow.quote(value.input);
  assert.equal(after.periods[0].paid, false);
  assert.equal(after.periods[1].paid, true);
  assert.equal(after.depositPaise, 0);
  const expired = fixture();
  expired.clock(Date.parse('2027-09-01T00:00:00Z'));
  await assert.rejects(expired.flow.begin(expired.input), { code: 'failed-precondition' });
});

test('capture races recheck paused profiles, actual snapshot and verified tenant membership', async () => {
  for (const change of ['paused', 'snapshot', 'membership']) {
    const value = fixture();
    const intent = await value.flow.begin(value.input);
    value.payment(intent);
    if (change === 'paused') value.set('users/tenant', { paused: true });
    if (change === 'snapshot') value.agreement.monthlyMaintenancePaise++;
    if (change === 'membership') value.agreement.agreementCopy.people = [];
    value.set('agreements/test', value.agreement);
    const body = Buffer.from(JSON.stringify({ event: 'payment.captured', payload: { payment: { entity: value.provider.payments[0] } } }));
    await value.flow.webhook(body, createHmac('sha256', 'secret').update(body).digest('hex'), 'secret', change);
    assert.equal(value.get('payments/pay_test1').status, 'reconciliation_required');
    const account = value.all().find(([path]) => path.startsWith('rentPaymentAccounts/'))[1];
    assert.deepEqual(account.paidMonths, []);
    assert.equal(account.depositPaid, false);
  }
});

test('calendar months prorate actual days, bound the term and distribute maintenance without losing paise', () => {
  const value = fixture();
  value.agreement.startDateISO = '2026-10-16T00:00:00.000';
  const first = rentPeriods(reviewSnapshot(value.agreement), 'tenant')[0];
  assert.equal(first.days, 16);
  assert.equal(first.rentPaise, Math.round(1100000 * 16 / 31));
  const firstTenant = rentPeriods(reviewSnapshot(fixture().agreement), 'tenant')[0];
  const secondTenant = rentPeriods(reviewSnapshot(fixture().agreement), 'tenant2')[0];
  assert.equal(firstTenant.maintenancePaise + secondTenant.maintenancePaise, 20001);
  const second = rentPeriods(reviewSnapshot(value.agreement), 'tenant2')[0];
  assert.equal(first.rentPaise + second.rentPaise, Math.round(2200000 * 16 / 31));
  assert.equal(first.maintenancePaise + second.maintenancePaise, Math.round(20001 * 16 / 31));
  assert.equal(validPaymentSignature('x', 'bad', 'secret'), false);
  assert.throws(() => razorpayTestProvider('rzp_live_not_allowed', 'long-test-secret-123456789'));
});
