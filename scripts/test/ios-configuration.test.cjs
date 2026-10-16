const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { checkIosConfiguration } = require('../check-ios-configuration.cjs');

const root = path.resolve(__dirname, '../..');
const mutate = (target, transform) => relative => {
  const content = fs.readFileSync(path.join(root, relative), 'utf8');
  return relative === target ? transform(content) : content;
};

test('iOS and Android use shared Firebase identity and pinned Flutter', () => {
  assert.deepEqual(checkIosConfiguration(), {
    flutter: '3.38.6', project: 'trustkeyper', bundleId: 'com.trustkeyper.mobile', minimumIos: '15.0',
  });
});

test('missing phone-auth callback fails preflight', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/Info.plist',
    content => content.replace('app-1-539073703501-ios-9efb50396fa9c31fc5b604', 'wrong-scheme'))), /callback scheme/);
});

test('missing camera disclosure fails preflight', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/Info.plist',
    content => content.replace('NSCameraUsageDescription', 'MissingCameraDisclosure'))), /camera access/);
});

test('a different Firebase project fails instead of creating a second data universe', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/lib/firebase_options.dart',
    content => content.replaceAll("projectId: 'trustkeyper'", "projectId: 'wrong-project'"))), /same Firebase project/);
});

test('missing push entitlement fails preflight', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/Runner.entitlements',
    content => content.replace('aps-environment', 'missing-aps-environment'))));
});

test('every Runner configuration must use the checked-in entitlements', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner.xcodeproj/project.pbxproj',
    content => content.replace('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;', ''))));
});

test('native auth callback handling is registered before Firebase plugins so consumed callbacks cannot fall through', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/AppDelegate.swift',
    content => content.replace('FirebaseAuthCallbackPlugin.register(with: registrar)', ''))), /callback ownership/);
});

test('warm and cold scene callbacks must both reach the native auth handler', () => {
  for (const target of ['registrar.addSceneDelegate(plugin)', 'return handleCallbacks(urlContexts.map',
    'return handleCallbacks(connectionOptions?.urlContexts.map']) {
    assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/AppDelegate.swift',
      content => content.replace(target, 'missingCallback'))));
  }
});

test('normal app links and Firebase callback privacy cannot be disabled to hide the routing failure', () => {
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/Info.plist',
    content => content.replace('<key>LSRequiresIPhoneOS</key>', '<key>FlutterDeepLinkingEnabled</key><false/><key>LSRequiresIPhoneOS</key>'))), /normal app deep links/);
  assert.throws(() => checkIosConfiguration(mutate('apps/flutter_app/ios/Runner/AppDelegate.swift',
    content => content.replace('forwardToAuth(url)', 'print(url)\n      forwardToAuth(url)'))), /Never log auth/);
});
