const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');

async function completeTestCheckout({ keyId, orderId, amountPaise, playwrightPath, evidencePrefix }) {
  assert.match(keyId, /^rzp_test_[A-Za-z0-9]+$/);
  assert.match(orderId, /^order_[A-Za-z0-9]+$/);
  assert.ok(Number.isSafeInteger(amountPaise) && amountPaise >= 100 && amountPaise <= 100000000);
  const playwright = require(playwrightPath);
  const server = http.createServer((request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    response.end('<!doctype html><html><head><title>TrustKeyper TEST checkout</title><script src="https://checkout.razorpay.com/v1/checkout.js"></script></head><body>TEST MODE only. No real money.</body></html>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  let phase = 'opening SDK';
  try {
    browser = await playwright.chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
    const page = await browser.newPage({ viewport: { width: 440, height: 920 } });
    await page.goto(`http://127.0.0.1:${server.address().port}`, { waitUntil: 'load' });
    await page.evaluate(input => {
      window.checkoutResult = null;
      window.checkoutFailure = null;
      const checkout = new window.Razorpay({ ...input, handler: result => { window.checkoutResult = result; } });
      checkout.on('payment.failed', failure => { window.checkoutFailure = failure.error?.code; });
      checkout.open();
    }, { key: keyId, order_id: orderId, amount: amountPaise, currency: 'INR',
      name: 'TrustKeyper TEST', description: 'Synthetic test · no real money',
      prefill: { contact: '9000090000', email: 'test@example.invalid' } });
    await page.waitForSelector('iframe.razorpay-checkout-frame', { timeout: 45000 });
    const frame = page.frameLocator('iframe.razorpay-checkout-frame');
    await frame.getByText('Netbanking', { exact: true }).waitFor({ timeout: 45000 });
    await frame.getByText('Netbanking', { exact: true }).click();
    phase = 'opening TEST bank';
    const bankWindow = page.context().waitForEvent('page', { timeout: 20000 }).catch(() => null);
    await frame.getByRole('button', { name: /^Axis\s/ }).first().click();
    const bank = await bankWindow;
    assert.ok(bank, 'Expected the gateway TEST bank window.');
    await bank.waitForURL(/^https:/, { timeout: 20000 });
    await bank.waitForLoadState('domcontentloaded');
    process.stdout.write(`TEST bank host: ${new URL(bank.url()).hostname}\n`);
    assert.equal(new URL(bank.url()).hostname, 'api.razorpay.com');
    phase = 'confirming TEST mock-bank result';
    await bank.getByRole('button', { name: 'Success', exact: true }).waitFor({ timeout: 20000 });
    await bank.screenshot({ path: path.resolve(`${evidencePrefix}-mock-bank.png`), fullPage: true });
    await bank.getByRole('button', { name: 'Success', exact: true }).click();
    phase = 'waiting for signed callback';
    await page.waitForFunction(() => window.checkoutResult !== null || window.checkoutFailure !== null, null, { timeout: 45000 });
    const callback = await page.evaluate(() => window.checkoutResult);
    assert.equal(callback?.razorpay_order_id, orderId);
    assert.match(callback.razorpay_payment_id, /^pay_[A-Za-z0-9]+$/);
    assert.match(callback.razorpay_signature, /^[a-f0-9]{64}$/);
    await page.screenshot({ path: path.resolve(`${evidencePrefix}-callback.png`), fullPage: true });
    return { paymentId: callback.razorpay_payment_id, signature: callback.razorpay_signature };
  } catch (error) {
    process.stderr.write(`TEST checkout stopped at ${phase}: ${error.name}.\n`);
    throw error;
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
}

module.exports = { completeTestCheckout };
