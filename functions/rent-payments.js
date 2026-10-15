import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { verifiedPhone } from './verified-phone.js';
import { approvalDigest } from './agreement-approvals.js';
import { reviewSnapshot } from './agreement-review.js';

export class PaymentError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const requireValue = (value, message, code = 'failed-precondition') => {
  if (!value) throw new PaymentError(code, message);
};
const safe = value => typeof value === 'string' && /^[\w-]{1,150}$/.test(value);
const hash = value => createHash('sha256').update(value).digest('hex');
const monthKey = date => date.toISOString().slice(0, 7);
const money = value => Number.isSafeInteger(value) && value >= 0;
function allocate(total, tenants, monthlyRentPaise) {
  const allocations = tenants.map(person => {
    const numerator = BigInt(total) * BigInt(person.rentSharePaise);
    return { id: person.id, amount: Number(numerator / BigInt(monthlyRentPaise)),
      remainder: numerator % BigInt(monthlyRentPaise) };
  });
  const remainder = total - allocations.reduce((sum, part) => sum + part.amount, 0);
  const ordered = [...allocations].sort((left, right) => left.remainder === right.remainder
    ? left.id.localeCompare(right.id) : left.remainder > right.remainder ? -1 : 1);
  for (let index = 0; index < remainder; index++) ordered[index].amount++;
  return allocations;
}

export function validPaymentSignature(payload, signature, secret) {
  if (!secret || !/^[a-f0-9]{64}$/.test(signature ?? '')) return false;
  const expected = createHmac('sha256', secret).update(payload).digest();
  return timingSafeEqual(expected, Buffer.from(signature, 'hex'));
}

export function rentPeriods(snapshot, personId) {
  const person = snapshot.tenants.find(person => person.id === personId);
  requireValue(person, 'This tenant is not in this version.');
  const start = new Date(`${snapshot.startDateISO.slice(0, 10)}T00:00:00Z`);
  const end = new Date(`${snapshot.endDateISO.slice(0, 10)}T00:00:00Z`);
  const periods = [];
  const cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
  while (cursor <= end && periods.length <= 120) {
    const first = new Date(cursor);
    const last = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 0));
    const coveredStart = new Date(Math.max(first.getTime(), start.getTime()));
    const coveredEnd = new Date(Math.min(last.getTime(), end.getTime()));
    const days = Math.round((coveredEnd - coveredStart) / 86400000) + 1;
    const daysInMonth = last.getUTCDate();
    const rentPaise = allocate(Math.round(snapshot.monthlyRentPaise * days / daysInMonth),
      snapshot.tenants, snapshot.monthlyRentPaise).find(part => part.id === personId).amount;
    const maintenancePaise = allocate(Math.round(snapshot.monthlyMaintenancePaise * days / daysInMonth),
      snapshot.tenants, snapshot.monthlyRentPaise).find(part => part.id === personId).amount;
    periods.push({ month: monthKey(first), rentPaise, maintenancePaise,
      totalPaise: rentPaise + maintenancePaise, days, daysInMonth,
      from: coveredStart.toISOString().slice(0, 10), to: coveredEnd.toISOString().slice(0, 10) });
    cursor.setUTCMonth(cursor.getUTCMonth() + 1);
  }
  requireValue(periods.length > 0 && periods.length <= 120, 'The agreement period must be at most ten years.');
  return periods;
}

