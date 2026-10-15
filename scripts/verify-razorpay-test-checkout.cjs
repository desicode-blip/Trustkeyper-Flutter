const assert = require('node:assert/strict');
const path = require('node:path');
const http = require('node:http');
const fs = require('node:fs');
const { randomUUID } = require('node:crypto');
const { pathToFileURL } = require('node:url');
const { loadCredentials } = require('./import-razorpay-test-credentials.cjs');

async function main() {
  if (!process.argv.includes('--test-mode-order')) throw new Error('Explicit test-mode order acknowledgement required.');
  const credentials = loadCredentials(process.argv.find(argument => argument.startsWith('--python='))?.slice(9),
    process.argv.filter(argument => argument.startsWith('--pdf=')).map(argument => argument.slice(6)));
  const { razorpayTestProvider } = await import(pathToFileURL(path.join(__dirname, '../functions/razorpay-test-provider.js')));
  const provider = razorpayTestProvider(credentials.keyId, credentials.keySecret);
  const contextPath = path.join(__dirname, '../output/ui-audit/build23-test-order.json');
  const previous = process.argv.includes('--reuse-unpaid-order') ? JSON.parse(fs.readFileSync(contextPath, 'utf8')) : null;
  const matches = previous ? await provider.findOrders(previous.receipt) : [];
  if (previous) assert.equal(matches.length, 1);
  const order = previous ? matches[0] : await provider.createOrder({ amount: 3300000, currency: 'INR', partial_payment: false,
    receipt: `tk_sdk_${randomUUID().replaceAll('-', '')}`, notes: { purpose: 'isolated_test_checkout_no_real_money' } });
  assert.equal(order.amount, 3300000); assert.equal(order.currency, 'INR'); assert.match(order.id, /^order_/);
  const initial = await provider.orderPayments(order.id);
  assert.equal(order.amount_paid ?? 0, 0);
  assert.ok(['created', 'attempted'].includes(order.status));
  assert.ok(initial.every(payment => ['created', 'failed'].includes(payment.status) && payment.captured === false));
  fs.writeFileSync(contextPath, JSON.stringify({ receipt: order.receipt, orderId: order.id, mode: 'test' }));
  process.stdout.write('PASS: real Razorpay TEST order created and fetched; no real money moved.\n');
  if (process.argv.includes('--complete-test-payment')) {
    const { completeTestCheckout } = require('./razorpay-test-checkout.cjs');
    const callback = await completeTestCheckout({ keyId: credentials.keyId, orderId: order.id,
      amountPaise: order.amount, playwrightPath: process.argv.find(argument => argument.startsWith('--playwright='))?.slice(13),
      evidencePrefix: path.join(__dirname, '../output/ui-audit/build23-provider-completed') });
    const { validPaymentSignature } = await import(pathToFileURL(path.join(__dirname, '../functions/rent-payments.js')));
    assert.ok(validPaymentSignature(`${order.id}|${callback.paymentId}`, callback.signature, credentials.keySecret));
    const payment = await provider.payment(callback.paymentId);
    assert.equal(payment.order_id, order.id); assert.equal(payment.amount, order.amount); assert.equal(payment.currency, 'INR');
    assert.ok(['authorized', 'captured'].includes(payment.status));
    process.stdout.write(`PASS: official TEST mock bank returned a genuine signed callback; provider status is ${payment.status}. No real money moved.\n`);
    return;
  }
  const playwright = require(process.argv.find(argument => argument.startsWith('--playwright='))?.slice(13));
  const server = http.createServer((request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    response.end('<!doctype html><html><head><title>TrustKeyper isolated gateway test</title><script src="https://checkout.razorpay.com/v1/checkout.js"></script></head><body>Isolated Razorpay TEST checkout. No real money.</body></html>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  let page;
  let frame;
  try {
    browser = await playwright.chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
    page = await browser.newPage({ viewport: { width: 440, height: 920 } });
    await page.goto(`http://127.0.0.1:${server.address().port}`, { waitUntil: 'load' });
    await page.evaluate(input => {
      window.checkoutResult = null;
      const checkout = new window.Razorpay({ ...input,
        handler: result => { window.checkoutResult = result; },
        modal: { ondismiss: () => { window.checkoutClosed = true; } } });
      checkout.open();
    }, { key: credentials.keyId, order_id: order.id, amount: order.amount, currency: 'INR',
      name: 'TrustKeyper TEST', description: 'Isolated SDK test · no real money',
      prefill: { contact: '9000090000', email: 'test@example.invalid' } });
    await page.waitForSelector('iframe.razorpay-checkout-frame', { timeout: 45000 });
    frame = page.frameLocator('iframe.razorpay-checkout-frame');
    await frame.locator('body').filter({ hasText: /UPI|Netbanking|Mobile number|Contact|Continue|Email/ }).waitFor({ timeout: 45000 });
    await page.screenshot({ path: path.join(__dirname, '../output/ui-audit/build23-provider-checkout.png'), fullPage: true });
    process.stdout.write('PASS: official Razorpay secure checkout iframe loads in a fresh isolated browser.\n');
    process.stdout.write((await frame.locator('body').innerText()).replace(/\b\d{10}\b/g, '[test phone]').slice(0, 1800) + '\n');
    if (process.argv.includes('--inspect-methods')) {
      process.stdout.write(JSON.stringify(await frame.locator('input').evaluateAll(inputs => inputs.map(input => ({
        type: input.type, name: input.name, placeholder: input.placeholder, ariaLabel: input.getAttribute('aria-label'),
      })))) + '\n');
      if (await frame.getByPlaceholder('Mobile number', { exact: true }).isVisible()) {
        await frame.getByPlaceholder('Mobile number', { exact: true }).fill('9000090000');
        await frame.getByPlaceholder('Email address (optional)', { exact: true }).fill('test@example.invalid');
        await frame.getByRole('button', { name: 'Continue', exact: true }).click();
      }
      await frame.locator('body').filter({ hasText: /Net\s?banking|UPI|Payment options|Verify|OTP|Invalid|valid email/i }).waitFor({ timeout: 20000 });
      process.stdout.write((await frame.locator('body').innerText()).replace(/\b\d{10}\b/g, '[test phone]').slice(0, 2400) + '\n');
      await page.screenshot({ path: path.join(__dirname, '../output/ui-audit/build23-provider-methods.png'), fullPage: true });
      await frame.getByText('Netbanking', { exact: true }).click();
      await frame.locator('body').filter({ hasText: /HDFC|ICICI|Axis|State Bank/ }).waitFor({ timeout: 20000 });
      process.stdout.write((await frame.locator('body').innerText()).replace(/\b\d{10}\b/g, '[test phone]').slice(-2400) + '\n');
      process.stdout.write(JSON.stringify(await frame.getByRole('button').allTextContents()) + '\n');
      await page.screenshot({ path: path.join(__dirname, '../output/ui-audit/build23-provider-banks.png'), fullPage: true });
      if (process.argv.includes('--inspect-test-bank')) {
        const bankWindow = page.context().waitForEvent('page', { timeout: 20000 }).catch(() => null);
        await frame.getByRole('button', { name: /^Axis\s/ }).first().click();
        const bank = await bankWindow;
        assert.ok(bank); await bank.waitForLoadState('domcontentloaded');
        assert.equal(new URL(bank.url()).hostname, 'api.razorpay.com');
        process.stdout.write((await bank.locator('body').innerText()).slice(0, 1500) + '\n');
        await bank.screenshot({ path: path.join(__dirname, '../output/ui-audit/build23-provider-mock-bank.png'), fullPage: true });
      }
    }
    assert.equal((await provider.orderPayments(order.id)).filter(payment => payment.status === 'captured').length, 0);
    process.stdout.write('PASS: loading checkout did not credit or fabricate a payment. The TEST order remains unpaid.\n');
  } catch (error) {
    await page?.screenshot({ path: path.join(__dirname, '../output/ui-audit/build23-provider-interaction.png'), fullPage: true });
    if (frame) process.stdout.write((await frame.locator('body').innerText()).replace(/\b\d{10}\b/g, '[test phone]').slice(0, 2800) + '\n');
    throw error;
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { process.stderr.write(`Isolated TEST checkout verification did not complete: ${error.name}. No credentials logged.\n`); process.exitCode = 1; });
