const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { fileURLToPath } = require('node:url');

const root = path.join(__dirname, '..');
const packages = JSON.parse(fs.readFileSync(path.join(root, 'apps/flutter_app/.dart_tool/package_config.json')));
const core = packages.packages.find(value => value.name === 'firebase_core_web');
assert.ok(core, 'Firebase web SDK package must be resolved before building.');
const packageRoot = fileURLToPath(new URL(core.rootUri, `file:///${root.replaceAll('\\', '/')}/apps/flutter_app/.dart_tool/`));
const expected = fs.readFileSync(path.join(packageRoot, 'lib/src/firebase_sdk_version.dart'), 'utf8')
  .match(/supportedFirebaseJsSdkVersion\s*=\s*'([^']+)'/)?.[1];
const configured = fs.readFileSync(path.join(root, 'apps/flutter_app/web/firebase-startup.js'), 'utf8')
  .match(/const version\s*=\s*'([^']+)'/)?.[1];
assert.ok(expected);
assert.equal(configured, expected, 'The preloaded SDK must match the resolved FlutterFire SDK; no version override is allowed.');
console.log('Firebase browser startup SDK matches the resolved FlutterFire version.');
