const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const playwrightPath = process.argv.find(argument => argument.startsWith('--playwright='))?.slice(13);
  assert.ok(playwrightPath);
  const build = process.argv.find(argument => argument.startsWith('--build='))?.slice(8) ?? '23';
  assert.ok(/^\d+$/.test(build));
  const playwright = require(playwrightPath);
  const browser = await playwright.chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  try {
    const results = [];
    const routes = [
      ['/login', 'Log in or sign up'],
      ['/admin/login', 'Work email'],
      ['/documents/request?token=invalid-test-link', 'Link unavailable'],
      ['/switch-role', 'Sign in again to choose your role.'],
    ];
    if (Number(build) >= 27) routes.push(['/owner/support', 'Your login changed. Reopen this page.']);
    for (const [route, expected] of routes) {
      const page = await browser.newPage({ viewport: { width: 440, height: 920 } });
      const errors = [];
      page.on('pageerror', error => errors.push(error.name));
      const response = await page.goto(`https://trustkeyper.web.app/#${route}`, { waitUntil: 'domcontentloaded' });
      assert.equal(response.status(), 200);
      await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 60000 });
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(element => element.click());
      await page.locator('flt-semantics').first().waitFor({ state: 'attached', timeout: 30000 });
      await page.waitForFunction(expected => [document.body.innerText, ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'), element => element.getAttribute('aria-label'))].join('\n').includes(expected), expected, { timeout: 30000 });
      const text = await page.evaluate(() => [document.body.innerText, ...Array.from(document.querySelectorAll('flt-semantics[aria-label]'), element => element.getAttribute('aria-label'))].join('\n'));
      assert.ok(text.includes(expected));
      assert.equal(new URL(page.url()).hash, `#${route}`);
      assert.deepEqual(errors, []);
      await page.waitForLoadState('networkidle', { timeout: 20000 });
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const name = route.startsWith('/admin') ? 'admin-login' : route.startsWith('/documents') ? 'recipient-invalid-link' : route === '/switch-role' ? 'role-auth-gate' : route === '/owner/support' ? 'manager-auth-gate' : 'login';
      await page.screenshot({ path: path.join(__dirname, `../output/ui-audit/build${build}-web-${name}.png`), fullPage: true });
      results.push({ route, httpStatus: response.status(), rendered: true, javascriptErrors: errors.length });
      process.stdout.write(`PASS: hosted ${name} renders without JavaScript errors in a fresh anonymous context.\n`);
      await page.close();
    }
    fs.writeFileSync(path.join(__dirname, `../output/ui-audit/build${build}-web-runtime.json`), JSON.stringify(results, null, 2));
  } finally {
    await browser.close();
  }
}

main().catch(error => { process.stderr.write(`Hosted web smoke check failed: ${error.name}.\n`); process.exitCode = 1; });
