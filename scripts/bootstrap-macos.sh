#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/apps/flutter_app"
mode="${1:-}"

fail() { printf '%s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail 'Run this setup on your Mac, not Windows or Linux.'
[[ $# -le 1 && ( -z "$mode" || "$mode" == tk2 ) ]] || fail 'Usage: bash scripts/bootstrap-macos.sh [tk2]'
for command in flutter python3 ruby bundle xcodebuild plutil; do
  command -v "$command" >/dev/null 2>&1 || fail "Missing $command. Follow docs/ios-macos-setup.md first."
done

xcode_version="$(xcodebuild -version | sed -n 's/^Xcode //p')"
IFS=. read -r xcode_major xcode_minor xcode_patch <<< "$xcode_version"
if (( xcode_major < 26 || (xcode_major == 26 && ${xcode_minor:-0} < 2) )); then
  fail 'The resolved Firebase Apple SDK requires Xcode 26.2 or newer.'
fi
xcodebuild -checkFirstLaunchStatus || fail 'Finish Xcode first-launch setup and accept its licence, then retry.'
ruby -e 'abort "Use Ruby 3.2+ with Bundler; see docs/ios-macos-setup.md." if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")'

expected_flutter="$(tr -d '\r\n' < "$root/.flutter-version")"
flutter --version --machine | python3 -c 'import json,sys; actual=json.load(sys.stdin)["frameworkVersion"]; expected=sys.argv[1]; sys.exit(0 if actual == expected else "Use Flutter " + expected + ", not " + actual + ", on both machines.")' "$expected_flutter"

plutil -lint "$app/ios/Runner/Info.plist" "$app/ios/Runner/GoogleService-Info.plist" "$app/ios/Runner/Runner.entitlements"
plutil -lint "$app/ios/Runner.xcodeproj/project.pbxproj"
if [[ "$mode" == tk2 ]]; then
  config="$app/ios/Runner/GoogleService-Info-TK2.plist"
  if [[ ! -f "$config" ]]; then
    command -v firebase >/dev/null 2>&1 || fail 'Install Firebase CLI or place the TK2 plist as described in docs/TRUSTKEEPER2-MOBILE.md.'
    firebase apps:sdkconfig IOS '1:882743913919:ios:0e6387885a884e92d4c50a' \
      --project trustkeyper-app-staging --non-interactive --out "$config"
  fi
  plutil -lint "$config"
  python3 - "$config" <<'PY'
import plistlib
import sys

with open(sys.argv[1], 'rb') as file:
    config = plistlib.load(file)
expected = {
    'BUNDLE_ID': 'com.trustkeyper.tk2',
    'GOOGLE_APP_ID': '1:882743913919:ios:0e6387885a884e92d4c50a',
    'PROJECT_ID': 'trustkeyper-app-staging',
    'STORAGE_BUCKET': 'trustkeyper-app-staging.firebasestorage.app',
}
if not config.get('API_KEY') or any(config.get(key) != value for key, value in expected.items()):
    sys.exit('Use the Firebase plist for TrustKeeper 2 Staging, bundle com.trustkeyper.tk2.')
PY
fi
flutter precache --ios
cd "$app"
flutter pub get --enforce-lockfile
cd ios
bundle config set --local path vendor/bundle
bundle check || bundle install
bundle exec pod install

printf '\n%s\n' 'iOS dependencies are prepared. No Firebase deployment or account changes were made.'
printf '%s\n' 'Open apps/flutter_app/ios/Runner.xcworkspace and select your Apple Development Team.'
if [[ "$mode" == tk2 ]]; then
  printf '%s\n' 'Select the tk2 scheme in Xcode, then select your device and press Run.'
else
  printf '%s\n' 'Then run flutter devices and flutter run -d <device-id> from apps/flutter_app.'
fi
