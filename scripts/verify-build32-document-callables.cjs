const fs = require('node:fs');
const path = require('node:path');
const expected = {
  createDocumentRequest: 'INVALID_ARGUMENT',
  readDocumentRequest: 'FAILED_PRECONDITION',
  recordDocumentRequest: 'INVALID_ARGUMENT',
  beginDocumentUpload: 'FAILED_PRECONDITION',
  completeDocumentUpload: 'INVALID_ARGUMENT',
};

async function main() {
  if (!process.argv.includes('--project=trustkeyper')) {
    throw new Error('Explicit production target required.');
  }
  const results = [];
  for (const [name, status] of Object.entries(expected)) {
    const response = await fetch(
      `https://asia-south1-trustkeyper.cloudfunctions.net/${name}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ data: {} }),
        signal: AbortSignal.timeout(120000),
      },
    );
    let envelope;
    try {
      envelope = await response.json();
    } catch {
      throw new Error(`Document callable transport failed: ${name} (${response.status})`);
    }
    if (![400, 401, 403].includes(response.status) ||
        envelope.error?.status !== status || envelope.result) {
      throw new Error(`Document input/auth guard failed: ${name} (${response.status})`);
    }
    results.push({
      name, callableTransport: true, invalidRequestRejected: true,
      httpStatus: response.status, errorStatus: envelope.error.status,
    });
  }
  const evidence = {
    project: 'trustkeyper', build: 32, checkedAt: new Date().toISOString(),
    noAuthenticatedWrite: true, results,
    limitation: 'Transport/input guards only; not authenticated whole-flow or phone acceptance.',
  };
  fs.writeFileSync(path.join(__dirname,
    '../output/ui-audit/build32-document-callable-guards.json'),
  JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence) + '\n');
}

main().catch(error => {
  process.stderr.write(error.message + '\n');
  process.exitCode = 1;
});
