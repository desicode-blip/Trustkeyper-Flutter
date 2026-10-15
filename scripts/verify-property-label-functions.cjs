const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const deploymentAuth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));

async function main() {
  assert.ok(process.argv.includes('--project=trustkeyper'), 'Explicit production target required.');
  const build = Number(process.argv.find(value => value.startsWith('--build='))?.slice(8));
  assert.ok(Number.isSafeInteger(build) && build >= 36, 'Choose an optional-property-label build.');
  const root = path.join(__dirname, '..');
  const deploymentScript = fs.readFileSync(path.join(__dirname, 'deploy-property-label-functions.ps1'), 'utf8');
  const list = deploymentScript.match(/\$names\s*=\s*@\(([\s\S]*?)\)/)?.[1];
  const names = [...(list ?? '').matchAll(/'([A-Za-z]+)'/g)].map(match => match[1]);
  assert.equal(names.length, 26, 'Expected the complete affected callable set.');
  const evidence = path.join(root, 'output/ui-audit');
  const logs = fs.readdirSync(evidence).filter(name => new RegExp(`^build${build}-backend-batch\\d+\\.log$`).test(name));
  const deployed = logs.map(name => fs.readFileSync(path.join(evidence, name), 'utf8')).join('\n');
  const sources = ['agreement-review.js', 'document-requests.js', 'owner-properties.js'].map(name => {
    const file = path.join(root, 'functions', name);
    return { name, modifiedAt: fs.statSync(file).mtime.toISOString(),
      sha256: createHash('sha256').update(fs.readFileSync(file)).digest('hex') };
  });
  const latestSource = Math.max(...sources.map(source => Date.parse(source.modifiedAt)));
  const account = deploymentAuth.getAllAccounts().find(entry => entry.user.email === 'ajay@trustkeyper.com');
  assert.ok(account, 'Business deployment account is not signed in.');
  const token = await deploymentAuth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes);
  const headers = { Authorization: `Bearer ${token.access_token}` };
  const functions = [];
  for (const name of names) {
    const response = await fetch(`https://cloudfunctions.googleapis.com/v2/projects/trustkeyper/locations/asia-south1/functions/${name}`, {
      headers, signal: AbortSignal.timeout(60000),
    });
    assert.ok(response.ok, `Function metadata unavailable for ${name}.`);
    const metadata = await response.json();
    assert.equal(metadata.state, 'ACTIVE', `${name} must be active.`);
    assert.ok(Date.parse(metadata.updateTime) >= latestSource, `${name} predates the updated property-label source.`);
    const source = metadata.buildConfig?.source?.storageSource;
    assert.equal(source?.bucket, 'gcf-v2-sources-539073703501-asia-south1');
    assert.equal(source?.object, `${name}/function-source.zip`);
    assert.match(source?.generation ?? '', /^\d+$/);
    const archiveResponse = await fetch(`https://storage.googleapis.com/storage/v1/b/${source.bucket}/o/${encodeURIComponent(source.object)}?alt=media&generation=${source.generation}`, {
      headers, signal: AbortSignal.timeout(60000),
    });
    assert.ok(archiveResponse.ok, `Deployed source unavailable for ${name}.`);
    const archiveBytes = Buffer.from(await archiveResponse.arrayBuffer());
    assert.ok(archiveBytes.length < 2000000, 'Unexpectedly large source archive.');
    const reader = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `
      $ErrorActionPreference = 'Stop';
      Add-Type -AssemblyName System.IO.Compression;
      $archive = [System.IO.Compression.ZipArchive]::new([Console]::OpenStandardInput(), [System.IO.Compression.ZipArchiveMode]::Read);
      $algorithm = [System.Security.Cryptography.SHA256]::Create();
      try {
        $result = @{};
        foreach ($file in @('agreement-review.js','document-requests.js','owner-properties.js')) {
          $entry = $archive.GetEntry($file);
          if (!$entry) { throw 'Required source file is missing.' };
          $stream = $entry.Open();
          try { $result[$file] = [System.BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant(); }
          finally { $stream.Dispose(); }
        };
        $result | ConvertTo-Json -Compress;
      } finally { $algorithm.Dispose(); $archive.Dispose(); }
    `], { input: archiveBytes, encoding: 'utf8', timeout: 30000, maxBuffer: 8192, windowsHide: true });
    assert.equal(reader.status, 0, 'Deployed-source hash inspection failed.');
    const hashes = JSON.parse(reader.stdout);
    for (const file of sources) assert.equal(hashes[file.name], file.sha256, `Deployed source differs for ${name}/${file.name}.`);
    let signedWebhookTransportVerified;
    if (name === 'razorpayTestWebhook') {
      const serviceResponse = await fetch(`https://run.googleapis.com/v2/${metadata.serviceConfig.service}`, { headers });
      assert.ok(serviceResponse.ok);
      const service = await serviceResponse.json();
      assert.equal(service.invokerIamDisabled, true);
      const unsigned = await fetch(`https://asia-south1-trustkeyper.cloudfunctions.net/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'x-razorpay-signature': '0'.repeat(64) }, body: '{}',
        signal: AbortSignal.timeout(60000),
      });
      assert.equal(unsigned.status, 400, 'Unsigned gateway callbacks must be rejected before recording payments.');
      signedWebhookTransportVerified = true;
    }
    functions.push({ name, state: metadata.state, updatedAt: metadata.updateTime, deployedSourceHashesMatch: true,
      deploymentCliReportedSuccess: deployed.includes(`functions[authentication:${name}(asia-south1)] Successful update operation.`),
      ...(signedWebhookTransportVerified ? { signedWebhookTransportVerified } : {}) });
  }
  console.log(JSON.stringify({ project: 'trustkeyper', build, checkedAt: new Date().toISOString(),
    updatedFunctionCount: functions.length, sources, functions }, null, 2));
}

main().catch(() => {
  console.error('Affected-function metadata or successful-deployment verification failed. Credentials are not logged.');
  process.exitCode = 1;
});
