const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  for (const name of ['requestAgreementReview', 'recordAgreementReview']) {
    const resource = `projects/trustkeyper/locations/asia-south1/functions/${name}`;
    const response = await fetch(`https://cloudfunctions.googleapis.com/v2/${resource}`, {
      headers: { Authorization: `Bearer ${token.access_token}` },
    });
    if (!response.ok) throw new Error(`Function metadata unavailable: ${response.status}`);
    const metadata = await response.json();
    const service = metadata.serviceConfig?.service;
    const policyResponse = await fetch(`https://run.googleapis.com/v2/${service}:getIamPolicy`, {
      headers: { Authorization: `Bearer ${token.access_token}` },
    });
    const policy = await policyResponse.json();
    const configurationResponse = await fetch(`https://run.googleapis.com/v2/${service}`, {
      headers: { Authorization: `Bearer ${token.access_token}` },
    });
    const configuration = await configurationResponse.json();
    const callableTransport = configuration.invokerIamDisabled === true ||
      (policy.bindings ?? []).some(binding =>
        binding.role === 'roles/run.invoker' && binding.members?.includes('allUsers'));
    const check = await fetch(`https://asia-south1-trustkeyper.cloudfunctions.net/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { agreementId: 'connectivity-check', revision: 1 } }),
    });
    const result = await check.json().catch(() => ({}));
    process.stdout.write(`${JSON.stringify({ name, state: metadata.state, service, policyHttpStatus: policyResponse.status, policyError: policy.error?.status, callableTransport,
      httpStatus: check.status, status: result.error?.status ?? 'non-callable response' })}\n`);
    if (metadata.state !== 'ACTIVE' || check.status !== 401 || result.error?.status !== 'UNAUTHENTICATED') {
      process.exitCode = 1;
    }
  }
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
