# TrustKeyper — Flutter + Firebase

## Start on a Mac / iPhone

Clone `https://github.com/desicode-blip/Trustkeyper-Flutter.git`, install the
pinned Flutter 3.38.6, Xcode 26.2+ and Ruby 3.2+/Bundler, then run:

```bash
bash scripts/bootstrap-macos.sh
open apps/flutter_app/ios/Runner.xcworkspace
```

Select your Apple signing team, then run `flutter run -d YOUR_DEVICE_ID` from
`apps/flutter_app`. Follow [the complete Mac/iOS guide](docs/ios-macos-setup.md),
including the one-time APNs configuration. Version 2.0.0+47 uses the same Dart
screens, fonts, workflows and Firebase backend as Android. Native build/device
acceptance is still required; Windows cannot certify an iPhone build.

The supported app is `apps/flutter_app`. Firebase Authentication, Firestore,
Storage, Cloud Functions and Hosting provide its backend and web hosting.
Android, iOS, the owner/tenant document-link website and the admin portal share
the Flutter source. The primary checkout is `D:\Trustkeyper\Project`.

The previous application and its setup have been removed locally. See
`docs/legacy-stack-retirement.md` for the recovery backup and exact scope.
Git history, remote services, DNS, customer data and phone installations were
not deleted by this cleanup.

## Setup

Use Flutter 3.38.6 / Dart 3.10, Node.js 22, Java 17 and the Android SDK. Java 21
is required for the Firebase emulator suite. Add Flutter, Node, Java and the
Firebase CLI to PATH. From the project root:

```powershell
npm run setup:backend
npm run setup:flutter
npm run dev:mobile
```

`npm run dev:web` opens the normal Firebase-connected web app. Production
configuration targets Firebase project `trustkeyper`; do not experiment on
customer records. `npm run dev:ui-test` instead launches synthetic offline
fixtures under the separate Android package `com.trustkeyper.mobile.uitest`.
Never replace the original phone installation without an explicit request.

## Verification

```powershell
npm test
npm run analyze
npm run test:flutter
npm run test:rules
npm run build:web
```

Backend dependencies and their lockfile belong to `functions`; the root npm
manifest only provides commands and has no application dependencies. No pnpm,
Docker/Postgres, Expo or Vercel setup is needed. Emulator tests explicitly use
`demo-trustkeyper-rules`, not the production project.

## Android releases

Private upload signing material is outside the repository at
`$HOME\.trustkeyper\signing\android-upload.json` and its adjacent keystore.
Alternatively set `TRUSTKEYPER_SIGNING_CREDENTIALS_FILE` or pass
`-SigningCredentialsFile`. Do not print or commit its contents.

```powershell
.\scripts\build-flutter-aab.ps1 -VerifySigningOnly
.\scripts\build-testing-release.ps1 -Build 47
```

The build number must match `pubspec.yaml`. The testing-release script runs
tests/analysis, builds web, signs the normal AAB, builds a separate offline
UI Test APK and verifies unchanged application sources. It does not deploy,
upload to Play or install either app. See the current platform guide,
`TESTING.md`, `docs/ios-macos-setup.md` and `docs/handoff-status.md` before release. Historical build-46
binaries are retained locally in `output/releases/build46`; they predate the
version-47 iOS preparation and are not fresh version-47 binaries.

## Project map

- `apps/flutter_app/`: app, shared assets and Flutter tests.
- `functions/`: trusted backend, unit and emulator integration tests.
- `firebase.json`, `.firebaserc`, `firestore.*`, `storage.rules`: Firebase configuration.
- `scripts/`: Flutter/Firebase build, verification, device and design utilities.
- `docs/`: product coverage, testing guides and historical build evidence.
- `output/`: ignored local designs, requirements, release evidence and tooling;
  preserve these references when cleaning generated build caches.

Razorpay Route work remains deferred. Other unaccepted states are tracked in
`docs/product-requirements-coverage.md`; removing obsolete code does not
establish full product acceptance.
