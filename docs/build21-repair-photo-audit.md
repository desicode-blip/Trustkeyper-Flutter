# Build 21 — private repair-photo implementation

9 October 2026. This continues the build-20 design audit; it is not whole-app
completion or pixel-perfect sign-off.

## Implemented

Reference `12/19` contains a working Add a photo control, not an illustration.
The owner/tenant issue form now provides camera/file choice, image preview,
confirmed selection, removable thumbnails and up to four JPG/PNG photos of
10 MB each. PDF or unreadable images are rejected. Files are selected locally
until Send; picking or previewing does not claim successful submission.

Normal submission uses `beginRepairReport` and `submitRepairReport` in
`asia-south1`. Firebase verifies the account is enabled and still belongs to the
agreement. A private upload grant expires after one hour, has four named slots,
and rate limits new reports to twenty per account/hour. The server verifies
image headers/size/type, copies the exact source generation into a create-only
private snapshot, strips download tokens and stores the linked participants,
property address and server timestamps. It then removes temporary uploads.

Retries retain the same report ID, text/category and selected photo payload.
Ambiguous failures lock editing until the same report is retried, avoiding a
second report or changed text after an unseen successful submission. Submission
is not acknowledged until the server returns the saved report ID. An expired
upload requires reopening the issue form. Authenticated staging access ends
after expiry; automated removal of abandoned uploads remains an operational
follow-up. The app never requests or shares staging download URLs.

Participants can open the actual report and privately view/zoom its submitted
photos, with loading, failed-read and retry states. The admin repair dialog also
opens the report photos. `readRepairPhoto` checks current membership and enabled
account status before and after fetching the exact stored generation, verifies
the bytes and returns image data, never a URL. Direct client reads of final
snapshots are denied, even for participants and admins. Participants
cannot overwrite/delete final snapshots; unrelated, unlinked or paused accounts
cannot view them.

Photo receipt timestamps describe submission, not verified camera capture dates
or proof of a completed repair. Uploaded photos are not stamped move-in evidence.
Vendor assignment, quotations, owner cost consent, bills and payout deductions
remain unimplemented; references `11/17`, `11/20` and `11/21` remain open.

