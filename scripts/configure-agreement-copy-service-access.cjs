const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project required.');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment login unavailable.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  async function request(url, body) {
    const response = await fetch(url, { method: body ? 'PUT' : 'GET',
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    if (!response.ok) throw new Error(`Agreement copy service access rejected (${response.status}).`);
    return response.json();
  }
  const serviceAccount = '539073703501-compute@developer.gserviceaccount.com';
  for (const name of ['beginAgreementCopyUpload', 'completeAgreementCopyUpload', 'readAgreementCopy']) {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    if (metadata.state !== 'ACTIVE' || metadata.serviceConfig?.serviceAccountEmail !== serviceAccount) {
      throw new Error('Agreement runtime identity did not match the expected service.');
    }
  }
  const url = 'https://storage.googleapis.com/storage/v1/b/trustkeyper.firebasestorage.app/iam';
  const policy = await request(`${url}?optionsRequestedPolicyVersion=3`);
  const member = `serviceAccount:${serviceAccount}`;
  const prefix = 'projects/_/buckets/trustkeyper.firebasestorage.app/objects/';
  const expression = `resource.name.startsWith("${prefix}agreementCopyUploads/") || resource.name.startsWith("${prefix}agreementCopies/")`;
  policy.bindings ??= [];
  const configured = policy.bindings.some(binding => binding.role === 'roles/storage.objectUser' &&
    binding.members.includes(member) && (!binding.condition || binding.condition.expression === expression));
  if (!configured && process.argv.includes('--apply')) {
    policy.version = 3;
    policy.bindings.push({ role: 'roles/storage.objectUser', members: [member],
      condition: { title: 'private-agreement-copy-objects-only', expression } });
    await request(url, policy);
  }
  process.stdout.write(JSON.stringify({ resource: 'agreementCopyUploads/ and agreementCopies/ objects only', role: 'roles/storage.objectUser',
    state: configured ? 'already configured' : process.argv.includes('--apply') ? 'configured' : 'would configure' }) + '\n');
}
main().catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
