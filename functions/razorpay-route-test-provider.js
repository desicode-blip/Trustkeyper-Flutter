import { PaymentError } from './rent-payments.js';

const requireValue = (condition, message) => {
  if (!condition) throw new PaymentError('invalid-argument', message);
};
const identifier = (value, prefix) => typeof value === 'string' &&
  new RegExp(`^${prefix}_[A-Za-z0-9]{1,64}$`).test(value);
const amount = value => Number.isSafeInteger(value) && value > 0;

export function razorpayRouteTestProvider(keyId, keySecret, fetcher = fetch) {
  if (!/^rzp_test_[A-Za-z0-9]+$/.test(keyId ?? '') ||
      typeof keySecret !== 'string' || keySecret.length < 20) {
    throw new PaymentError('failed-precondition', 'Only configured Razorpay Route test credentials are enabled.');
  }
  async function request(path, { method = 'GET', body, headers = {} } = {}) {
    let response;
    try {
      response = await fetcher(`https://api.razorpay.com/${path}`, {
        method, signal: AbortSignal.timeout(20000),
        headers: { ...headers, Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
          'Content-Type': 'application/json' },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch (_) {
      throw new PaymentError('unavailable', 'Route could not confirm this test request. Reconcile before retrying a transfer.');
    }
    if (!response.ok) {
      const error = new PaymentError(response.status === 401 || response.status === 403
        ? 'failed-precondition' : 'unavailable',
      'Route could not confirm this test request. Check account activation and reconcile before retrying.');
      error.definitive = response.status >= 400 && response.status < 500 &&
        ![408, 429].includes(response.status);
      throw error;
    }
    try { return await response.json(); } catch (_) {
      throw new PaymentError('unavailable', 'Route returned an unreadable response. Reconcile before retrying.');
    }
  }
  async function collection(path, options) {
    const data = await request(path, options);
    if (data.entity !== 'collection' || !Array.isArray(data.items)) {
      throw new PaymentError('unavailable', 'Route returned an unexpected collection. Reconcile before retrying.');
    }
    return data.items;
  }
  function accountId(value) { requireValue(identifier(value, 'acc'), 'Choose a real Route Linked Account ID.'); }
  function transferId(value) { requireValue(identifier(value, 'trf'), 'Choose a saved Route transfer.'); }
  function paymentId(value) { requireValue(identifier(value, 'pay'), 'Choose a captured gateway payment.'); }
  return {
    mode: 'test',
    async linkedAccount(id) {
      accountId(id);
      const data = await request(`v2/accounts/${id}`);
      if (data.id !== id || data.type !== 'route') {
        throw new PaymentError('failed-precondition', 'The destination is not the requested Route Linked Account.');
      }
      return data;
    },
    async readiness(id, productId) {
      accountId(id);
      requireValue(identifier(productId, 'acc_prd'), 'Choose the saved Route product configuration.');
      const account = await this.linkedAccount(id);
      const product = await request(`v2/accounts/${id}/products/${productId}`);
      if (product.id !== productId || product.account_id !== id || product.product_name !== 'route') {
        throw new PaymentError('failed-precondition', 'The Route configuration does not match this Linked Account.');
      }
      return { accountId: id, productId, mode: 'test', activationStatus: product.activation_status,
        ready: product.activation_status === 'activated' && account.status === 'created' };
    },
    async transfers(id) {
      paymentId(id);
      return collection(`v1/payments/${id}/transfers?count=100`);
    },
    async transfer(id) {
      transferId(id);
      const data = await request(`v1/transfers/${id}`);
      if (data.id !== id || data.entity !== 'transfer') {
        throw new PaymentError('unavailable', 'Route could not match this saved transfer.');
      }
      return data;
    },
    async createHeldTransfers(id, parts) {
      paymentId(id);
      requireValue(Array.isArray(parts) && parts.length > 0 && parts.length <= 100,
        'Choose the saved allocation of this payment.');
      const seen = new Set();
      const transfers = parts.map(part => {
        accountId(part.accountId);
        requireValue(amount(part.amountPaise) && typeof part.operationId === 'string' &&
          /^[\w-]{1,128}$/.test(part.operationId) && !seen.has(part.operationId),
        'Each transfer needs an exact amount and a distinct saved operation.');
        seen.add(part.operationId);
        return { account: part.accountId, amount: part.amountPaise, currency: 'INR',
          on_hold: true, notes: { tk_route_operation: part.operationId } };
      });
      return collection(`v1/payments/${id}/transfers`, { method: 'POST', body: { transfers } });
    },
    async hold(id, onHold, untilSeconds = null) {
      transferId(id);
      requireValue(typeof onHold === 'boolean' && (untilSeconds === null ||
        onHold && Number.isSafeInteger(untilSeconds) && untilSeconds > 0), 'Choose the settlement hold.');
      return request(`v1/transfers/${id}`, { method: 'PATCH',
        body: { on_hold: onHold, ...(untilSeconds === null ? {} : { on_hold_until: untilSeconds }) } });
    },
  };
}

export function routeTransferState(transfer, settlement = null) {
  if (transfer?.entity !== 'transfer' || !identifier(transfer.id, 'trf') ||
      !amount(transfer.amount) || transfer.currency !== 'INR') {
    throw new PaymentError('failed-precondition', 'A genuine INR Route transfer is required.');
  }
  if (!Number.isSafeInteger(transfer.amount_reversed ?? 0) ||
      (transfer.amount_reversed ?? 0) < 0 || (transfer.amount_reversed ?? 0) > transfer.amount) {
    throw new PaymentError('failed-precondition', 'Route reversal totals need reconciliation.');
  }
  if (transfer.amount_reversed === transfer.amount) return 'reversed';
  if ((transfer.amount_reversed ?? 0) > 0) return 'partially_reversed';
  if (transfer.status === 'failed') return 'failed';
  if (transfer.on_hold === true || transfer.on_hold === 1) return 'held';
  if (transfer.status === 'processed' && settlement?.id && settlement.id === transfer.recipient_settlement_id &&
      settlement.entity === 'settlement' && settlement.status === 'processed') return 'settled';
  return transfer.status === 'processed' ? 'awaiting_settlement' : 'processing';
}
