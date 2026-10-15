const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project required.');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  const url = 'https://storage.googleapis.com/storage/v1/b/trustkeyper.firebasestorage.app/iam';
  async function request(endpoint, body, method = body ? 'PUT' : 'GET') {
    const response = await fetch(endpoint, { method,
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const result = await response.json();
    if (!response.ok) throw new Error(`Private upload service access failed: ${response.status} ${result.error?.status}`);
    return result;
  }
  const policy = await request(`${url}?optionsRequestedPolicyVersion=3`);
  const member = 'serviceAccount:539073703501-compute@developer.gserviceaccount.com';
  const expression = 'resource.name.startsWith("projects/_/buckets/trustkeyper.firebasestorage.app/objects/brokerDocumentRequests/")';
  policy.bindings ??= [];
  const existing = policy.bindings.some(binding => binding.role === 'roles/storage.objectUser' &&
    binding.members.includes(member) && (!binding.condition || binding.condition.expression === expression));
  if (!existing && process.argv.includes('--apply')) {
    policy.version = 3;
    policy.bindings.push({ role: 'roles/storage.objectUser', members: [member],
      condition: { title: 'document-request-snapshots-only', expression } });
    await request(url, policy);
  }
  process.stdout.write(JSON.stringify({ resource: 'private document request objects only', role: 'roles/storage.objectUser',
    state: existing ? 'already configured' : process.argv.includes('--apply') ? 'configured' : 'would configure' }) + '\n');
  const manager = 'https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper';
  const projectPolicy = await request(`${manager}:getIamPolicy`, { options: { requestedPolicyVersion: 3 } }, 'POST');
  const storageAgent = 'serviceAccount:service-539073703501@gcp-sa-firebasestorage.iam.gserviceaccount.com';
  const role = 'roles/firebaserules.firestoreServiceAgent';
  projectPolicy.bindings ??= [];
  const crossService = projectPolicy.bindings.find(binding => binding.role === role && !binding.condition);
  const configured = crossService?.members.includes(storageAgent);
  if (!configured && process.argv.includes('--apply')) {
    if (crossService) crossService.members.push(storageAgent);
    else projectPolicy.bindings.push({ role, members: [storageAgent] });
    await request(`${manager}:setIamPolicy`, { policy: projectPolicy }, 'POST');
  }
  process.stdout.write(JSON.stringify({ resource: 'Firebase Storage service agent cross-service rule reads', role,
    state: configured ? 'already configured' : process.argv.includes('--apply') ? 'configured' : 'would configure' }) + '\n');
}
main().catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
