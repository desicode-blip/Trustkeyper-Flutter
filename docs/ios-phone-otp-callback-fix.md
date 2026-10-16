# iOS phone OTP callback fix

## Problem and scope

The reported iPhone screen showed GoRouter trying to open the Firebase
`firebaseauth/link` callback as an application page after reCAPTCHA. The URL
contains verification material, not a TrustKeyper page. The app's callback
scheme was already registered; adding an ordinary route for it would not fix
native callback ownership.

The pinned Firebase SDK can consume the callback before another lifecycle
delegate observes it. Its `canHandle` result is not a durable indication that
the callback belongs to the application router: a repeated or already-consumed
callback can return false. This source fix claims only the current Firebase
app's encoded callback scheme, `firebaseauth` host and `/link` path.

## Implementation

`FirebaseAuthCallbackPlugin` lives in `ios/Runner/AppDelegate.swift`, already in
the Runner build target. It registers before generated plugins, retains its
delegate through the registrar, and handles legacy application URLs, warm scene
URL contexts and cold scene connection options. Recognised callbacks go to
Firebase Auth and are reported handled even if another Firebase observer has
already consumed them. Unrelated application/browser links are not claimed.

It does not parse tokens, create credentials, accept an OTP, mark someone signed
in or bypass app verification. Normal Firebase phone authentication decides the
result. Callback URLs are never logged. Firebase delegate swizzling, APNs,
registered schemes and normal Flutter deep linking remain enabled. Android,
shared UI, Firebase configuration, payment code and account data are unchanged.

## Run the focused fix on the Mac

Use the published fix branch/PR, not an unchanged `main` checkout. Preserve any
uncommitted Mac work before switching branches; do not reset or clean it.

```bash
git fetch origin
git switch --track origin/codex/ios-phone-otp-callback
cd apps/flutter_app
flutter pub get --enforce-lockfile
cd ios
bundle exec pod install
cd ..
flutter devices
flutter run -d YOUR_IPHONE_DEVICE_ID
```

If the fix branch already exists locally, use `git switch codex/ios-phone-otp-callback`
and `git pull --ff-only` instead of `git switch --track`. Keep Flutter 3.38.6,
the existing Apple signing team and bundle ID. No backend deployment or Firebase
console reset is required for this native callback fix. Stop the old app run
and rebuild/reinstall from the Mac; hot reload cannot update Swift code.

## Acceptance on Mac/iPhone

1. Open `ios/Runner.xcworkspace`, select Runner and a simulator, and run Product
   → Test. Five `RunnerTests` cover native forwarding, duplicate/no-pending
   callbacks, unrelated URLs, multiple callbacks and empty/missing configuration.
2. On the physical iPhone, request a phone OTP. If Firebase opens reCAPTCHA,
   finish it and return to the app. The verification URL must not become a
   Page Not Found screen; normal code-sent/verification-error handling must run.
3. Enter the newly received OTP, not a code from a previous attempt. Verify the
   expected account/profile and sign out/retry. Repeat after backgrounding the
   app during the browser verification. Do not log/share the full callback URL.
4. Cancel the browser verification, retry normally, and check that no account is
   logged in merely because a callback opened. If the app was killed during
   verification, start a fresh OTP request; callbacks cannot restore a lost
   in-memory phone verification session.
5. Verify the normal `trustkeyper` app-open link and owner/tenant document browser
   links still work. Keep the APNs setup in `ios-macos-setup.md`; reCAPTCHA is a
   supported fallback, not itself an error or proof APNs is configured.

The Windows verification covers nine native-configuration checks, fourteen full
tooling checks and twelve focused Flutter push/shared-platform/splash checks.
Native XCTest compilation and physical iPhone OTP acceptance require the Mac;
they are not claimed as run on Windows. This fix does not certify unrelated
product flows or the full Flutter suite.

References: [Firebase Apple phone authentication](https://firebase.google.com/docs/auth/ios/phone-auth),
[Flutter deep linking](https://docs.flutter.dev/ui/navigation/deep-linking).
