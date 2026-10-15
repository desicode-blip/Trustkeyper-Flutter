# Isolated Android UI-test app

This is a separate debug application named **TrustKeyper UI Test**, package
`com.trustkeyper.mobile.uitest`. It must never replace the live package
`com.trustkeyper.mobile`. It is not a complete app or a release candidate.

Build 28 adds login persistence/splash recovery to the normal app and callback
rescheduling/contact recovery. Its isolated APK keeps email disabled and has
no Internet permission. No ADB phone was detected during this build's checks;
no installation or physical acceptance is claimed. The last verified isolated
phone installation is build 27. See `docs/build28-testing-release.md`.

Initially installed with the user's approval on the connected CPH2707 phone on
7 October 2026; updated only in the isolated package to build 27 on 10 October.
The normal TrustKeyper remains build 18, last updated 8 October at 23:45:12.
No original-app data was cleared or original package replaced.

Build 27 adds owner manager-callback request, confirmed and missed-call entries
at the top of the gallery. Topic/time selection, saving a local request and
rescheduling a missed callback were exercised on the connected phone. Synthetic
manager contacts cannot dial or message. The installed APK checksum matches
`C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build27.apk`. The normal signed AAB
is a different, Firebase-connected artifact; see
`docs/build27-manager-callbacks.md` for release evidence and backend test steps.

Build 26 adds interactive move-out checklist/deductions, returned-key attestation
and owner report scenarios. The phone checks cover selected offline interactions,
not real settlement or every-artboard acceptance. See
`docs/build26-move-out-audit.md` for its evidence and boundaries.

Build 24 adds interactive offline repair approval/completion/bill/tenant outcome,
registered role switching, and property-photo room selection/review/timeline.
Connected-phone checks exercise the room grid, synthetic stamped photo save,
actual pending status, tenant confirmation, bill PDF and owner role selection.
The installed APK checksum matches the archived isolated APK. Separate Firebase
checks cover normal phone authentication and private photo upload/download,
idempotency, cross-broker isolation and removal of temporary test records.
See `docs/build24-repairs-and-photos-testing.md` for the exact testing steps.

Build 23 adds **Payments · first payment layout only** and **Payments · choose
advance months only**. Native phone checks verify the first-month deposit and
total, selection of three unpaid months, scrolling through the agreement end
date, and an explicit no-checkout error when the offline Pay button is pressed.
These are layout fixtures, not gateway or Firebase payment tests. The separate
real-backend test guide is `docs/build23-test-payments.md`.

Build 22 adds interactive offline owner/tenant demo replies, changed-version
confirmation, and **Agreement copy · read and save demo PDF**. Full-demo reading,
two confirmations and the owner reply result were tested on the native phone.
The copy entry renders the actual synthetic PDF and saves it through the Android
file picker; the downloaded bytes matched the fixture exactly. It remains a demo,
not an externally signed original. A TEST PDF was saved in phone Downloads.
See `docs/build22-manual-copy-testing.md` for separate real-backend/admin testing.

## Safety

- Its entry point does not initialize Firebase.
- Google Services and Crashlytics configuration are not applied for this build.
- The test manifest removes the Firebase initialization provider and Android
  INTERNET permission. No live OTP, Firestore write, payment or upload is sent.
- Authentication/profile/approval screens are read-only visual previews, with
  clearly described fixture states. Property edits use an in-memory repository
  and disappear when the test process restarts.
- Call-us actions on interactive broker/property pages can open the phone dialer;
  they do not automatically make a call. Do not use them for visual testing.
- Incomplete downstream workflows display an explicit not-connected page, not a
  simulated success or fabricated payment/document result.
- Repair photo selection can read a local file or open the camera. Use synthetic
  TEST images only. Photo selection, report saving and viewing stay in memory;
  they do not send anything to Firebase. See `docs/build21-repair-photo-audit.md`
  for the separate production-backend checks and remaining repair-workflow gaps.

## Using it

1. Open **TrustKeyper UI Test**, not your existing **TrustKeyper** app.
2. Read the offline-test notice and choose a preview from the gallery.
3. Use the Android Back gesture/button to return to the gallery.
4. In **Interactive property journey**, add an address, size/direction if needed,
   rooms, floors, furnishing, parking and inventory. Save, review and continue.
5. The final page explicitly confirms only a local property test result; no real
   agreement is made. Return to the gallery and reopen the property journey to
   test selecting/editing the locally saved record.
6. In **Interactive agreement draft**, enter test owners/tenants, rent, exact
   shares, dates and separate brokerage amounts. Saving validates a private draft
   in memory only. The owner and tenant document steps now have interactive
   fixture upload/view/replace/delete controls and PDF review. Delivery remains
   pending. Restarting the app clears these records. Never enter real identity
   documents in this test app. Firebase progress saving is not exercised here.
7. In **Private documents · offline fixture**, select the test owner or tenant,
   add the labelled fixture, confirm its review and try view/replace/delete.
   This entry never opens the native picker or reads real identity documents;
   the file store is in memory and clears on app restart. **Take photo** returns
   the same labelled fixture rather than opening the native camera.
8. Open **Demo agreement · not for signing** to read the offline test agreement.
   A real draft can also open its demo preview after all required terms validate.
   Yellow fields are captured data; green fields indicate changes since opening.
   Copying requires confirmation and never creates consent or a signature.
9. Compare against the downloaded designs. Report the gallery entry and specific
   mismatch; the full screen/state coverage ledger still marks acceptance pending.

