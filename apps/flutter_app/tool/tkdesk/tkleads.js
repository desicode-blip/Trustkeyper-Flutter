// TrustKeyper desk: opens the team's published lead batches (leads/…).
// Lead files are encrypted, so names and phone numbers are never public.
// Group reading only needs the public key to add a batch; the desk unlocks the
// private key with the team password. Same format as tools/tkm_crypto.py.
(function () {
  const td = new TextDecoder();
  const te = new TextEncoder();
  const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const get = async (p) => (await fetch(p + '?' + Date.now(), { cache: 'no-store' })).json();

  window.tkLeadBatches = async function () {
    try {
      const idx = await get('leads/index.json');
      return idx.batches.map((b) => b.file).join(',');
    } catch (e) {
      return '';
    }
  };

  window.tkLoadLeads = async function (pass, skip) {
    try {
      const keys = await get('leads/keys.json');
      const base = await crypto.subtle.importKey('raw', te.encode(pass.trim()), 'PBKDF2', false, ['deriveKey']);
      const aes = await crypto.subtle.deriveKey(
        { name: 'PBKDF2', hash: 'SHA-256', salt: fromB64(keys.salt), iterations: keys.iter },
        base,
        { name: 'AES-GCM', length: 256 },
        false,
        ['decrypt'],
      );
      const pkcs8 = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromB64(keys.iv) }, aes, fromB64(keys.wrapped));
      const priv = await crypto.subtle.importKey('pkcs8', pkcs8, { name: 'RSA-OAEP', hash: 'SHA-256' }, false, ['decrypt']);
      const done = new Set((skip || '').split(',').filter(Boolean));
      const idx = await get('leads/index.json');
      const out = { format: 'tk-leads-1', tenants: [], homes: [] };
      const files = [];
      for (const b of idx.batches) {
        if (done.has(b.file)) continue;
        const batch = await get('leads/batches/' + b.file);
        const raw = await crypto.subtle.decrypt({ name: 'RSA-OAEP' }, priv, fromB64(batch.key));
        const k = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt']);
        const data = JSON.parse(td.decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromB64(batch.iv) }, k, fromB64(batch.data))));
        out.tenants.push(...(data.tenants || []));
        out.homes.push(...(data.homes || []));
        files.push(b.file);
      }
      return JSON.stringify({ files, data: out });
    } catch (e) {
      return null;
    }
  };
})();
