const fs = require('node:fs');
const path = require('node:path');

async function main() {
  if (!process.argv.includes('--project=trustkeyper') || !process.argv.includes('--read-only')) {
    throw new Error('Explicit project and read-only mode are required.');
  }
  const checks = [];
  for (const name of ['requestAccountEmailOtp', 'verifyAccountEmailOtp']) {
    const response = await fetch(`https://asia-south1-trustkeyper.cloudfunctions.net/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: {} }), signal: AbortSignal.timeout(70000),
    });
    const body = await response.json();
    const denied = body.error?.status === 'UNAUTHENTICATED';
    checks.push({ name, anonymousDenied: denied, mailRequested: false, accountMutation: false });
    if (!denied) throw new Error(`${name} did not return its expected authentication guard.`);
  }
  fs.writeFileSync(path.join(__dirname, '../output/ui-audit/build46-email-callable-guards.json'),
    JSON.stringify({ project: 'trustkeyper', readOnly: true, checks }, null, 2));
  process.stdout.write(`${JSON.stringify({ checked: checks.length, anonymousDenied: true, mailRequested: false })}\n`);
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
