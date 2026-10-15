(() => {
  const version = '12.19.0';
  const startupLocation = window.location.href;
  const modules = [
    ['firebase_auth', 'auth'],
    ['firebase_firestore', 'firestore-pipelines'],
    ['firebase_functions', 'functions'],
    ['firebase_storage', 'storage'],
    ['firebase_messaging', 'messaging'],
    ['firebase_app_check', 'app-check'],
  ];
  let preparation;
  let temporaryStorage = false;
  function protectConfigurationStorage(name) {
    try {
      window[name].getItem('trustkeyper.storage-check');
      const probe = 'trustkeyper.storage-check.' + Date.now() + '.' + Math.random();
      window[name].setItem(probe, '1');
      window[name].removeItem(probe);
      return;
    } catch {}
    const values = new Map();
    const storage = {
      get length() { return values.size; },
      key: index => Array.from(values.keys())[index] ?? null,
      getItem: key => values.get(String(key)) ?? null,
      setItem: (key, value) => { values.set(String(key), String(value)); },
      removeItem: key => { values.delete(String(key)); },
      clear: () => values.clear(),
    };
    Object.defineProperty(window, name, { configurable: true, get: () => storage });
    temporaryStorage = true;
  }
  window.trustkeyperUsesTemporaryStorage = () => temporaryStorage;
  window.trustkeyperReloadStartupPage = () => {
    window.history.replaceState(null, '', startupLocation);
    window.location.reload();
  };
  window.trustkeyperPrepareFirebase = () => {
    preparation ??= (async () => {
      protectConfigurationStorage('localStorage');
      protectConfigurationStorage('sessionStorage');
      const core = await import(`https://www.gstatic.com/firebasejs/${version}/firebase-app.js`);
      const services = await Promise.all(modules.map(async ([name, module]) =>
        [name, await import(`https://www.gstatic.com/firebasejs/${version}/firebase-${module}.js`)]));
      for (const [name, service] of services) window[name] = service;
      window.firebase_core = core;
    })();
    return preparation;
  };
})();
