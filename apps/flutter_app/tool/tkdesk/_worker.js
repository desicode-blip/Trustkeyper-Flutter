// TrustKeyper desk: team storage on Cloudflare Pages (advanced-mode worker).
// - GET  /api/leads?since=<ms>  → leads saved after that time (all if 0).
// - POST /api/leads {leads:[...], by} → saves each lead unless the stored one
//   is newer, and appends every save to the log table (never changed, never
//   deleted), so nothing typed is ever lost.
// - Needs the team password in the x-tk-pass header (checked against its
//   SHA-256 below; _worker.js is never served to browsers) and a D1 database
//   bound as DB. Every other path serves the app.
//   To change the password: put the new password's SHA-256 in TEAM_PASS_SHA256
//   (or set it as the secret TEAM_PASS_SHA256 in the Pages settings).
const TEAM_PASS_SHA256 = '__HASH__';
let ready = false;

async function sha256(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
async function setup(db) {
  if (ready) return;
  await db.exec(
    'CREATE TABLE IF NOT EXISTS leads (id TEXT PRIMARY KEY, changed INTEGER, saved INTEGER, data TEXT);' +
      'CREATE INDEX IF NOT EXISTS leads_saved ON leads(saved);' +
      'CREATE TABLE IF NOT EXISTS log (saved INTEGER, id TEXT, who TEXT, data TEXT);',
  );
  ready = true;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    const json = (body, status = 200) =>
      new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
    if (!env.DB) return json({ error: 'storage not set up' }, 503);
    const want = env.TEAM_PASS_SHA256 || TEAM_PASS_SHA256;
    if ((await sha256((request.headers.get('x-tk-pass') || '').trim())) !== want) return json({ error: 'wrong password' }, 401);
    if (url.pathname !== '/api/leads') return json({ error: 'not found' }, 404);
    await setup(env.DB);
    const now = Date.now();

    if (request.method === 'GET') {
      const since = Number(url.searchParams.get('since') || 0);
      const { results } = await env.DB.prepare('SELECT data FROM leads WHERE saved > ?1').bind(since).all();
      return json({ leads: results.map((r) => JSON.parse(r.data)), at: now });
    }
    if (request.method !== 'POST') return json({ error: 'method' }, 405);

    const body = await request.json();
    const who = String(body.by || '');
    const stmts = [];
    for (const l of body.leads || []) {
      if (!l || !l.id) continue;
      const data = JSON.stringify(l);
      stmts.push(
        env.DB.prepare(
          'INSERT INTO leads (id, changed, saved, data) VALUES (?1, ?2, ?3, ?4) ' +
            'ON CONFLICT(id) DO UPDATE SET changed = excluded.changed, saved = excluded.saved, data = excluded.data WHERE excluded.changed >= leads.changed',
        ).bind(l.id, Number(l.changed || 0), now, data),
        env.DB.prepare('INSERT INTO log (saved, id, who, data) VALUES (?1, ?2, ?3, ?4)').bind(now, l.id, who, data),
      );
    }
    if (stmts.length) await env.DB.batch(stmts);
    return json({ saved: stmts.length / 2, at: now });
  },
};
