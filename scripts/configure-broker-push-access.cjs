const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production project required.');
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment login required.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(endpoint, body, method = body ? 'POST' : 'GET', missing = false) {
    const response = await fetch(endpoint, {
      method, headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (missing && response.status === 404) return null;
    const result = await response.json();
    if (!response.ok) throw new Error(`Push configuration failed (${response.status}).`);
    return result;
  }
  const runtime = await request('https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/completeDocumentUpload');
  const member = `serviceAccount:${runtime.serviceConfig.serviceAccountEmail}`;
  const roleName = 'projects/trustkeyper/roles/trustkeyperBrokerPush';
  const iam = 'https://iam.googleapis.com/v1/';
  const apply = process.argv.includes('--apply');
  let role = await request(`${iam}${roleName}`, null, 'GET', true);
  if (!role && apply) {
    role = await request(`${iam}projects/trustkeyper/roles`, {
      roleId: 'trustkeyperBrokerPush', role: {
        title: 'TrustKeyper broker upload push', stage: 'GA', includedPermissions: ['cloudmessaging.messages.create'],
      },
    });
  }
  if (role && (role.deleted || JSON.stringify(role.includedPermissions) !== '["cloudmessaging.messages.create"]')) {
    throw new Error('Unexpected push role permissions; refusing overwrite.');
  }
  const manager = 'https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper';
  const policy = await request(`${manager}:getIamPolicy`, { options: { requestedPolicyVersion: 3 } });
  policy.bindings ??= [];
  const binding = policy.bindings.find(value => value.role === roleName && !value.condition);
  const configured = binding?.members.includes(member);
  if (!configured && apply) {
    if (binding) binding.members.push(member);
    else policy.bindings.push({ role: roleName, members: [member] });
    await request(`${manager}:setIamPolicy`, { policy });
  }
  const service = 'https://serviceusage.googleapis.com/v1/projects/trustkeyper/services/fcm.googleapis.com';
  const api = await request(service);
  if (api.state !== 'ENABLED' && apply) await request(`${service}:enable`, {});
  console.log(JSON.stringify({ project: 'trustkeyper', permission: 'cloudmessaging.messages.create',
    runtimeOnly: true, state: configured ? 'already configured' : apply ? 'configured' : 'would configure',
    messagingApi: api.state === 'ENABLED' ? 'enabled' : apply ? 'enable requested' : 'disabled' }));
}
main().catch(() => { console.error('Broker push service access could not be confirmed; no credentials printed.'); process.exitCode = 1; });
