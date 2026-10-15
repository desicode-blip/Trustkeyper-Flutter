const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const readSource = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const stringValue = (source, key) => source.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`))?.[1];

function checkIosConfiguration(read = readSource) {
  const prefix = 'apps/flutter_app';
  const info = read(`${prefix}/ios/Runner/Info.plist`);
  const google = read(`${prefix}/ios/Runner/GoogleService-Info.plist`);
  const entitlements = read(`${prefix}/ios/Runner/Runner.entitlements`);
  const project = read(`${prefix}/ios/Runner.xcodeproj/project.pbxproj`);
  const options = read(`${prefix}/lib/firebase_options.dart`);
  const ios = options.match(/static const FirebaseOptions ios = FirebaseOptions\(([\s\S]*?)\);/)?.[1];
  assert.ok(ios, 'The iOS Firebase configuration must exist.');
  const appId = stringValue(google, 'GOOGLE_APP_ID');
  assert.ok(appId && ios.includes(appId), 'Firebase iOS app IDs must match.');
  assert.equal(stringValue(google, 'PROJECT_ID'), 'trustkeyper');
  assert.ok(ios.includes("projectId: 'trustkeyper'"), 'iOS must use the same Firebase project.');
  const android = JSON.parse(read(`${prefix}/android/app/google-services.json`));
  assert.equal(android.project_info.project_id, 'trustkeyper');
  assert.equal(stringValue(google, 'BUNDLE_ID'), 'com.trustkeyper.mobile');
  assert.equal((project.match(/PRODUCT_BUNDLE_IDENTIFIER = com\.trustkeyper\.mobile;/g) ?? []).length, 3);
  assert.equal((project.match(/CODE_SIGN_ENTITLEMENTS = Runner\/Runner\.entitlements;/g) ?? []).length, 3);
  assert.ok(info.includes(`<string>app-${appId.replaceAll(':', '-')}</string>`), 'Register the Firebase phone-auth callback scheme.');
  assert.ok(info.includes('<string>trustkeyper</string>'), 'Register the same app-open scheme as Android.');
  assert.ok(stringValue(info, 'NSCameraUsageDescription'), 'Explain document/property camera access.');
  assert.ok(stringValue(info, 'NSPhotoLibraryUsageDescription'), 'Explain document/property photo access.');
  assert.match(info, /<key>UIBackgroundModes<\/key>\s*<array>[\s\S]*?<string>remote-notification<\/string>/);
  assert.doesNotMatch(info, /<key>FirebaseAppDelegateProxyEnabled<\/key>\s*<false\s*\/>/);
  assert.equal(stringValue(entitlements, 'aps-environment'), 'development');
  assert.equal(stringValue(entitlements, 'com.apple.developer.devicecheck.appattest-environment'), 'production');
  assert.match(read(`${prefix}/ios/Podfile`), /platform :ios, '15\.0'/);
  assert.doesNotMatch(project, /FlutterGeneratedPluginSwiftPackage/);
  assert.ok(read(`${prefix}/ios/Flutter/Debug.xcconfig`).includes('Pods-Runner.debug.xcconfig'));
  assert.ok(read(`${prefix}/ios/Flutter/Release.xcconfig`).includes('Pods-Runner.release.xcconfig'));
  assert.ok(read(`${prefix}/ios/Flutter/Profile.xcconfig`).includes('Pods-Runner.profile.xcconfig'));
  assert.match(read(`${prefix}/pubspec.yaml`), /enable-swift-package-manager: false/);
  const version = read('.flutter-version').trim();
  assert.equal(version, JSON.parse(read('.fvmrc')).flutter);
  return { flutter: version, project: 'trustkeyper', bundleId: 'com.trustkeyper.mobile', minimumIos: '15.0' };
}

module.exports = { checkIosConfiguration };
if (require.main === module) {
  console.log('iOS configuration checks passed:', checkIosConfiguration());
}