export function createRentPaymentService({ store, provider, auth, now = Date.now, eventId = randomUUID }) {
  function initialMonth(periods) {
    const currentMonth = monthKey(new Date(now() + 330 * 60000));
    if (currentMonth < periods[0].month) return periods[0].month;
    return periods.find(period => period.month === currentMonth)?.month ?? null;
  }
  async function context(transaction, agreementId, revision) {
    requireValue(auth?.uid, 'Log in with your verified tenant phone.', 'unauthenticated');
    requireValue(safe(agreementId) && Number.isSafeInteger(revision) && revision > 0, 'Choose a saved agreement version.', 'invalid-argument');
    const profile = await transaction.get(`users/${auth.uid}`);
    requireValue(profile?.paused !== true, 'This account is paused.', 'permission-denied');
    const agreement = await transaction.get(`agreements/${agreementId}`);
    const copy = agreement?.agreementCopy;
    requireValue(agreement?.revision === revision && copy?.revision === revision &&
      ['reviewed', 'signed_copy_received', 'active'].includes(agreement.status), 'Your reviewed agreement copy must be ready first.');
    const snapshot = reviewSnapshot(agreement);
    requireValue(copy.digest === approvalDigest(snapshot), 'The agreement terms changed. Reopen the current copy.');
    const people = copy.people.filter(person => person.role === 'tenant' && person.uid === auth.uid &&
      person.phone === verifiedPhone(auth));
    requireValue(people.length === 1, 'Only the verified tenant can pay their personal share.', 'permission-denied');
    const person = snapshot.tenants.find(person => person.id === people[0].id);
    requireValue(person, 'The verified tenant share is unavailable.');
    const accountId = hash(JSON.stringify(['test', agreementId, revision, person.id]));
    const account = await transaction.get(`rentPaymentAccounts/${accountId}`) ?? { paidMonths: [], depositPaid: false };
    return { agreementId, revision, agreement, snapshot, copy, person, accountId, account,
      periods: rentPeriods(snapshot, person.id) };
  }
  function plan(current, months) {
    const firstPayment = current.account.depositPaid !== true;
    const available = current.periods.filter(period => !current.account.paidMonths.includes(period.month));
    const firstPaymentMonth = initialMonth(current.periods);
    requireValue(!firstPayment || firstPaymentMonth, 'This agreement has ended. Ask the team to review outstanding rent before the first payment.');
    const selected = months ?? (firstPayment ? [firstPaymentMonth] : available.slice(0, 1).map(period => period.month));
    requireValue(Array.isArray(selected) && selected.length > 0 && selected.length <= 120 &&
      new Set(selected).size === selected.length && selected.every(month => available.some(period => period.month === month)),
    'Select unpaid months within this agreement.', 'invalid-argument');
    requireValue(!firstPayment || selected.length === 1 && selected[0] === firstPaymentMonth,
      'First payment is only the current rental month, deposit and maintenance.', 'invalid-argument');
    const lines = available.filter(period => selected.includes(period.month));
    const depositPaise = firstPayment ? current.person.depositSharePaise : 0;
    const amountPaise = depositPaise + lines.reduce((sum, period) => sum + period.totalPaise, 0);
    requireValue(money(amountPaise) && amountPaise >= 100 && amountPaise <= 100000000, 'The checkout amount is outside the supported gateway limits.');
    return { firstPayment, months: lines.map(period => period.month), lines, depositPaise, amountPaise, currency: 'INR' };
  }
  function summary(intent) {
    return { intentId: intent.id, agreementId: intent.agreementId, revision: intent.revision,
      mode: 'test', status: intent.status, orderId: intent.orderId ?? null, amountPaise: intent.amountPaise,
      currency: 'INR', depositPaise: intent.depositPaise, lines: intent.lines,
      paymentId: intent.paymentId ?? null, receiptNumber: intent.receiptNumber ?? null,
      paidAtMs: intent.paidAtMs ?? null, legalReady: intent.legalReady,
      propertyAddress: intent.propertyAddress, payerName: intent.payerName, payerPhone: intent.payerPhone };
  }
  async function owned(transaction, intentId) {
    requireValue(safe(intentId), 'Invalid checkout.', 'invalid-argument');
    const intent = await transaction.get(`rentPaymentIntents/${intentId}`);
    requireValue(intent?.payerUid === auth?.uid, 'This checkout belongs to its verified tenant.', 'permission-denied');
    const current = await context(transaction, intent.agreementId, intent.revision);
    requireValue(current.person.id === intent.personId, 'Your verified tenant identity changed.', 'permission-denied');
    return { intent, current };
  }
  async function attachOrder(intent, order) {
    requireValue(/^order_[A-Za-z0-9]+$/.test(order?.id ?? '') && order.amount === intent.amountPaise &&
      order.currency === 'INR' && order.receipt === intent.providerReceipt, 'Gateway order did not match the saved invoice.', 'internal');
    return store.transaction(async transaction => {
      const saved = await transaction.get(`rentPaymentIntents/${intent.id}`);
      requireValue(saved && (!saved.orderId || saved.orderId === order.id), 'This checkout already has another gateway order.', 'aborted');
      const mapped = await transaction.get(`razorpayTestOrders/${order.id}`);
      requireValue(!mapped || mapped.intentId === intent.id, 'Gateway order is already assigned.', 'aborted');
      transaction.update(`rentPaymentIntents/${intent.id}`, { orderId: order.id,
        status: saved.status === 'paid' ? 'paid' : 'awaiting_payment', updatedAtMs: now() });
      transaction.set(`razorpayTestOrders/${order.id}`, { intentId: intent.id });
      return summary({ ...saved, orderId: order.id, status: saved.status === 'paid' ? 'paid' : 'awaiting_payment' });
    });
  }
  async function settle(intent, payment) {
    requireValue(payment?.order_id === intent.orderId && payment.currency === 'INR' &&
      payment.amount === intent.amountPaise && /^pay_[A-Za-z0-9]+$/.test(payment.id ?? ''), 'Gateway payment does not match this invoice.', 'permission-denied');
    if (payment.status !== 'captured' || payment.captured !== true) return summary(intent);
    requireValue((payment.amount_refunded ?? 0) === 0, 'This payment was refunded; the team must reconcile it.');
    return store.transaction(async transaction => {
      const saved = await transaction.get(`rentPaymentIntents/${intent.id}`);
      const account = await transaction.get(`rentPaymentAccounts/${intent.accountId}`);
      const agreement = await transaction.get(`agreements/${intent.agreementId}`);
      const paymentRecord = await transaction.get(`payments/${payment.id}`);
      const profile = await transaction.get(`users/${intent.payerUid}`);
      requireValue(saved?.orderId === payment.order_id, 'Checkout order changed.', 'aborted');
      if (['paid', 'reconciliation_required'].includes(saved.status)) {
        requireValue(saved.paymentId === payment.id, 'This order has more than one captured payment. Contact the team.');
        return summary(saved);
      }
      requireValue(!paymentRecord, 'Payment was assigned to a different checkout.', 'aborted');
      let termsMatch = false;
      try {
        termsMatch = profile?.paused !== true && agreement?.revision === intent.revision &&
          agreement.agreementCopy?.digest === intent.digest && approvalDigest(reviewSnapshot(agreement)) === intent.digest &&
          ['reviewed', 'signed_copy_received', 'active'].includes(agreement.status) &&
          agreement.agreementCopy.people.some(person => person.role === 'tenant' && person.id === intent.personId &&
            person.uid === intent.payerUid && person.phone === intent.payerPhone);
      } catch (_) {}
      const balanceMatch = account?.pendingIntentId === intent.id &&
        !intent.months.some(month => account.paidMonths.includes(month)) &&
        (!intent.firstPayment || account.depositPaid !== true);
      const status = termsMatch && balanceMatch ? 'paid' : 'reconciliation_required';
      const receiptNumber = `TK-TEST-${payment.id.slice(4)}`;
      const paidAtMs = now();
      const record = { ...summary({ ...saved, status, receiptNumber, paidAtMs, paymentId: payment.id }),
        participantUids: intent.participantUids, createdAtMs: paidAtMs, payerUid: intent.payerUid,
        status, amountPaise: intent.amountPaise, agreementId: intent.agreementId, mode: 'test',
        method: typeof payment.method === 'string' ? payment.method : 'gateway',
        settlementStatus: 'test_only_no_payout', deliveryStatus: 'not_sent' };
      transaction.set(`payments/${payment.id}`, record);
      transaction.update(`rentPaymentIntents/${intent.id}`, { status, paymentId: payment.id, receiptNumber, paidAtMs, updatedAtMs: now() });
      if (status === 'paid') {
        transaction.update(`rentPaymentAccounts/${intent.accountId}`, {
          paidMonths: [...account.paidMonths, ...intent.months].sort(),
          depositPaid: account.depositPaid || intent.firstPayment, pendingIntentId: null, updatedAtMs: now(),
        });
      }
      transaction.set(`agreements/${intent.agreementId}/events/${eventId()}`, {
        action: 'payment.test_captured', actorUid: intent.payerUid, revision: intent.revision,
        paymentId: payment.id, amountPaise: intent.amountPaise, status, createdAtMs: now(),
      });
      return summary({ ...saved, status, paymentId: payment.id, receiptNumber, paidAtMs });
    });
  }
  return {
    async quote({ agreementId, revision }) {
      return store.transaction(async transaction => {
        const current = await context(transaction, agreementId, revision);
        const pending = current.account.pendingIntentId
          ? await transaction.get(`rentPaymentIntents/${current.account.pendingIntentId}`) : null;
        return { agreementId, revision, mode: 'test', propertyAddress: current.snapshot.propertyAddress,
          payerName: current.person.name, legalReady: current.copy.mode === 'externally_signed',
          firstPayment: current.account.depositPaid !== true,
          firstPaymentMonth: initialMonth(current.periods),
          depositPaise: current.account.depositPaid ? 0 : current.person.depositSharePaise,
          periods: current.periods.map(period => ({ ...period, paid: current.account.paidMonths.includes(period.month) })),
          pending: pending ? summary(pending) : null };
      });
    },
    async begin({ agreementId, revision, months, operationId }) {
      requireValue(safe(operationId) && Array.isArray(months), 'Keep the checkout open and retry.', 'invalid-argument');
      const id = hash(JSON.stringify([auth?.uid, agreementId, revision, operationId]));
      const payloadHash = hash(JSON.stringify([...(months ?? [])].sort()));
      const result = await store.transaction(async transaction => {
        const current = await context(transaction, agreementId, revision);
        const previous = await transaction.get(`rentPaymentIntents/${id}`);
        const pending = current.account.pendingIntentId
          ? await transaction.get(`rentPaymentIntents/${current.account.pendingIntentId}`) : null;
        if (previous) {
          requireValue(previous.payloadHash === payloadHash, 'Retry the same selected months.', 'aborted');
          return { intent: previous, create: false };
        }
        requireValue(!pending || ['paid', 'creation_failed'].includes(pending.status),
          'A checkout is already open. Resume or check its status before starting another.');
        const due = plan(current, months);
        const intent = { id, ...due, payloadHash, operationId, agreementId, revision, accountId: current.accountId,
          personId: current.person.id, payerUid: auth.uid, payerPhone: current.person.phone,
          payerName: current.person.name, propertyAddress: current.snapshot.propertyAddress,
          digest: current.copy.digest, mode: 'test', legalReady: current.copy.mode === 'externally_signed',
          participantUids: [...new Set([auth.uid, current.agreement.brokerUid, ...current.copy.people.map(person => person.uid)])],
          providerReceipt: `tk_${id.slice(0, 32)}`, status: 'creating_order', createdAtMs: now(), updatedAtMs: now() };
        transaction.set(`rentPaymentIntents/${id}`, intent);
        transaction.set(`rentPaymentAccounts/${current.accountId}`, { ...current.account, agreementId, revision,
          personId: current.person.id, payerUid: auth.uid, mode: 'test', pendingIntentId: id, updatedAtMs: now() });
        return { intent, create: true };
      });
      let intent = result.intent;
      if (result.create) {
        try {
          const order = await provider.createOrder({ amount: intent.amountPaise, currency: 'INR',
            receipt: intent.providerReceipt, partial_payment: false, notes: { tk_test_intent: id } });
          return { ...await attachOrder(intent, order), keyId: provider.keyId };
        } catch (error) {
          await store.transaction(async transaction => {
            const saved = await transaction.get(`rentPaymentIntents/${id}`);
            if (!saved.orderId) transaction.update(`rentPaymentIntents/${id}`, {
              status: error.definitive === true ? 'creation_failed' : 'creation_unknown', updatedAtMs: now(),
            });
          });
          throw new PaymentError('unavailable', 'Order creation could not be confirmed. Check status; do not create another checkout.');
        }
      }
      if (!intent.orderId && now() - intent.createdAtMs >= 25000) {
        const orders = await provider.findOrders(intent.providerReceipt);
        requireValue(orders.length <= 1, 'More than one gateway order exists. Contact the team.');
        if (orders.length === 1) return { ...await attachOrder(intent, orders[0]), keyId: provider.keyId };
      }
      return { ...summary(intent), keyId: provider.keyId };
    },
    async confirm({ intentId, paymentId, signature }) {
      const { intent } = await store.transaction(transaction => owned(transaction, intentId));
      requireValue(intent.orderId && /^pay_[A-Za-z0-9]+$/.test(paymentId ?? '') &&
        validPaymentSignature(`${intent.orderId}|${paymentId}`, signature, provider.keySecret),
      'Gateway confirmation could not be verified. Check payment status.', 'permission-denied');
      return settle(intent, await provider.payment(paymentId));
    },
    async reconcile({ intentId }) {
      let { intent } = await store.transaction(transaction => owned(transaction, intentId));
      if (!intent.orderId) {
        const result = await this.begin({ agreementId: intent.agreementId, revision: intent.revision,
          months: intent.months, operationId: intent.operationId });
        return result;
      }
      const payments = await provider.orderPayments(intent.orderId);
      const captured = payments.filter(payment => payment.status === 'captured' && payment.captured === true);
      requireValue(captured.length <= 1, 'More than one captured payment exists. Contact the team.');
      if (captured.length === 1) return settle(intent, captured[0]);
      return { ...summary(intent), keyId: provider.keyId };
    },
    async webhook(rawBody, signature, webhookSecret, eventHeader) {
      requireValue(Buffer.isBuffer(rawBody) && rawBody.length <= 512 * 1024 &&
        validPaymentSignature(rawBody, signature, webhookSecret), 'Invalid webhook signature.', 'permission-denied');
      let event;
      try { event = JSON.parse(rawBody.toString('utf8')); } catch { throw new PaymentError('invalid-argument', 'Invalid webhook body.'); }
      if (!['payment.captured', 'order.paid', 'payment.failed'].includes(event.event)) return { ignored: true };
      const payment = event.payload?.payment?.entity;
      requireValue(/^order_[A-Za-z0-9]+$/.test(payment?.order_id ?? '') && /^pay_[A-Za-z0-9]+$/.test(payment?.id ?? ''), 'Invalid payment event.', 'invalid-argument');
      const mapping = await store.transaction(transaction => transaction.get(`razorpayTestOrders/${payment.order_id}`));
      if (!mapping) return { ignored: true };
      const eventId = hash(typeof eventHeader === 'string' && eventHeader.length <= 200 ? eventHeader : rawBody);
      const path = `razorpayTestEvents/${eventId}`;
      const previous = await store.transaction(transaction => transaction.get(path));
      if (previous) return { duplicate: true };
      const intent = await store.transaction(transaction => transaction.get(`rentPaymentIntents/${mapping.intentId}`));
      const actual = await provider.payment(payment.id);
      const result = await settle(intent, actual);
      await store.transaction(async transaction => {
        const duplicate = await transaction.get(path);
        if (!duplicate) transaction.set(path, { orderId: payment.order_id, paymentId: payment.id,
          event: event.event, status: result.status, processedAtMs: now() });
      });
      return { processed: true };
    },
  };
}
