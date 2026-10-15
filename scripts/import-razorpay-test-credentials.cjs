const path = require('node:path');
const { spawnSync } = require('node:child_process');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

const extract = String.raw`
import json,re,sys
from pypdf import PdfReader
pairs=set()
for filename in sys.argv[1:]:
    for page in PdfReader(filename).pages:
        for line in (page.extract_text() or '').splitlines():
            identifiers=re.findall(r'(?<![A-Za-z0-9_])rzp_test_[A-Za-z0-9]+(?![A-Za-z0-9_])',line)
            if identifiers and re.search(r'(?i)key\s+secret',line):
                secrets=re.findall(r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{24}(?![A-Za-z0-9_-])',line)
                if len(identifiers)==1 and len(secrets)==1:
                    pairs.add((identifiers[0],secrets[0]))
if len(pairs)!=1:
    sys.exit(2)
identifier,secret=next(iter(pairs))
sys.stdout.write(json.dumps({'keyId':identifier,'keySecret':secret}))
`;

function loadCredentials(python, pdfs) {
  if (!python || pdfs.length === 0) throw new Error('Explicit Python runtime and private source PDFs are required.');
  const extraction = spawnSync(python, ['-c', extract, ...pdfs], { encoding: 'utf8', windowsHide: true, timeout: 30000 });
  if (extraction.status !== 0) throw new Error('Could not identify exactly one labelled test-mode credential pair; nothing was saved.');
  let credentials;
  try { credentials = JSON.parse(extraction.stdout); } catch { throw new Error('Private extraction failed; nothing was saved.'); }
  if (!/^rzp_test_[A-Za-z0-9]+$/.test(credentials.keyId) || !/^[A-Za-z0-9_-]{24}$/.test(credentials.keySecret)) {
    throw new Error('Only an unambiguous test-mode credential pair is permitted.');
  }
  return credentials;
}

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit Firebase project is required.');
  const apply = process.argv.includes('--apply');
  const credentials = loadCredentials(process.argv.find(argument => argument.startsWith('--python='))?.slice('--python='.length),
    process.argv.filter(argument => argument.startsWith('--pdf=')).map(argument => argument.slice('--pdf='.length)));
  const providerResponse = await fetch('https://api.razorpay.com/v1/orders?count=1', {
    headers: { Authorization: `Basic ${Buffer.from(`${credentials.keyId}:${credentials.keySecret}`).toString('base64')}` },
    signal: AbortSignal.timeout(20000),
  });
  if (!providerResponse.ok) throw new Error(`Razorpay read-only credential validation returned HTTP ${providerResponse.status}; nothing was saved.`);
  const providerResult = await providerResponse.json();
  if (providerResult.entity !== 'collection' || !Array.isArray(providerResult.items)) {
    throw new Error('Razorpay validation returned an unexpected response; nothing was saved.');
  }
  process.stdout.write('PASS: Razorpay test credentials authenticate; no order or payment was created.\n');
  if (!apply) return;
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('The business Firebase deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  const base = 'https://secretmanager.googleapis.com/v1/projects/trustkeyper/secrets';
  async function request(url, body, method = body ? 'POST' : 'GET') {
    const response = await fetch(url, {
      method, headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) throw new Error(`Secret Manager request failed with HTTP ${response.status}; no credential data is logged.`);
    return response.json();
  }
  const destinations = [
    ['RAZORPAY_TEST_KEY_ID', credentials.keyId],
    ['RAZORPAY_TEST_KEY_SECRET', credentials.keySecret],
  ];
  const current = await request(base);
  for (const [name, value] of destinations) {
    const exists = (current.secrets ?? []).some(secret => secret.name.endsWith(`/secrets/${name}`));
    if (exists) {
      const versions = await request(`${base}/${name}/versions`);
      const enabled = (versions.versions ?? []).filter(version => version.state === 'ENABLED');
      if (enabled.length > 0) {
        const saved = await request(`https://secretmanager.googleapis.com/v1/${enabled[0].name}:access`);
        if (Buffer.from(saved.payload.data, 'base64').toString('utf8') !== value) {
          throw new Error('A different enabled test credential already exists; replacement was not attempted.');
        }
      }
    }
  }
  for (const [name, value] of destinations) {
    const exists = (current.secrets ?? []).some(secret => secret.name.endsWith(`/secrets/${name}`));
    if (!exists) await request(`${base}?secretId=${name}`, { replication: { automatic: {} } });
    const versions = await request(`${base}/${name}/versions`);
    if (!(versions.versions ?? []).some(version => version.state === 'ENABLED')) {
      await request(`${base}/${name}:addVersion`, { payload: { data: Buffer.from(value).toString('base64') } });
    }
    const saved = await request(`${base}/${name}/versions/latest:access`);
    if (Buffer.from(saved.payload.data, 'base64').toString('utf8') !== value) throw new Error('Secret verification failed.');
    process.stdout.write(`PASS: ${name} saved and privately verified in Firebase Secret Manager.\n`);
  }
  process.stdout.write('Live-mode credentials were not imported. App/payment implementation is a separate step.\n');
}

module.exports = { loadCredentials };
if (require.main === module) main().catch(() => {
  process.stderr.write('Credential import did not complete. No keys or private PDF contents were logged; check extraction, provider access and Firebase permissions.\n');
  process.exitCode = 1;
});
