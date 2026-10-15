const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function scenario(href, controlled = true) {
  const events = {};
  const title = {};
  const message = {};
  const retry = { style: {} };
  const calls = { reloads: [], loader: 0, unregistered: 0, cachesRemoved: 0, removedRoot: 0, timersCleared: 0 };
  let timer;
  const window = {
    location: { href, replace: value => calls.reloads.push(value) },
    addEventListener: (event, handler) => { events[event] = handler; },
    setTimeout: callback => { timer = callback; return 1; },
    clearTimeout: () => calls.timersCleared++,
    caches: { keys: async () => ['flutter-app-cache'], delete: async () => calls.cachesRemoved++ },
  };
  Object.defineProperty(window, 'sessionStorage', { get() { throw new Error('Storage unavailable.'); } });
  const context = vm.createContext({ window, URL, console: { warn() {}, error() {} },
    navigator: { serviceWorker: { controller: controlled ? {} : null,
      getRegistrations: async () => [{ unregister: async () => calls.unregistered++ }] } },
    document: {
      getElementById: name => ({
        'trustkeyper-bootstrap': { remove: () => calls.removedRoot++ },
        'trustkeyper-bootstrap-title': title, 'trustkeyper-bootstrap-message': message, 'trustkeyper-bootstrap-retry': retry,
      })[name],
      querySelector: () => ({ remove() {} }),
    },
    _flutter: { loader: { load: async () => { calls.loader++; } } },
  });
  const source = fs.readFileSync(path.join(__dirname, '../apps/flutter_app/web/flutter_bootstrap.js'), 'utf8')
    .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
  vm.runInContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  return { calls, title, message, retry, events, timer };
}

(async () => {
  const fragment = '#/documents/request?token=TEST-NOT-A-REAL-LINK';
  const original = `https://trustkeyper.web.app/${fragment}`;
  let reloads = 0;
  const retryWindow = {
    location: { href: original, reload: () => reloads++ },
    history: { replaceState: (state, title, url) => { retryWindow.location.href = url; } },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../apps/flutter_app/web/firebase-startup.js'), 'utf8'),
    { window: retryWindow });
  retryWindow.location.href = 'https://trustkeyper.web.app/#/';
  retryWindow.trustkeyperReloadStartupPage();
  assert.equal(retryWindow.location.href, original);
  assert.equal(reloads, 1);
  const first = await scenario(`https://trustkeyper.web.app/${fragment}`);
  assert.equal(first.calls.reloads.length, 1);
  assert.equal(new URL(first.calls.reloads[0]).hash, fragment);
  assert.equal(new URL(first.calls.reloads[0]).searchParams.get('_tk_cache_reset'), '1');
  assert.equal(first.calls.loader, 0);
  const second = await scenario(first.calls.reloads[0]);
  assert.equal(second.calls.reloads.length, 0);
  assert.equal(second.calls.loader, 1);
  second.timer();
  assert.equal(second.title.textContent, 'Opening TrustKeyper');
  assert.ok(second.message.textContent.includes('slow connection'));
  assert.equal(second.retry.style.display, 'inline-block');
  second.events['flutter-first-frame']();
  assert.equal(second.calls.timersCleared, 1);
  assert.equal(second.calls.removedRoot, 1);
  const fresh = await scenario(`https://trustkeyper.web.app/${fragment}`, false);
  assert.equal(fresh.calls.loader, 1);
  assert.equal(fresh.calls.reloads.length, 0);
  console.log('PASS: cache recovery and failure-page retry preserve the upload link; slow loading is not treated as fatal.');
})().catch(() => { console.error('Web bootstrap regression failed.'); process.exitCode = 1; });
