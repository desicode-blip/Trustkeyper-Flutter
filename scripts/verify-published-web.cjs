const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

async function main() {
  const build = process.argv.find(value => /^--build=\d+$/.test(value))?.split('=')[1];
  if (!build) throw new Error('Specify the release build number.');
  const root = path.join(__dirname, '..');
  const results = [];
  for (const name of ['index.html', 'flutter_bootstrap.js', 'firebase-startup.js', 'main.dart.js']) {
    const local = fs.readFileSync(path.join(root, 'apps/flutter_app/build/web', name));
    let response;
    try {
      response = await fetch(`https://trustkeyper.web.app/${name}`, {
        cache: 'no-store', signal: AbortSignal.timeout(120000),
      });
    } catch (error) {
      throw new Error(`Hosted ${name} transport failed: ${error.cause?.code ?? error.name}`);
    }
    if (!response.ok) throw new Error(`Hosted asset unavailable: ${name} (${response.status})`);
    const hosted = Buffer.from(await response.arrayBuffer());
    const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
    if (digest(local) !== digest(hosted)) throw new Error(`Hosted asset does not match this build: ${name}`);
    results.push({ name, bytes: local.length, sha256: digest(local), publishedBytesMatch: true });
  }
  const evidence = { build: Number(build), project: 'trustkeyper', host: 'https://trustkeyper.web.app',
    checkedAt: new Date().toISOString(), results, limitation: 'Published-byte verification, not authenticated journey or physical-device acceptance.' };
  fs.writeFileSync(path.join(root, `output/ui-audit/build${build}-hosted-assets.json`), JSON.stringify(evidence, null, 2));
  process.stdout.write(`${JSON.stringify(evidence)}\n`);
}

main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
