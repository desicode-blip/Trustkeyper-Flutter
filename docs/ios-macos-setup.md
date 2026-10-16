# Run the same TrustKeyper app on your Mac and iPhone

## What is shared

Android and iOS build the same `apps/flutter_app/lib` screens, theme, fonts,
validation, repositories and workflows. Both connect to Firebase project
`trustkeyper`; the bundle/application identifier is `com.trustkeyper.mobile`.
An existing verified account reaches the same UID/records on either platform.
Do not register a new Firebase project or replace its checked-in client config.
Native permission prompts, camera/file pickers and keyboards follow their OS.

This repository prepares version **2.0.0+47**. The older signed Android build 46
is not proof of acceptance for these iOS changes. Actual iOS compilation,
signing and physical-device acceptance require a Mac/iPhone; Windows cannot
certify them. Current product limitations remain in
`product-requirements-coverage.md`. Razorpay Route remains deferred.

## 1. Install the Mac tools once

- Install Xcode **26.2 or newer** and its iOS platform/simulator components.
- Open Xcode once, finish installation and accept its licence. If command-line
  tools point to the wrong installation, run
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.
- Install Flutter **3.38.6** with Dart **3.10.7**, matching Windows. The version
  is pinned in `.flutter-version` and `.fvmrc`. Do not use a newer SDK only on
  the Mac or run `flutter pub upgrade`. If using FVM, run `fvm install` and add
  this project's `.fvm/flutter_sdk/bin` to PATH before setup.
- Install Ruby **3.2+** and Bundler. For Homebrew Ruby, add
  `export PATH="$(brew --prefix ruby)/bin:$PATH"` to your shell setup and run
  `gem install bundler` if `bundle` is absent. System Ruby 2.6 is not used.
- Python 3 must be on PATH. Node.js 22 is only needed for backend/tooling tests.

