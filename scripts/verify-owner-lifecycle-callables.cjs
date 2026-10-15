const fs = require('node:fs');
const path = require('node:path');
const id = '0'.repeat(64);
const input = {
  beginOwnerContractUpload: { id, revision: 1, operationId: '0'.repeat(32), kind: 'source', spec: { contentType: 'application/pdf', size: 100, sha256: id }, reference: 'TEST unauthenticated guard only', originalChecked: true },
  completeOwnerContractUpload: { uploadId: id }, readOwnerContract: { id },
  changeOwnerPropertyLifecycle: { id, revision: 1, action: 'begin_consent', operationId: '0'.repeat(32) },
  enquireOwnerListing: { id, action: 'view' }, readPublicOwnerListing: { id },
};
async function main() {
  if (!process.argv.includes('--project=trustkeyper')) throw new Error('Explicit production target required.');
  const results = [];
  for (const [name, data] of Object.entries(input)) {
    const response = await fetch(`https://asia-south1-trustkeyper.cloudfunctions.net/${name}`, { method: 'POST',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ data }), signal: AbortSignal.timeout(120000) });
    const envelope = await response.json(); const publicListing = name === 'readPublicOwnerListing';
    if (publicListing ? response.status !== 404 || envelope.error?.status !== 'NOT_FOUND' || envelope.result :
      ![401, 403].includes(response.status) || !['UNAUTHENTICATED', 'PERMISSION_DENIED'].includes(envelope.error?.status) || envelope.result) {
      throw new Error(`Callable guard failed: ${name} (${response.status})`);
    }
    const result = { name, httpStatus: response.status, errorStatus: envelope.error.status, publicListing, noPrivateResult: true };
    results.push(result); process.stdout.write(`${JSON.stringify(result)}\n`);
  }
  fs.writeFileSync(path.join(__dirname, '../output/ui-audit/build31-callable-guards.json'), JSON.stringify({ project: 'trustkeyper',
    testedAt: new Date().toISOString(), results, noAuthenticatedWrite: true }, null, 2));
}
main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