The live upload test exposed Firebase Storage's two-Firestore-document limit,
which the emulator did not enforce. Staging rules now read only the enabled
profile and server-issued grant. The callable checks agreement membership when
issuing the grant and again when publishing a report. A removed participant
cannot publish/view a report, although their own still-enabled account can
finish writing its temporary slots until the existing grant expires. Private
photo viewing uses the authenticated callable instead of exceeding that limit.
See [Firebase's documented limit](https://firebase.google.com/docs/storage/security/rules-conditions#enhance_with_cloud_firestore).

## Validation

- Final analyzer: clean. Full Flutter suite: 157 passing tests, including actual
  image decoding before preview, cancelled selections, invalid files, immutable
  retry payloads and private viewing failures/retries. An invalid earlier PNG
  fixture was caught and replaced with the existing valid 16 × 16 test image;
  the final suite and live backend check were rerun, not marked passed early.
- Backend suite: 59 passing tests, including report identity, linkage, retry,
  rate limit, expiry, missing images, content validation and snapshot privacy.
- Rules emulator: 16 passing tests against the final two-document staging rules
  and callable-only final snapshots (`build21-rules-final.log`).
- Production Firebase acceptance passed with the already-configured backend
  test phone accounts: wrong-account denial, missing-photo publication denial,
  upload, idempotent submission, owner byte-for-byte viewing, removed-participant
  denial, direct-storage/overwrite/delete denial, token-free snapshot and removal
  of the submitted temporary upload (`build21-live-repair-photos-final.log`).
  Only uniquely named temporary agreement/report/file fixtures were created;
  they were deleted and existing account records left untouched.
- On the connected CPH2707, the isolated UI-test app selected a synthetic TEST
  image, confirmed its preview, kept Send usable above the keyboard, saved the
  in-memory report, opened its photo and enlarged it. That is device UI evidence,
  not an Android production authentication/submission claim. Camera capture
  itself remains untested; no personal file was selected.
- The rebuilt isolated APK is build 21, package
  `com.trustkeyper.mobile.uitest`, label `TrustKeyper UI Test`, with no INTERNET
  permission. Installation succeeded; the normal app remains build 18 with its
  original 8 October 23:45:12 update time. Final form layout and preview-copy
  captures use the `build21-*-final.png` filenames.
- The three production functions are ACTIVE. `readRepairPhoto` has concurrency
  one and at most three instances, bounding memory use for large image replies.
  Runtime Storage permissions are limited to repair upload/snapshot prefixes;
  no bucket-wide/public file access was granted. Its transport uses the same
  Firebase-authenticated callable setup as the document endpoints.
- Hosting deployment succeeded at `https://trustkeyper.web.app`. HTTP checks
  return 200, and the served `main.dart.js` exactly matches the final local build:
  SHA-256 `02C579D1949DABE404E2E3813E8C7C17018ECD1397D518ED50C1A7CF7BB4940B`.
  This is delivery/integrity evidence, not complete browser visual acceptance.

## Checked artifacts

- Normal signed release bundle:
  `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build21-repair-photos.aab`.
  Package `com.trustkeyper.mobile`, version `2.0.0`, code `21`.
  Bundletool validation passed. The expected Play upload fingerprint is verified:
  `94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7`.
  SHA-256 `C57D3ADFE8502744414845FBC5742FF48DEFA15A98E1D0B51FF3F37024A781F7`.
- Isolated APK, rebuilt and installed only in the UI-test package:
  `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build21.apk`.
  SHA-256 `AAA169B30AD45DB1BE56FE1D0C0A8E0F26B8B146A073557591D91151D70B67F6`.
  The final installed APK also completed selection, preview, keyboard Send,
  opening the saved local report and photo zoom. Its synthetic phone image was
  removed afterwards; the app was left in its offline gallery.
- Release mapping archived in `output/ui-audit/build21-release-mapping.txt`.
  Build-time Crashlytics symbol upload was deferred, not runtime reporting.
- No Play release was published and the installed normal app was not replaced.
  Upload this checked AAB to Play internal testing for normal Android/Firebase
  testing. The separately installed UI-test app cannot test live authentication,
  storage, payment collection or legal signing.
- This is a tested progress build, not a complete or production-ready release.

## Whole-app status

The design ledger covers all 438 reference boards: 394 active variants and 44
explicitly discarded boards. Current source coverage is 186 partial, 200 missing
and 8 email-deferred active references. None has final pixel-perfect acceptance.
Those are reference states, not 394 distinct app routes. Build 21 closes a
specific working-photo gap inside a partial repair flow, not these other gaps.
Signing/consent, payment collection/allocation, beneficiary verification,
move-in/out evidence, renewals, self-onboarding and other listed workflows still
need implementation and full visual/device acceptance. Real-money/eSign provider
setup and the required business decisions cannot be replaced with demo success.

## Manual test steps

1. In the normal internal-test app, sign in with a configured test owner/tenant
   account that has a broker-linked test agreement. Do not use real identity
   documents or real homes for this test.
2. Open Issues → Tell us a problem. Choose the test home and category.
3. Tap Add a photo, then Choose photo or Take photo. Use a non-sensitive TEST
   picture. Review it and confirm selection; this alone must not send a report.
4. Remove a thumbnail, select it again, then enter at least ten characters.
5. Press Send. Do not leave during submission. If connection fails, retry the
   same report instead of starting another one. Expect one saved reference.
6. Return to Issues and open that report. Its photo must load and enlarge when
   tapped. Sign in as the other linked participant and verify the same report.
7. In the admin panel, open Repairs → Manage → View reported photos.
8. A broker/account not included in that agreement must not see the report or
   read its private photos. Do not manually change participants to bypass this.

The separate TrustKeyper UI Test app exercises only memory fixtures, not live
Firebase submission. Its file chooser can read local files: select TEST files
only. Keep the normal installed app and its session untouched during device QA.
