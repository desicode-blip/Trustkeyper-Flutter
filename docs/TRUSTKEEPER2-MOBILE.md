# TrustKeyper staging mobile builds

The broker app uses `apps/flutter_app/lib/main_tk2.dart` on both platforms.
The new build keeps the existing TrustKeyper app ID `com.trustkeyper.mobile`.
It uses `trustkeyper-app-staging` and the staging website for owner and tenant
links. On iOS, the `tk2` scheme selects the new broker experience for staging.

## Aman and Claude on macOS

Use a clean checkout so the previous local Xcode edits do not conflict with
the shared scheme. From a directory where you keep projects, run:

```bash
git clone --branch codex/tk2-access-control https://github.com/desicode-blip/Trustkeyper-Flutter.git Trustkeyper-TK2
cd Trustkeyper-TK2
bash scripts/bootstrap-macos.sh tk2
open apps/flutter_app/ios/Runner.xcworkspace
```

Use Flutter 3.38.6 and the Mac tools listed in [iOS setup](ios-macos-setup.md).
The bootstrap restores the Dart lockfile and installs Pods. It downloads the
TK2 Firebase plist when Firebase CLI is installed and signed in to an account
with staging access. Alternatively, download the plist from Firebase Project
settings for `trustkeyper-app-staging` → Your apps → the iOS app for
`com.trustkeyper.mobile`. Save it
as `apps/flutter_app/ios/Runner/GoogleService-Info-TK2.plist`, then rerun the
bootstrap. Git ignores the plist.

In Xcode select the **tk2** scheme and your iPhone. Select the authorized
Apple Team for the Runner target with automatic signing, then press Run.
The scheme sets the app name, bundle ID, Flutter entry point and Firebase
reCAPTCHA callback. No manual changes to `Generated.xcconfig` are needed.

For a compile check without device signing, run this from `apps/flutter_app`:

```bash
flutter build ios --simulator --debug --flavor tk2 -t lib/main_tk2.dart
```

On the iPhone, test OTP with an authorized pilot number, then create a
synthetic listing, open its tenant link, book a visit, and confirm with the
tenant code. Test the owner invite and gate pass on the same staging backend.
Firebase staging allows verification SMS in all regions. For an owner abroad,
enter the full phone number including `+` and the country calling code.
This scheme uses the Firebase reCAPTCHA fallback. Silent verification via APNs
requires setup in the staging Firebase project for the existing bundle ID.

## Android App Bundle

Keep the verified upload key in the private signing directory or point
`TRUSTKEYPER_SIGNING_CREDENTIALS_FILE` to it. Copy
`apps/flutter_app/tk2_cloud.example.json` to the ignored `tk2_cloud.json` and use
the staging Firebase app settings. Get the Android client config for
`com.trustkeyper.mobile` from the staging Firebase project. Set
`TK2_FIREBASE_APP_ID_ANDROID` from the matching client’s `mobilesdk_app_id` and
`TK2_FIREBASE_API_KEY_ANDROID` from its API key. Use the staging bucket and
`https://trustkeyper-tk2-staging.web.app/` for shared links.

```powershell
./scripts/build-flutter-aab.ps1 -Tk2Staging
```

The script verifies the upload certificate and builds the TrustKeyper staging bundle.
Use the existing **TrustKeyper → Internal testing** track in Google Play Console.
An AAB is for distribution through Google Play or for generating device APKs
with `bundletool`. If Google Play re-signs the app, register the public Play
app-signing certificate fingerprints on the staging Firebase Android app before
testing OTP from that track. This staging app uses test bookings, and real
payments and agreement signing are outside the pilot.
