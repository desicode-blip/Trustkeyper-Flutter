const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  async function read(url, body) {
    const response = await fetch(url, { method: body ? 'POST' : 'GET',
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const result = await response.json();
    if (!response.ok) throw new Error(`Inspection failed: ${response.status} ${result.error?.status}`);
    return result;
  }
  const build = await read('https://cloudbuild.googleapis.com/v1/projects/trustkeyper/locations/asia-south1/builds/6185cef9-c932-47b5-9f14-f42530724a4b');
  process.stdout.write(`${JSON.stringify({ status: build.status, serviceAccount: build.serviceAccount,
    failure: build.failureInfo, steps: (build.steps ?? []).map(step => ({ id: step.id, status: step.status })) })}\n`);
  const policy = await read('https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper:getIamPolicy', {});
  const member = `serviceAccount:${build.serviceAccount?.split('/').pop()}`;
  process.stdout.write(`${JSON.stringify({ buildRoles: (policy.bindings ?? [])
    .filter(binding => binding.members?.includes(member)).map(binding => binding.role) })}\n`);
  const logs = await read('https://logging.googleapis.com/v2/entries:list', {
    resourceNames: ['projects/trustkeyper'],
    filter: 'resource.type="build" AND resource.labels.build_id="6185cef9-c932-47b5-9f14-f42530724a4b"',
    orderBy: 'timestamp desc', pageSize: 15,
  });
  process.stdout.write(`${JSON.stringify({ errors: (logs.entries ?? []).map(entry => entry.textPayload)
    .filter(entry => entry && /denied|permission|failed|error/i.test(entry)) })}\n`);
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
