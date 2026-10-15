const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project is required.');
  const apply = process.argv.includes('--apply');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  const serviceAccount = '539073703501-compute@developer.gserviceaccount.com';
  const member = `serviceAccount:${serviceAccount}`;
  async function request(url, method = 'GET', body) {
    const response = await fetch(url, { method,
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const result = await response.json();
    if (!response.ok) throw new Error(`Service configuration failed: ${response.status} ${result.error?.status}`);
    return result;
  }
  const build = await request('https://cloudbuild.googleapis.com/v1/projects/trustkeyper/locations/asia-south1/builds/6185cef9-c932-47b5-9f14-f42530724a4b');
  if (build.serviceAccount?.split('/').pop() !== serviceAccount || build.status !== 'FAILURE') {
    throw new Error('Failed build identity did not match the inspected service account.');
  }
  const grants = [
    { resource: 'project logging and review database', roles: ['roles/logging.logWriter', 'roles/datastore.user'],
      get: 'https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper:getIamPolicy', getMethod: 'POST',
      set: 'https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper:setIamPolicy', setMethod: 'POST', wrapper: true },
    { resource: 'function build source bucket', roles: ['roles/storage.objectViewer'],
      get: 'https://storage.googleapis.com/storage/v1/b/gcf-v2-sources-539073703501-asia-south1/iam',
      set: 'https://storage.googleapis.com/storage/v1/b/gcf-v2-sources-539073703501-asia-south1/iam', setMethod: 'PUT' },
    { resource: 'function container repository', roles: ['roles/artifactregistry.writer'],
      get: 'https://artifactregistry.googleapis.com/v1/projects/trustkeyper/locations/asia-south1/repositories/gcf-artifacts:getIamPolicy',
      set: 'https://artifactregistry.googleapis.com/v1/projects/trustkeyper/locations/asia-south1/repositories/gcf-artifacts:setIamPolicy', setMethod: 'POST', wrapper: true },
  ];
  for (const grant of grants) {
    const policy = await request(grant.get, grant.getMethod, grant.getMethod ? { options: { requestedPolicyVersion: 3 } } : undefined);
    policy.bindings ??= [];
    let changed = false;
    for (const role of grant.roles) {
      let binding = policy.bindings.find(entry => entry.role === role && !entry.condition);
      if (!binding) {
        binding = { role, members: [] };
        policy.bindings.push(binding);
      }
      if (!binding.members.includes(member)) {
        binding.members.push(member);
        changed = true;
      }
    }
    if (apply && changed) await request(grant.set, grant.setMethod, grant.wrapper ? { policy } : policy);
    process.stdout.write(`${JSON.stringify({ resource: grant.resource, roles: grant.roles,
      state: changed ? (apply ? 'added' : 'would add') : 'already configured' })}\n`);
  }
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
