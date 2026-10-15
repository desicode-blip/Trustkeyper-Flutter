const path = require('node:path');
const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  const account = auth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('TrustKeyper deployment account is not signed in.');
  const token = await auth.getAccessToken(account.tokens.refresh_token,
    [...(account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform'])]);
  async function inspect(url, pick) {
    const response = await fetch(url, { headers: { Authorization: `Bearer ${token.access_token}` } });
    const body = await response.json().catch(() => ({}));
    return response.ok ? pick(body) : { httpStatus: response.status, status: body.error?.status ?? 'unavailable',
      reasons: (body.error?.details ?? []).map(detail => detail.reason).filter(Boolean) };
  }
  const selectedProject = process.argv.find(argument => argument.startsWith('--project='))?.slice('--project='.length);
  if (selectedProject && !['trustkeyper', 'trustkeyper-app-staging'].includes(selectedProject)) throw new Error('Unknown project.');
  for (const project of selectedProject ? [selectedProject] : ['trustkeyper-app-staging', 'trustkeyper']) {
    const billing = await inspect(`https://cloudbilling.googleapis.com/v1/projects/${project}/billingInfo`, body => ({ enabled: body.billingEnabled === true }));
    const storage = await inspect(`https://firebasestorage.googleapis.com/v1beta/projects/${project}/defaultBucket`, body => ({ name: body.name, bucket: body.bucket?.name ?? body.bucket }));
    const functions = await inspect(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/asia-south1/functions`, body => ({ entries: (body.functions ?? []).map(entry => ({ name: entry.name.split('/').pop(), state: entry.state, uri: entry.serviceConfig?.uri })) }));
    const secrets = await inspect(`https://secretmanager.googleapis.com/v1/projects/${project}/secrets`, body => ({ names: (body.secrets ?? []).map(entry => entry.name.split('/').pop()) }));
    process.stdout.write(`${JSON.stringify({ project, billing, storage, functions, secrets })}\n`);
  }
}
main().catch(() => { process.stderr.write('Could not inspect Firebase readiness. Refresh the deployment login or check project permissions.\n'); process.exitCode = 1; });
