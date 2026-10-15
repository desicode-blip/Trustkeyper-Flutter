const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (process.argv[2] !== '--project=trustkeyper') throw new Error('Specify the approved TrustKeyper project explicitly.');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Deployment account unavailable.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, [...account.tokens.scopes]);
  const headers = { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' };
  const billingResponse = await fetch('https://cloudbilling.googleapis.com/v1/projects/trustkeyper/billingInfo', { headers });
  if (!billingResponse.ok || (await billingResponse.json()).billingEnabled !== true) throw new Error('Existing billing must be enabled; this script does not change billing.');
  const url = 'https://firebasestorage.googleapis.com/v1alpha/projects/trustkeyper/defaultBucket';
  const existing = await fetch(url, { headers });
  if (existing.ok) {
    const bucket = await existing.json();
    process.stdout.write(`${JSON.stringify({ status: 'already-provisioned', location: bucket.location, bucket: bucket.bucket?.name })}\n`);
    return;
  }
  if (existing.status !== 404) throw new Error('Cannot verify the default bucket; no changes attempted.');
  const response = await fetch(url, { method: 'POST', headers, body: JSON.stringify({ location: 'asia-south1' }) });
  const body = await response.json();
  if (!response.ok) {
    process.stdout.write(`${JSON.stringify({ status: 'not-provisioned', httpStatus: response.status, reason: body.error?.status })}\n`);
    process.exitCode = 1;
    return;
  }
  process.stdout.write(`${JSON.stringify({ status: 'provisioned', location: body.location, bucket: body.bucket?.name })}\n`);
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