Build 20 adds **Owner dashboard · interactive offline fixture**, **Tenant
dashboard · interactive offline fixture**, and no-linked-home entries at the top
of the gallery. Explore every bottom tab, open a home or money record, then open
**Issues → Tell us a problem**. Choose a category, describe a TEST problem and
press **Send**. The report is added only to memory; it is not a live repair job.
The no-linked-home entries should show real empty states instead of fictional
properties or balances. Profile changes, collection, repair approval and
other unfinished actions are not simulated as successful.

Build 19 additionally provides **Recipient Aadhaar/PAN/bank proof · offline
preview** entries. These use the browser-recipient layout with pre-verified,
explicitly labelled fixture state. Camera/file selection can read local files;
use non-sensitive TEST files only. Sending changes only in-memory fixture state,
never Firebase. The build-19 audit records whether a new phone install occurred.

## Rebuilding

From `apps/flutter_app`, run:

```powershell
flutter build apk --debug --no-pub --target lib/ui_test_main.dart --dart-define=TRUSTKEYPER_UI_TEST=true
```

Before installation, inspect the APK's package name, label and permissions. It
must be `com.trustkeyper.mobile.uitest`, labelled `TrustKeyper UI Test`, without
`android.permission.INTERNET`. Do not install an APK whose identity differs.
The UI-test build is debug-only; release builds with this flag are rejected.

The current checked isolated APK is saved as
`C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build27.apk`. The standard
`build/app/outputs/flutter-apk/app-debug.apk` filename is shared between build
targets; always verify identity again after rebuilding. Never assume that a
normal debug APK is the isolated app.

## Validation evidence

Current build 27: analyzer clean, 231 Flutter tests, 163 backend tests and 31
actual emulator rules/integration tests pass. Isolated request/confirmed/missed
callback checks pass on the phone, and its installed APK matches the archive.
Firebase Hosting bytes match the final web build and five anonymous web routes
render without JavaScript errors. See `docs/build27-manager-callbacks.md` for
the exact evidence and limitations. Whole-app design acceptance remains open.

Historical build 23: analyzer clean, 177 Flutter tests, 92 backend tests and 19
emulator rules tests pass. The isolated APK has version code 23 and no INTERNET
permission. Its SHA-256 is
`624F52D0BD4FB2C5FFCA7C5DD2AD78CEC6C37F2E2AA0EF9C45C30D45BFB43C2E`.
Real Firebase checks verify TEST quote/order/retry/isolation separately from
offline phone layouts. Whole-app design acceptance is still outstanding.

Historical build 21: analyzer clean, 157 Flutter tests, 59 backend tests and 16
emulator rules tests pass. Private repair-photo upload/submission/viewing passed
the live configured-test-phone check, with temporary fixtures removed. The
isolated phone app exercised selection, keyboard submission, report opening and
photo zoom without live Firebase writes. See
`docs/build21-repair-photo-audit.md` for current limitations and release evidence.

Historical build 20: analyzer clean, 151 Flutter tests and 15 emulator rules tests
pass. Owner/tenant tabs, real keyboard layout, local issue submission and the
recipient upload chooser were checked on the connected phone. Separate live
Firebase test-account checks verified issue creation/read/isolation/forgery
denial and cleaned every temporary fixture. See
`docs/build20-design-and-device-audit.md` for coverage and artifact evidence.

Build 18 historical validation: analyzer clean, 132 Flutter tests, 34 backend tests and ten
emulator rules tests pass. On the phone, actual PDF rendering enables upload;
owner fixture upload/view/confirmed replacement/deletion and separate tenant
upload were exercised. Normal-app native camera/picker, live phone upload and
full-artboard acceptance remain outstanding. Separate authenticated live SDK
checks validate Firebase progress/storage and remove their temporary data.
Final hashes and device identity evidence are in `docs/build18-functional-audit.md`.

### Earlier build history

- Analyzer: no issues; 107 Flutter tests and 26 email OTP backend tests passed.
- Both isolated and normal-identity Android debug builds compile. Only the
  isolated package is installed for phone testing.
- Phone previews inspected: gallery, login, roles, broker home and agreement
  introduction (including scrolling to its final review stage). The property
  journey was exercised with a clearly test-labelled address, 2 BHK, semi
  furnishing, one fan and one light; the result remained local-only.
- The updated offline build opens the interactive agreement owner-count screen
  on the connected phone. Automated widget tests exercise two owners/two tenants,
  exact shares, term correction, separate brokerage and failed-save recovery.
  These checks do not constitute pixel-perfect acceptance of every design.
- The document-enabled build was installed only as `com.trustkeyper.mobile.uitest`.
  On-device fixture review/upload displayed **Uploaded · Not verified** and
  exposed replace/view/delete. It remained in memory, with no live upload.
  The original Play app is still version 2.0.0 build 15, last updated
  5 October 2026 at 10:44:31. The checked isolated APK SHA-256 is
  `54A24D2A44F15AAC575705D667474DE704A03AC4432AF7ED3955DC49EFD4494C`.
- The demo-enabled update was also installed only in the isolated package. The
  on-device preview shows the full non-signable warning, captured yellow fields,
  test owner/tenant contacts and exact amounts in words. No clipboard copy,
  participant approval, signing request or real payment was initiated.
- Reference screenshots, native captures and device screenshots live in the
  ignored `output/design-reference` and `output/ui-audit` folders. They are not
  whole-app visual sign-off or live-provider validation.
