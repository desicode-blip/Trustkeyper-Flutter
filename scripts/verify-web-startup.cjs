const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const playwrightPath = process.argv.find(value => value.startsWith('--playwright='))?.slice(13);
  assert.ok(playwrightPath, 'Choose the configured browser runtime.');
  const build = Number(process.argv.find(value => value.startsWith('--build='))?.slice(8) ?? 38);
  assert.ok(Number.isSafeInteger(build));
  const base = process.argv.find(value => value.startsWith('--base='))?.slice(7) ?? 'https://trustkeyper.web.app';
  assert.ok(/^https:\/\/trustkeyper\.web\.app$|^http:\/\/127\.0\.0\.1:\d+$/.test(base));
  const before = process.argv.includes('--expect-old-failures');
  const browser = await require(playwrightPath).chromium.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
  });
  const results = [];
  try {
    const modes = process.argv.includes('--retry-only') ? [] :
      ['fresh-mobile', 'slow-first-load', 'unavailable-session-storage', 'read-only-storage'];
    for (const mode of modes) {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
      const page = await context.newPage();
      const startupErrors = [];
      page.on('console', message => {
        if (message.text().startsWith('TrustKeyper startup failed:')) {
          startupErrors.push(message.text().replace(/https?:\/\/[^\s]+/g, '[redacted-url]').slice(0, 250));
        }
      });
      if (mode === 'slow-first-load') {
        let delayed = false;
        await page.route('https://www.gstatic.com/firebasejs/**/firebase-app.js', async route => {
          if (!delayed) {
            delayed = true;
            await new Promise(resolve => setTimeout(resolve, 24000));
          }
          if (!page.isClosed()) await route.continue();
        });
      }
      if (mode === 'unavailable-session-storage') {
        await page.addInitScript(() => Object.defineProperty(window, 'sessionStorage', {
          configurable: true,
          get() { throw new DOMException('Browser storage unavailable for test.', 'SecurityError'); },
        }));
      }
      if (mode === 'read-only-storage') {
        await page.addInitScript(() => {
          Storage.prototype.setItem = () => { throw new DOMException('Browser storage is full for test.', 'QuotaExceededError'); };
        });
      }
      await page.goto(`${base}/#/documents/request?token=invalid-test-link`, { waitUntil: 'domcontentloaded' });
      await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 90000 });
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(element => element.click());
      await page.waitForFunction(() => {
        const labels = [document.body.innerText, ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'),
          element => element.getAttribute('aria-label'))].join('\n');
        return labels.includes('TrustKeyper could not start') || labels.includes('Link unavailable');
      }, null, { timeout: 90000 });
      const text = await page.evaluate(() => [document.body.innerText,
        ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'), element => element.getAttribute('aria-label'))].join('\n'));
      const failed = text.includes('TrustKeyper could not start');
      console.log(JSON.stringify({ mode, startupFailed: failed, recipientRouteRendered: !failed, startupErrors }));
      const expectedFailure = before && mode !== 'fresh-mobile';
      assert.equal(failed, expectedFailure, `Unexpected startup outcome in ${mode}.`);
      if (!expectedFailure) assert.ok(text.includes('Link unavailable'));
      await page.screenshot({ path: path.join(__dirname, `../output/ui-audit/build${build}-${before ? 'before' : 'after'}-${mode}.png`), fullPage: true });
      results.push({ mode, startupFailed: failed, recipientRouteRendered: !failed, startupErrors });
      await context.close();
    }
    if (!before) {
      const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
      const page = await context.newPage();
      let blockedOnce = false;
      await page.route('https://www.gstatic.com/firebasejs/**/firebase-app.js', async route => {
        if (!blockedOnce) { blockedOnce = true; await route.abort('connectionfailed'); }
        else await route.continue();
      });
      const fragment = '#/documents/request?token=invalid-test-link';
      await page.goto(`${base}/${fragment}`, { waitUntil: 'domcontentloaded' });
      await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 90000 });
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(element => element.click());
      const retry = page.getByRole('button', { name: 'Try again', exact: true });
      await retry.waitFor({ state: 'visible', timeout: 30000 });
      assert.equal(new URL(page.url()).hash, fragment, 'The failure screen must preserve the document link for browser refresh.');
      await Promise.all([
        page.waitForNavigation({ waitUntil: 'domcontentloaded' }),
        retry.click(),
      ]);
      await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 90000 });
      const reloadedSemantics = page.locator('flt-semantics-placeholder');
      if (await reloadedSemantics.count()) await reloadedSemantics.evaluate(element => element.click());
      await page.waitForFunction(() => [document.body.innerText,
        ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'), element => element.getAttribute('aria-label'))]
        .join('\n').includes('Link unavailable'), null, { timeout: 90000 });
      assert.equal(new URL(page.url()).hash, fragment);
      results.push({ mode: 'retry-after-network-failure', recipientRouteRendered: true, originalLinkPreserved: true });
      await context.close();
    }
    fs.writeFileSync(path.join(__dirname, `../output/ui-audit/build${build}-${before ? 'before' : 'after'}-startup.json`),
      JSON.stringify({ build, base, results }, null, 2));
  } finally { await browser.close(); }
}

main().catch(error => {
  console.error(`Web startup regression failed: ${error.name}: ${error.message.replace(/https?:\/\/[^\s]+/g, '[private-url]').slice(0, 250)}`);
  process.exitCode = 1;
});
