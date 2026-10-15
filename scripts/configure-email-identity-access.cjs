const assert = require('node:assert/strict');
const path = require('node:path');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  assert.ok(process.argv.includes('--project=trustkeyper'), 'Explicit production project is required.');
  const apply = process.argv.includes('--apply');
  const expectedRuntime = '539073703501-compute@developer.gserviceaccount.com';
  const roleId = 'trustkeyperEmailIdentity';
  const roleName = `projects/trustkeyper/roles/${roleId}`;
  const permissions = ['firebaseauth.users.create', 'firebaseauth.users.get', 'firebaseauth.users.update'];
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  assert.ok(account, 'Business deployment account is required.');
  const credential = await deploymentAuth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body, method = body ? 'POST' : 'GET', allowMissing = false) {
    const response = await fetch(url, { method,
      headers: { Authorization: `Bearer ${credential.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000),
    });
    if (allowMissing && response.status === 404) return null;
    assert.ok(response.ok, `Identity access configuration HTTP ${response.status}`);
    return response.json();
  }
  for (const name of ['requestEmailOtp', 'verifyEmailOtp', 'requestProfileEmailOtp', 'verifyProfileEmailOtp']) {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    assert.equal(metadata.serviceConfig?.serviceAccountEmail, expectedRuntime,
      'Email runtime identity changed; review before modifying IAM.');
  }
  const roleUrl = `https://iam.googleapis.com/v1/${roleName}`;
  let role = await request(roleUrl, undefined, 'GET', true);
  if (!role && apply) {
    role = await request('https://iam.googleapis.com/v1/projects/trustkeyper/roles', {
      roleId, role: { title: 'TrustKeyper email identity', stage: 'GA',
        description: 'Lookup, create and update verified customer identities for email OTP; no account deletion or authentication configuration access.',
        includedPermissions: permissions },
    });
  }
  if (role) {
    assert.notEqual(role.deleted, true, 'Identity role is deleted; manual review is required.');
    assert.deepEqual([...role.includedPermissions].sort(), [...permissions].sort(),
      'Identity role permissions differ from the reviewed allowlist.');
  }
  const policyUrl = 'https://cloudresourcemanager.googleapis.com/v1/projects/trustkeyper';
  let policy = await request(`${policyUrl}:getIamPolicy`, { options: { requestedPolicyVersion: 3 } });
  const member = `serviceAccount:${expectedRuntime}`;
  const assigned = value => value.bindings?.some(binding => binding.role === roleName && !binding.condition && binding.members?.includes(member)) === true;
  if (!assigned(policy) && apply) {
    assert.ok(role, 'Identity role is required before granting access.');
    policy.bindings ??= [];
    const binding = policy.bindings.find(item => item.role === roleName && !item.condition);
    if (binding) binding.members.push(member);
    else policy.bindings.push({ role: roleName, members: [member] });
    await request(`${policyUrl}:setIamPolicy`, { policy });
    policy = await request(`${policyUrl}:getIamPolicy`, { options: { requestedPolicyVersion: 3 } });
    assert.ok(assigned(policy), 'Narrow identity access was not confirmed.');
  }
  process.stdout.write(`${JSON.stringify({ runtime: expectedRuntime, role: roleName,
    permissions, assigned: assigned(policy), applied: apply,
    accountDeletionPermission: false, authenticationConfigurationPermission: false })}\n`);
}

main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
