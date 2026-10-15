const path = require('node:path');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper') || !process.argv.includes('--apply')) {
    throw new Error('Explicit project and apply are required.');
  }
  const allowed = ['requestEmailOtp', 'verifyEmailOtp', 'requestProfileEmailOtp', 'verifyProfileEmailOtp',
    'requestAccountEmailOtp', 'verifyAccountEmailOtp', 'issueKeyReturnCode'];
  const names = process.argv.find(argument => argument.startsWith('--functions='))?.slice(12).split(',') ?? allowed;
  if (!names.length || names.some(name => !allowed.includes(name)) || new Set(names).size !== names.length) {
    throw new Error('Choose unique known email/key-code functions.');
  }
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business deployment account is required.');
  const credential = await deploymentAuth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function request(url, body, method = body ? 'POST' : 'GET') {
    const response = await fetch(url, { method,
      headers: { Authorization: `Bearer ${credential.access_token}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(`Runtime configuration HTTP ${response.status}`);
    return result;
  }
  const failures = [];
  for (const name of names) {
    try {
    const metadata = await request(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`);
    const serviceName = `projects/trustkeyper/locations/asia-south1/services/${name.toLowerCase()}`;
    if (metadata.serviceConfig?.service !== serviceName) throw new Error('Function runtime identity did not match.');
    const url = `https://run.googleapis.com/v2/${serviceName}`;
    const current = await request(url);
    const containers = current.template?.containers;
    if (containers?.length !== 1 || containers[0].resources?.limits?.cpu !== '0.1666' ||
        containers[0].resources?.limits?.memory !== '256Mi' || current.template.maxInstanceRequestConcurrency !== 1 ||
        current.template.scaling?.maxInstanceCount !== 3) {
      throw new Error('Runtime must already have the reviewed bounded email/key-code settings.');
    }
    const changed = containers[0].resources.startupCpuBoost === true || current.invokerIamDisabled !== true ||
      current.terminalCondition?.state !== 'CONDITION_SUCCEEDED';
    if (changed) {
      containers[0].resources.startupCpuBoost = false;
      const revision = `${name.toLowerCase()}-email-${Date.now().toString(36)}`;
      let operation = await request(`${url}?updateMask=invokerIamDisabled,template.containers,template.revision`, {
        name: serviceName, etag: current.etag, invokerIamDisabled: true, template: { revision, containers },
      }, 'PATCH');
      for (let attempt = 0; !operation.done && attempt < 90; attempt++) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        operation = await request(`https://run.googleapis.com/v2/${operation.name}`);
      }
      if (!operation.done || operation.error) throw new Error('Bounded runtime revision failed to become ready.');
    }
    const verified = await request(url);
    if (verified.terminalCondition?.state !== 'CONDITION_SUCCEEDED' || verified.invokerIamDisabled !== true ||
        verified.template.containers[0].resources.startupCpuBoost === true) throw new Error('Runtime acceptance failed.');
    process.stdout.write(`${JSON.stringify({ name, cpu: '0.1666', memory: '256Mi', startupCpuBoost: false,
      concurrency: 1, maxInstances: 3, ready: true, callableTransport: true,
      latestReadyRevision: verified.latestReadyRevision?.split('/').pop() })}\n`);
    } catch (error) {
      failures.push(name);
      process.stdout.write(`${JSON.stringify({ name, ready: false, reason: error.message })}\n`);
    }
  }
  if (failures.length) throw new Error(`Runtime recovery remains pending for: ${failures.join(', ')}`);
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