The resolved Firebase Apple SDK 12.19.0 uses the current Apple toolchain;
see the [Firebase release requirements](https://firebase.google.com/support/release-notes/ios)
and [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup).

## 2. Clone and prepare

```bash
git clone https://github.com/desicode-blip/Trustkeyper-Flutter.git
cd Trustkeyper-Flutter
bash scripts/bootstrap-macos.sh
open apps/flutter_app/ios/Runner.xcworkspace
```

The script checks Xcode/Ruby/Flutter, validates the native property lists,
downloads iOS engine artifacts, restores the committed Dart dependency versions
and installs CocoaPods **1.16.2** locally through Bundler. Always open
`Runner.xcworkspace`, not `Runner.xcodeproj`. No Firebase CLI login, deployment,
Razorpay secret, Android keystore or service-account file is needed to run the
client. Firebase's checked-in client API configuration is not an administrator
credential. Provider secrets remain on the backend.

CocoaPods is configured for all existing native plugins; incomplete generated
Swift-package references have been removed. Commit the real `Podfile.lock` and
`Gemfile.lock` after the first successful Mac dependency install. Do not invent
native lockfile versions or delete lockfiles routinely to resolve a build.

## 3. Select Apple's signing team

In Xcode Settings → Accounts, sign in to the authorised Apple Developer account.
Select Runner target → Signing & Capabilities → choose the company's Team and
keep automatic signing. Keep bundle ID `com.trustkeyper.mobile`; changing it
creates another app identity and invalidates the existing Firebase binding.

Push Notifications, Background Modes (fetch/remote notifications) and App Attest
are declared in source. Your Apple app identifier/provisioning profile must
allow those capabilities. A paid Apple Developer team is needed for the full
capability set and distribution. No team ID, certificate or private Apple key
has been guessed or committed. Simulator builds do not require device signing.

## 4. Finish APNs once for real phone OTP and push

In the Apple Developer account, create/reuse an APNs authentication key for the
company's team. In Firebase → TrustKeyper → Project settings → Cloud Messaging
→ iOS app, upload that private `.p8` and enter its key ID/team ID. Do this in the
console, never in Git or chat. Do not replace the Google Workspace/Resend DNS
records. APNs setup affects Apple notifications, not email delivery.

The Firebase phone-auth callback URL scheme is already registered. Silent
verification uses APNs; the SDK can use reCAPTCHA when needed. Keep Firebase's
delegate swizzling enabled. See [Apple phone-auth requirements](https://firebase.google.com/docs/auth/ios/phone-auth)
and [Flutter messaging setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).
The broker's token registration now waits for APNs before requesting its FCM
token, without registering a token after logout/account switching.

The native callback handler now claims only Firebase's verification callback
before it can become a GoRouter page, including repeated/warm/cold scene events.
If an older build shows `Page Not Found` after reCAPTCHA, rebuild the focused
fix from the Mac; hot reload cannot replace its Swift code. Follow
`ios-phone-otp-callback-fix.md` for the branch, native tests and iPhone checks.
Do not add a page route for the callback, disable verification, or disable all
normal application deep links as a workaround.

Release builds use App Attest in production mode; debug builds keep the existing
debug provider. If Firebase reports an App Check denial, register that Mac/iPhone
debug token privately in the existing project's App Check settings; never commit
it or disable enforcement to conceal a problem. See
[Firebase App Attest setup](https://firebase.google.com/docs/app-check/ios/app-attest-provider).

## 5. Run on the phone

Connect/unlock the iPhone, trust the Mac and enable Developer Mode. Then:

```bash
cd apps/flutter_app
flutter devices
flutter run -d YOUR_IPHONE_DEVICE_ID
```

For a simulator, start Simulator/Device Hub from Xcode and select its device ID.
The normal app still uses the real Firebase backend; use designated test accounts
and harmless fixture documents, not customer data. Do not install the synthetic
`ui_test_main.dart` entry over a real iPhone app: the separate offline package
identity currently applies to Android, not iOS. Fixtures can be used on a
dedicated simulator. Normal phone OTP uses Firebase, not an app-side bypass.

## 6. Check parity and produce an archive

```bash
flutter analyze
flutter test test/push_token_readiness_test.dart test/mobile_platform_parity_test.dart
flutter build ios --simulator --debug
```

The focused checks exercise token ordering/cancellation and the same owner/tenant
document controls under Android and iOS Flutter platform settings. They are not
a substitute for a signed physical iPhone run. The earlier full suite has 14
document-state test-clock/golden failures; no baseline is regenerated to hide
them. Run the full suite and record them separately.

For TestFlight, use Xcode Product → Archive and Organizer's normal distribution
flow, or `flutter build ipa --release` after signing is configured. Let Xcode's
distribution export select production APNs entitlements from the provisioning
profile; do not hardcode private signing material. Review Apple privacy/store
requirements before distribution, including actual identity/document collection.

On Android and iPhone verify the same account/profile; property draft save and
resume; broker owner/tenant invite; browser OTP and uploads; broker notification
and request states; LinkedIn; agreement review and admin-uploaded signed PDF;
private PDF view/save; repairs, move-in/out and logout/relogin. Check camera,
photo/file permissions both allowed and denied; WhatsApp/SMS/email launch and
cancel; notification permission denied, delayed APNs and cold-start notification
tap. Real payment/settlement acceptance remains deferred, not simulated.

## Verified before publication

On 15 October 2026, the clean publication checkout passed 257 backend tests
under Node.js 22.23.3, 11 tooling/configuration tests, the web-bootstrap recovery
scenario and all 10 focused Flutter push/shared-platform checks. Flutter analysis
reported no issues. Native property lists, the Xcode project structure and the
Mac shell script were syntax-checked; this is not an Xcode compilation result.
The full Flutter suite's 14 pre-existing document-state clock failures remain
recorded separately; publishing the source does not mark them as passing.
