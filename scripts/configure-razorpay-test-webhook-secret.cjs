const path = require('node:path');
const { randomBytes } = require('node:crypto');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper') || !process.argv.includes('--apply')) {
    throw new Error('Explicit project and apply arguments are required.');
  }
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment login unavailable.');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body) {
    const response = await fetch(url, { method: body ? 'POST' : 'GET',
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000) });
    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Secret setup returned HTTP ${response.status}: ${error.error?.status ?? 'unknown'} ${error.error?.message ?? ''}`);
    }
    return response.json();
  }
  const base = 'https://secretmanager.googleapis.com/v1/projects/trustkeyper/secrets';
  const name = 'RAZORPAY_TEST_WEBHOOK_SECRET';
  const current = await request(base);
  if (!(current.secrets ?? []).some(secret => secret.name.endsWith(`/secrets/${name}`))) {
    await request(`${base}?secretId=${name}`, { replication: { automatic: {} } });
  }
  const versions = await request(`${base}/${name}/versions`);
  if (!(versions.versions ?? []).some(version => version.state === 'ENABLED')) {
    await request(`${base}/${name}:addVersion`, { payload: { data: Buffer.from(randomBytes(32).toString('hex')).toString('base64') } });
  }
  process.stdout.write('PASS: dedicated test webhook secret ready in Secret Manager; no value printed or old credential replaced.\n');
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
