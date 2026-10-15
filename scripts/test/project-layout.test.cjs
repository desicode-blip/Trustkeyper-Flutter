const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const readJson = relative => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));

test('only the Flutter app and Firebase backend remain in the active project', () => {
  for (const relative of ['apps/mobile', 'api', 'artifacts', 'lib', 'supabase',
    'attached_assets', 'vercel.json', '.vercel', 'pnpm-workspace.yaml',
    'pnpm-lock.yaml', 'docker-compose.yml', '.replit', 'tsconfig.api.json',
    'vitest.config.api.ts', '.github/workflows/ci.yml']) {
    assert.equal(fs.existsSync(path.join(root, relative)), false, `${relative} is obsolete`);
  }
  for (const relative of ['apps/flutter_app/lib/main.dart', 'apps/flutter_app/lib/ui_test_main.dart',
    'apps/flutter_app/pubspec.lock', 'functions/index.js', 'functions/package-lock.json']) {
    assert.ok(fs.existsSync(path.join(root, relative)), `${relative} must be preserved`);
  }
});

test('root tooling has no legacy workspace or application dependencies', () => {
  const manifest = readJson('package.json');
  assert.equal(manifest.private, true);
  assert.equal(manifest.engines.node, '22');
  assert.deepEqual(manifest.dependencies ?? {}, {});
  assert.deepEqual(manifest.devDependencies ?? {}, {});
  assert.equal(manifest.workspaces, undefined);
  const lock = readJson('package-lock.json');
  assert.deepEqual(Object.keys(lock.packages), ['']);
  assert.equal(lock.version, manifest.version);
  assert.doesNotMatch(JSON.stringify(manifest.scripts), /pnpm|supabase|vercel|expo|@workspace\//i);
  assert.ok(manifest.scripts['dev:mobile'].includes('apps/flutter_app'));
  assert.ok(manifest.scripts['test:rules'].includes('--project demo-trustkeyper-rules'));
  assert.doesNotMatch(JSON.stringify(manifest.scripts), /firebase deploy/);
});

test('Firebase configuration points exclusively at the retained app and backend', () => {
  const config = readJson('firebase.json');
  assert.equal(config.functions.length, 1);
  assert.equal(config.functions[0].source, 'functions');
  assert.equal(config.functions[0].codebase, 'authentication');
  assert.equal(config.hosting.public, 'apps/flutter_app/build/web');
  for (const relative of [config.firestore.rules, config.firestore.indexes, config.storage.rules]) {
    assert.ok(fs.existsSync(path.join(root, relative)));
  }
  const backend = readJson('functions/package.json');
  assert.equal(backend.engines.node, '22');
  assert.ok(backend.dependencies['firebase-admin']);
  assert.ok(backend.dependencies['firebase-functions']);
  assert.doesNotMatch(JSON.stringify(backend), /@supabase|@vercel|workspace:|drizzle-orm|"pg"/i);
});

test('retained tooling does not load any removed source tree', () => {
  for (const entry of fs.readdirSync(path.join(root, 'scripts'), { withFileTypes: true })) {
    if (!entry.isFile() || !/\.(cjs|ps1|py)$/.test(entry.name)) continue;
    const source = fs.readFileSync(path.join(root, 'scripts', entry.name), 'utf8');
    assert.doesNotMatch(source, /apps[\\/]mobile|artifacts[\\/]trustkeyper|lib[\\/]db|@workspace\/|pnpm|release-internal-20260917/,
      `${entry.name} must be independent of the retired code`);
  }
});

test('editor launches Flutter and signing defaults live outside the repository', () => {
  const launch = readJson('.vscode/launch.json');
  assert.ok(launch.configurations.length >= 2);
  for (const config of launch.configurations) {
    assert.equal(config.type, 'dart');
    assert.equal(config.cwd, '${workspaceFolder}/apps/flutter_app');
    assert.ok(fs.existsSync(path.join(root, 'apps/flutter_app', config.program)));
  }
  const offline = launch.configurations.find(config => config.program === 'lib/ui_test_main.dart');
  assert.ok(offline.toolArgs.includes('--dart-define=TRUSTKEYPER_UI_TEST=true'));
  for (const file of ['build-flutter-aab.ps1', 'build-testing-release.ps1']) {
    const source = fs.readFileSync(path.join(root, 'scripts', file), 'utf8');
    assert.ok(source.includes('TRUSTKEYPER_SIGNING_CREDENTIALS_FILE'));
    assert.ok(source.includes("Join-Path $HOME '.trustkeyper/signing/android-upload.json'"));
  }
  const release = fs.readFileSync(path.join(root, 'scripts/build-testing-release.ps1'), 'utf8');
  assert.ok(release.includes('*/test/failures/*'));
});
