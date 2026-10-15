{{flutter_js}}
{{flutter_build_config}}

const bootstrapRoot = document.getElementById('trustkeyper-bootstrap');
const bootstrapTitle = document.getElementById('trustkeyper-bootstrap-title');
const bootstrapMessage = document.getElementById('trustkeyper-bootstrap-message');
const bootstrapRetry = document.getElementById('trustkeyper-bootstrap-retry');
const cacheResetKey = 'trustkeyper-web-cache-reset-v1';

function updateBootstrap(title, message) {
  if (bootstrapTitle) bootstrapTitle.textContent = title;
  if (bootstrapMessage) bootstrapMessage.textContent = message;
}

function showBootstrapFailure() {
  updateBootstrap(
    'TrustKeyper could not start',
    'Check your connection, then try again. The page will no longer fail silently.'
  );
  document.querySelector('.trustkeyper-bootstrap-spinner')?.remove();
  if (bootstrapRetry) bootstrapRetry.style.display = 'inline-block';
}

window.addEventListener('flutter-first-frame', () => {
  window.clearTimeout(startupTimeout);
  bootstrapRoot?.remove();
});
window.addEventListener('error', showBootstrapFailure);
window.addEventListener('unhandledrejection', showBootstrapFailure);

const startupTimeout = window.setTimeout(() => {
  updateBootstrap(
    'Opening TrustKeyper',
    'The first visit can take longer on a slow connection. Keep this page open, or try again.'
  );
  if (bootstrapRetry) bootstrapRetry.style.display = 'inline-block';
}, 30000);

async function removeLegacyOfflineCache() {
  const hadController = Boolean(navigator.serviceWorker?.controller);
  const registrations = 'serviceWorker' in navigator
    ? await navigator.serviceWorker.getRegistrations()
    : [];

  await Promise.all(registrations.map((registration) => registration.unregister()));

  if ('caches' in window) {
    const cacheNames = await window.caches.keys();
    await Promise.all(cacheNames.map((cacheName) => window.caches.delete(cacheName)));
  }

  if (hadController) {
    const refreshed = new URL(window.location.href);
    let alreadyReset = refreshed.searchParams.get('_tk_cache_reset') === '1';
    try {
      alreadyReset ||= Boolean(window.sessionStorage.getItem(cacheResetKey));
      window.sessionStorage.setItem(cacheResetKey, 'done');
    } catch {}
    if (!alreadyReset) {
      refreshed.searchParams.set('_tk_cache_reset', '1');
      window.location.replace(refreshed.href);
      return true;
    }
  }

  return false;
}

async function startTrustKeyper() {
  try {
    updateBootstrap('Opening TrustKeyper', 'Checking the latest secure version…');
    if (await removeLegacyOfflineCache()) return;
  } catch (error) {
    console.warn('Could not remove the legacy offline cache', error);
  }

  _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        updateBootstrap('Opening TrustKeyper', 'Preparing your secure workspace…');
        const appRunner = await engineInitializer.initializeEngine();
        updateBootstrap('Opening TrustKeyper', 'Starting the application…');
        await appRunner.runApp();
        window.clearTimeout(startupTimeout);
      } catch (error) {
        console.error('TrustKeyper web startup failed', error);
        showBootstrapFailure();
      }
    }
  }).catch((error) => {
    console.error('TrustKeyper loader failed', error);
    showBootstrapFailure();
  });
}

startTrustKeyper();
