const path = require('node:path');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
const names = ['beginOwnerContractUpload', 'completeOwnerContractUpload', 'readOwnerContract', 'changeOwnerPropertyLifecycle', 'readPublicOwnerListing', 'enquireOwnerListing'];
async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production target required.');
  const apply = process.argv.includes('--apply');
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment login required.');
  const credential = await deploymentAuth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body, method = body ? 'PUT' : 'GET') {
    const response = await fetch(url, { method, headers: { Authorization: `Bearer ${credential.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`Build 31 runtime configuration HTTP ${response.status}`);
    return response.json();
  }
  const expected = '539073703501-compute@developer.gserviceaccount.com';
  for (const name of names) {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    if (metadata.state !== 'ACTIVE' || metadata.serviceConfig?.serviceAccountEmail !== expected) throw new Error(`Runtime identity not accepted: ${name}`);
  }
  const url = 'https://storage.googleapis.com/storage/v1/b/trustkeyper.firebasestorage.app/iam';
  const policy = await request(`${url}?optionsRequestedPolicyVersion=3`);
  const prefixes = ['ownerContractUploads/', 'ownerContractFiles/'];
  const expression = prefixes.map(prefix => `resource.name.startsWith("projects/_/buckets/trustkeyper.firebasestorage.app/objects/${prefix}")`).join(' || ');
  policy.bindings ??= [];
  const member = `serviceAccount:${expected}`;
  const exists = policy.bindings.some(binding => binding.role === 'roles/storage.objectUser' && binding.members.includes(member) && binding.condition?.expression === expression);
  if (!exists && apply) {
    policy.version = 3; policy.bindings.push({ role: 'roles/storage.objectUser', members: [member], condition: { title: 'private-owner-contract-objects-only', expression } });
    await request(url, policy);
  }
  process.stdout.write(`${JSON.stringify({ privateObjectPrefixes: prefixes, storageAccess: exists ? 'already configured' : apply ? 'configured' : 'not configured' })}\n`);
  for (const name of names) {
    const serviceName = `projects/trustkeyper/locations/asia-south1/services/${name.toLowerCase()}`;
    const resource = `https://run.googleapis.com/v2/${serviceName}`;
    const current = await request(resource); const containers = current.template?.containers;
    if (containers?.length !== 1 || containers[0].resources?.limits?.cpu !== '0.3333' || containers[0].resources?.limits?.memory !== '512Mi' ||
      current.template.maxInstanceRequestConcurrency !== 1 || current.template.scaling?.maxInstanceCount !== 3) throw new Error(`Unreviewed runtime limits: ${name}`);
    if (apply && (containers[0].resources.startupCpuBoost === true || current.invokerIamDisabled !== true || current.terminalCondition?.state !== 'CONDITION_SUCCEEDED')) {
      containers[0].resources.startupCpuBoost = false;
      let operation = await request(`${resource}?updateMask=invokerIamDisabled,template.containers,template.revision`, { name: serviceName, etag: current.etag,
        invokerIamDisabled: true, template: { containers, revision: `${name.toLowerCase()}-b31-${Date.now().toString(36)}` } }, 'PATCH');
      for (let attempt = 0; !operation.done && attempt < 90; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 2000)); operation = await request(`https://run.googleapis.com/v2/${operation.name}`);
      }
      if (!operation.done || operation.error) throw new Error(`Runtime revision failed: ${name}`);
    }
    const verified = await request(resource);
    const ready = verified.terminalCondition?.state === 'CONDITION_SUCCEEDED' && verified.invokerIamDisabled === true && verified.template.containers[0].resources.startupCpuBoost !== true;
    if (apply && !ready) throw new Error(`Callable transport not accepted: ${name}`);
    process.stdout.write(`${JSON.stringify({ name, ready, cpu: '0.3333', memory: '512Mi', concurrency: 1, maxInstances: 3, appAuthorizationRequired: name !== 'readPublicOwnerListing' })}\n`);
  }
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
