# Verification

Run from `D:\Trustkeyper\Project` with Flutter and Node.js 22 on PATH:

```powershell
npm run setup:backend
npm run setup:flutter
npm test
npm run analyze
npm run test:flutter
```

`npm test` runs backend unit tests, project-layout regression checks and browser
bootstrap unit scenarios without production credentials or mail. Layout checks
reject old application trees, dependencies, imports and editor launch targets.

With Java 21 and the Firebase CLI on PATH, run `npm run test:rules` to start
Auth, Firestore and Storage emulators with `demo-trustkeyper-rules`. Never use
the production project for those integration tests.

`npm run build:web` builds locally. To verify the preserved upload key without
building, run `.\scripts\build-flutter-aab.ps1 -VerifySigningOnly`. The full
signed-release script is documented in `README.md`; it checks the normal app's
certificate and the offline APK's separate package/no Internet permission.
None of these commands deploys or installs an app.

Build 46's prior ledger records 420 Flutter, 257 backend and 51 emulator tests.
These historical counts do not certify every design, live OTP, payout or
lifecycle. Follow `docs/ios-macos-setup.md` for current cross-platform testing and
`docs/product-requirements-coverage.md` for remaining acceptance. Use designated
accounts and harmless fixtures; preserve the original phone app.
