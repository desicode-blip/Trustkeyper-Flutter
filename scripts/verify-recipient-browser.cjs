const assert = require('node:assert/strict');
const path = require('node:path');

module.exports = async function verifyRecipientBrowser(request, { playwrightPath, base, build, label }) {
  assert.ok(/^https:\/\/trustkeyper\.web\.app$|^http:\/\/127\.0\.0\.1:\d+$/.test(base));
  const browser = await require(playwrightPath).chromium.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
  });
  const results = [];
  try {
    for (const mode of ['fresh-mobile', 'slow-first-load', 'restricted-storage', 'read-only-storage']) {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
      const page = await context.newPage();
      if (mode === 'slow-first-load') {
        let delayed = false;
        await page.route('https://www.gstatic.com/firebasejs/**/firebase-app.js', async route => {
          if (!delayed) { delayed = true; await new Promise(resolve => setTimeout(resolve, 24000)); }
          if (!page.isClosed()) await route.continue();
        });
      }
      if (mode === 'restricted-storage') {
        await page.addInitScript(() => {
          for (const name of ['sessionStorage', 'localStorage', 'indexedDB']) {
            Object.defineProperty(window, name, {
              configurable: true,
              get() { throw new DOMException('Persistent browser storage unavailable for test.', 'SecurityError'); },
            });
          }
        });
      }
      if (mode === 'read-only-storage') {
        await page.addInitScript(() => {
          Storage.prototype.setItem = () => { throw new DOMException('Browser storage is full for test.', 'QuotaExceededError'); };
        });
      }
      await page.goto(`${base}/#/documents/request?token=${encodeURIComponent(request.token)}`, { waitUntil: 'domcontentloaded' });
      await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 90000 });
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(element => element.click());
      await page.waitForFunction(() => {
        const text = [document.body.innerText, ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'),
          element => element.getAttribute('aria-label'))].join('\n');
        return text.includes('asked for your documents') || text.includes('Link unavailable') || text.includes('TrustKeyper could not start');
      }, null, { timeout: 90000 });
      const text = await page.evaluate(() => [document.body.innerText,
        ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'), element => element.getAttribute('aria-label'))].join('\n'));
      await page.screenshot({ path: path.join(__dirname, `../output/ui-audit/build${build}-${label}-${mode}.png`), fullPage: true });
      assert.ok(text.includes('asked for your documents'), `Recipient route failed in ${mode}; saved synthetic fixture screenshot.`);
      assert.ok(text.includes(request.brokerName));
      assert.ok(text.includes(`Continue with ${request.phone}`));
      assert.ok(!text.includes('TrustKeyper could not start'));
      assert.ok(!text.includes('Upload documents'));
      assert.ok(new URL(page.url()).hash.startsWith('#/documents/request?token='));
      results.push({ recipientRole: request.role, mode, correctBrokerShown: true, phoneVerificationRequired: true, privateUploadNotExposed: true });
      await context.close();
    }
    return results;
  } finally { await browser.close(); }
};
