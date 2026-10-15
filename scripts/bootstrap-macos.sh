#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/apps/flutter_app"

fail() { printf '%s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail 'Run this setup on your Mac, not Windows or Linux.'
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
flutter precache --ios
cd "$app"
flutter pub get --enforce-lockfile
cd ios
bundle config set --local path vendor/bundle
bundle check || bundle install
bundle exec pod install

printf '\n%s\n' 'iOS dependencies are prepared. No Firebase deployment or account changes were made.'
printf '%s\n' 'Open apps/flutter_app/ios/Runner.xcworkspace and select your Apple Development Team.'
printf '%s\n' 'Then run flutter devices and flutter run -d <device-id> from apps/flutter_app.'
