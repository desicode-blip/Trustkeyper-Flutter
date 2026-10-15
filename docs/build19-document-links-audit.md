# Build 19: document-link implementation audit

Date: 9 October 2026. Worktree: `flutter-firebase-migration`. No GitHub commit,
push, Vercel deployment or website DNS change is part of this increment.

Implemented: broker per-paper requests and reminders; phone-verified owner/tenant
mobile web uploads; scoped server grants; immutable private received copies;
live broker statuses, viewing and unclear-copy replacement. Recipients do not
install the app or complete signup/profile onboarding. Email delivery remains
deferred. See `docs/document-upload-links.md` for the exact test sequence.

## Validation recorded during implementation

- Flutter: 140 tests passed; analyzer reports no issues. Test output is
  `output/build19-flutter-tests.log` and `output/build19-analyze.log`. Recipient
  preview confirms selection with **Use this file**, not a fictitious immediate
  upload; the separate **Send to broker** step commits the received copy.
- Backend: 47 unit tests passed, including link/expiry/contact isolation,
  phone-provider proof, scoped slots, submission retries, and snapshot integrity.
  The real Storage-copy check exposed loss of the MIME field when copy metadata
  was supplied. Finalization now explicitly preserves MIME and rejects incomplete
  manifests; a regression test covers this before marking anything received.
- Firebase emulator: 14 Firestore/Storage access tests passed. Admin access to
  legacy document requests cannot write this separate request collection.
- Firebase deployment login was renewed by Ajay. Rules/indexes and all five
  document-link callable functions were deployed to production `trustkeyper`,
  region `asia-south1`. The two existing agreement-review functions were updated.
  Runtime object access is constrained to `brokerDocumentRequests/`. The Firebase
  Storage service agent received the cross-service role needed to evaluate its
  Firestore-backed rules. Callable transport is reachable; business access is
  still enforced by the server and rules, not public IAM membership.
- Live configured-test-phone acceptance passed: anonymous invitation without
  files, wrong-phone denial, secret/metadata isolation, missing Aadhaar side
  rejection, both sides received, idempotent completion, temporary-upload
  removal, private token-free snapshots, byte-for-byte broker viewing, live
  status query, unclear reason, reminder stability, old-link invalidation,
  tenant PAN and owner bank-proof scope. Only explicitly labelled temporary
  fixtures were written; all their records, audit events, secrets and objects
  were removed. Evidence: `output/build19-live-links.log`.
- Normal web build was deployed only to Firebase Hosting. The hosted
  `main.dart.js` SHA-256 matches the local normal release build; actual PDF WASM
  asset returns HTTP 200 with `application/wasm`. An invalid private-link route
  renders its recovery page at 440 × 956 with no uncaught JavaScript errors,
  rather than requiring app-role signup. Evidence: hosting/browser check logs.
- ADB detected no connected devices in this turn. No normal or UI-test phone
  package was installed, cleared, force-stopped or replaced.
- Offline browser fixtures exercised Aadhaar/PAN/bank entry at mobile dimensions
  and disabled incomplete submission. A real browser picker selected and previewed
  a labelled test PNG; selection did not submit it, and removal disabled sending.
  These cached fixture captures predate the final preview-label/footer adjustment;
  the final adjustment is covered by Flutter tests, not claimed as a new native
  capture. The offline fixture never sent anything to Firebase.

## Android testing artifact

- Signed normal Android bundle: version `2.0.0`, version code `19`, package
  `com.trustkeyper.mobile`. This is not the offline UI-test entry point.
- Download: `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build19-document-links.aab`.
- SHA-256: `528E689DE34D26FB0F098C81C163DF15DF2082E8F95FDBDB20A3FFEC40A88343`.
- Bundletool validation passed. Upload-certificate SHA-1 matches Google Play's
  expected `94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7`.
- Repeated network/DNS failures interrupted the Crashlytics build-time mapping
  upload. This build explicitly defers that step, not runtime crash reporting.
  The mapping is archived at `output/build19-release-mapping.txt` for later
  upload. No successful symbol upload or fully symbolicated release is claimed.
- An AAB is a Play publishing artifact, not an installable APK. Upload it to the
  intended internal-testing release, then install through the tester Play link.
  The agent has not published a Play release or replaced the phone app.

## Remaining product scope

This is a feature increment, not certification that all 85 product stories or
all approved screens are complete. Provider verification/OCR, true message
delivery callbacks, retention cleanup, participant dashboard binding, legal
consent/signing, payment and downstream property workflows remain separate
acceptance gates. Phone-browser camera/file picking and real-carrier SMS require
physical-device acceptance. Automated Firebase test-number authentication is
not proof of carrier SMS delivery.
