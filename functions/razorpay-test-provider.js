import { PaymentError } from './rent-payments.js';

export function razorpayTestProvider(keyId, keySecret, fetcher = fetch) {
  if (!/^rzp_test_[A-Za-z0-9]+$/.test(keyId ?? '') || typeof keySecret !== 'string' || keySecret.length < 20) {
    throw new PaymentError('failed-precondition', 'Only configured Razorpay test credentials are enabled.');
  }
  async function request(path, body) {
    const response = await fetcher(`https://api.razorpay.com/v1/${path}`, {
      method: body ? 'POST' : 'GET', signal: AbortSignal.timeout(20000),
      headers: { Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
        'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) {
      const error = new PaymentError('unavailable', 'The test gateway could not confirm this request.');
      error.definitive = response.status >= 400 && response.status < 500 && response.status !== 408 && response.status !== 429;
      throw error;
    }
    return response.json();
  }
  async function collection(path) {
    const result = await request(path);
    if (result.entity !== 'collection' || !Array.isArray(result.items)) throw new PaymentError('internal', 'Unexpected gateway collection.');
    return result.items;
  }
  return { keyId, keySecret,
    createOrder: body => request('orders', body),
    findOrders: receipt => collection(`orders?receipt=${encodeURIComponent(receipt)}&count=100`),
    payment: id => request(`payments/${encodeURIComponent(id)}`),
    orderPayments: id => collection(`orders/${encodeURIComponent(id)}/payments`),
  };
}
