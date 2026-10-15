const path = require('node:path');
const { pathToFileURL } = require('node:url');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit Firebase project is required.');
  const accountId = process.argv.find(value => value.startsWith('--linked-account='))?.slice(17);
  const productId = process.argv.find(value => value.startsWith('--product='))?.slice(10);
  if (!/^acc_[A-Za-z0-9]{1,64}$/.test(accountId ?? '') ||
      !/^acc_prd_[A-Za-z0-9]{1,64}$/.test(productId ?? '')) {
    throw new Error('Choose the real Test Linked Account and its Route product configuration IDs.');
  }
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  if (!account) throw new Error('Business Firebase deployment account is not signed in.');
  const token = await deploymentAuth.getAccessToken(account.tokens.refresh_token,
    account.tokens.scopes ?? ['https://www.googleapis.com/auth/cloud-platform']);
  async function secret(name) {
    const response = await fetch(`https://secretmanager.googleapis.com/v1/projects/trustkeyper/secrets/${name}/versions/latest:access`,
      { headers: { Authorization: `Bearer ${token.access_token}` }, signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw new Error(`Private test credential lookup failed with HTTP ${response.status}.`);
    const result = await response.json();
    if (!result.payload?.data) throw new Error('The test credential is unavailable.');
    return Buffer.from(result.payload.data, 'base64').toString('utf8').trim();
  }
  const { razorpayRouteTestProvider } = await import(pathToFileURL(path.join(__dirname, '../functions/razorpay-route-test-provider.js')));
  const provider = razorpayRouteTestProvider(await secret('RAZORPAY_TEST_KEY_ID'), await secret('RAZORPAY_TEST_KEY_SECRET'));
  const result = await provider.readiness(accountId, productId);
  process.stdout.write(`${JSON.stringify(result)}\n`);
  if (!result.ready) throw new Error('The Test Route destination is not activated. No account, order, transfer or settlement was changed.');
  process.stdout.write('PASS: read-only Test Route readiness. No provider data or money was changed.\n');
}
main().catch(error => {
  process.stderr.write(`Route readiness check failed: ${error.code ?? error.message}\n`);
  process.exitCode = 1;
});
