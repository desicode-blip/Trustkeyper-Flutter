const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project required.');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment login unavailable.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body) {
    const response = await fetch(url, { method: body ? 'PUT' : 'GET',
      headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw new Error(`Inspection service access rejected (${response.status}).`);
    return response.json();
  }
  const serviceAccount = '539073703501-compute@developer.gserviceaccount.com';
  for (const name of ['beginPropertyInspection', 'submitPropertyInspection', 'readPropertyInspectionPhoto']) {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    if (metadata.state !== 'ACTIVE' || metadata.serviceConfig?.serviceAccountEmail !== serviceAccount) {
      throw new Error('Inspection runtime identity did not match the expected deployed service.');
    }
  }
  const url = 'https://storage.googleapis.com/storage/v1/b/trustkeyper.firebasestorage.app/iam';
  const policy = await request(`${url}?optionsRequestedPolicyVersion=3`);
  const member = `serviceAccount:${serviceAccount}`;
  const prefix = 'projects/_/buckets/trustkeyper.firebasestorage.app/objects/';
  const expression = `resource.name.startsWith("${prefix}inspectionUploads/") || resource.name.startsWith("${prefix}inspectionPhotos/")`;
  policy.bindings ??= [];
  const configured = policy.bindings.some(binding => binding.role === 'roles/storage.objectUser' &&
    binding.members.includes(member) && (!binding.condition || binding.condition.expression === expression));
  if (!configured && process.argv.includes('--apply')) {
    policy.version = 3;
    policy.bindings.push({ role: 'roles/storage.objectUser', members: [member],
      condition: { title: 'private-inspection-objects-only', expression } });
    await request(url, policy);
  }
  process.stdout.write(JSON.stringify({ resource: 'inspectionUploads/ and inspectionPhotos/ objects only',
    state: configured ? 'already configured' : process.argv.includes('--apply') ? 'configured' : 'would configure' }) + '\n');
}
main().catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
