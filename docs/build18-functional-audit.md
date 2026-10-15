# Build 18: functional audit and document-step correction

Date: 8 October 2026. Target: Firebase project `trustkeyper`.

This is a testing build, not a certificate that the complete product works.
The connected phone initially had the normal build 17 app. Agent installation
must target only the separate `com.trustkeyper.mobile.uitest` package. An offline
fixture result is not evidence that Firebase uploads, camera permissions or real
authentication work on the normal Play-distributed app.

## Corrected owner and tenant document steps

- Both agreement steps now embed the private document manager immediately,
  rather than displaying static Aadhaar/PAN/bank-proof rows and requiring a
  complete agreement before opening uploads.
- Aadhaar front, Aadhaar back, PAN and bank proof each support file selection,
  camera capture, review, upload, view, confirmed replacement and confirmed
  deletion. JPG, PNG and PDF are limited to 10 MB. Unreadable image/PDF previews
  cannot be confirmed as uploads.
- PDF review displays actual pages; it no longer asks for blind confirmation
  without showing the file. Uploading is not identity, PAN or bank verification.
- Files stay broker-private, separated by draft, pending revision and party ID.
  Changing a party's name/contact rotates that party's document identity, even
  when progress is saved before pressing Next. Old files are not silently shown
  as belonging to the newly entered person. Old files are not automatically
  erased by identity changes; retention/cleanup remains a separate requirement.
- For unchanged people when editing a saved draft, previous-revision copies are
  offered for explicit review and confirmed reuse in the next revision. A revision
  change does not silently label an old file as newly reviewed or lose access to it.
- Controls prevent advancing the wizard while a document operation is running.
  Failure is visible and does not report a successful upload or verification.

## Draft recovery

Agreement progress is saved under `users/{uid}/draftProgress/{draftId}` on Next
and through Save progress. It preserves the current party/step, incomplete raw
amount inputs, party IDs and the base complete-draft revision. Resume unfinished
drafts is available from the broker Agreements tab.

Only approved, unpaused brokers can read/write their own progress. Other brokers,
admins and anonymous users cannot read those private checkpoints. Version checks
reject stale-device saves. A reviewed agreement or a newer complete draft cannot
be overwritten by unfinished progress. Saving the complete draft removes its
checkpoint when possible; failed cleanup reports a warning and stale progress
cannot be resumed as an editable newer agreement.

This is checkpoint saving, not a promise that every keystroke is durably saved.
Use Save progress before leaving an edited form. Automatic expiry, 30-day
retention and Android camera process-death recovery are still pending.

## Remaining prototype audit

The shared guided-journey presenter used by renewal/sign-only, signing, move-in,
move-out, agreement consent, tenant setup, repairs, late rent and owner
self-onboarding was a local state machine. It retained file names rather than
uploading files and advanced through sample success states without backend writes.

Normal production routes now refuse those simulations and explicitly say the
workflow is not connected. Payment simulation is also excluded from the normal
payment route. This safety change is not implementation of those business flows.
Design preview mode, if explicitly instantiated, remains preview-only.

Still required before whole-app acceptance:

1. Authenticated participant binding, expiring one-document links, consent on an
   immutable agreement version, real delivery/reminder events and recovery.
2. Approved legal template, real PDF output and the manual admin signed-PDF
   fallback. Automated eSign integration remains subject to the recorded decision.
3. Approved payment/beneficiary integration, authoritative ledgers, rent shares,
   failed-payment recovery and refunds. No real-money or bank verification is
   simulated as complete by this build.
4. Real owner/tenant dashboards backed by linked agreements, repairs, inspections,
   move-in/out checks, key OTP, renewals and sign-only requests.
5. Role switching, full Hindi/Telugu coverage, account deletion/retention,
   notifications and exact visual acceptance against every active approved frame.
6. Email OTP remains deliberately deferred at Ajay's request. Adding upload
   controls does not change that decision or configure a Resend secret.

The detailed acceptance ledger remains `docs/product-requirements-coverage.md`.
No GitHub push, Vercel release, nameserver change, provider signing call or real
payment is part of this correction.

## Validation and artifact evidence

- Flutter analyzer: no issues. Final full run: 132 tests passed, none failed.
  The PNG review widget tests now wait for actual preview readiness, instead of
  racing the asynchronous decoder against a fixed short sleep.
- Backend: 34 tests passed. Firestore/Storage emulator: ten access tests passed,
  including new-draft transaction reads, private progress and stale/reviewed gates.
- Live `trustkeyper` SDK check: an existing Firebase test-phone broker saved,
  queried and updated owner/tenant progress, uploaded/read/replaced/deleted a
  valid non-sensitive PDF and deleted the progress. Another existing test account
  could not read progress or read/write/delete that broker's document. Stale
  versions and forged completion fields were rejected. All temporary test data
  was confirmed removed. No business agreement, real identity file, profile,
  test-code configuration, provider setting or payment was changed by this probe.
  See `scripts/verify-firebase-document-flow.cjs` and
  `output/ui-audit/build18-live-firebase.log`. Tokens and the test code are not
  written by the script. The Node harness resumes a real phone-issued Firebase
  ID token in FirebaseServerApp; it does not mint an admin/custom-token bypass.
- Phone: only the offline build 18 UI-test package was installed. All four
  inline owner slots accepted the labelled PDF fixture, including the fixture
  camera action; Next advanced to tenant setup. Standalone owner PDF view,
  replacement and deletion required confirmation, and the tenant's separate
  fixture slot uploaded successfully. Actual PDF rendering was inspected and
  the Upload button became enabled after viewer readiness. This caught and fixed
  a real callback bug not exposed by the Windows widget runner.
- Phone normal package remains `com.trustkeyper.mobile`, version 2.0.0/build 17,
  lastUpdateTime `2026-10-08 19:17:09`. Its data/session was not cleared or replaced.
  The offline APK is `com.trustkeyper.mobile.uitest`, version 2.0.0/build 18,
  without INTERNET permission or the Firebase initialization provider.
- Firestore rules deployed successfully to `trustkeyper`. Fresh release web
  assets deployed successfully to Firebase Hosting. Root and JavaScript/PDFium
  worker/WASM assets return HTTP 200; remote hashes match the fresh local build.
  `main.dart.js` SHA-256:
  `4FA44067892DEAC21C58A50315A8A67ACD6FCD9EEDCC81D2DD8B000CCDE3964A`.
  No functions, Storage rules or marketing DNS were changed in this increment.
- Final signed AAB passed bundletool validation, package/version checks and
  Google Play upload-certificate comparison. Package `com.trustkeyper.mobile`,
  version 2.0.0/build 18, 60,878,916 bytes. Upload SHA-1:
  `94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7`.
  AAB SHA-256:
  `AC1DE8966D2F3738E8C46FE3D47D2E7EB5EA5765D830C0079576EE2CBF34380C`.
  Matching copies: `output/releases/TrustKeyper-v2.0.0-build18-document-flow-fix.aab`
  and `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build18-document-flow-fix.aab`.
- Offline APK SHA-256:
  `EEA6E7D91BFE607508AE51C1B7F851AAA78125015B1D409A209172F05F0CC665`.
  File: `output/ui-audit/TrustKeyper-ui-test-build18.apk`.
  Screenshots: `build18-pdf-ready-fixed.png`, `build18-inline-owner-uploaded.png`,
  `build18-owner-pan-bank-uploaded.png`, `build18-tenant-document-uploaded.png`
  under `output/ui-audit`.

## Next acceptance checks

1. Upload the signed build 18 AAB to the existing Play internal-test app and
   install its update, preserving the current normal app account/session.
   An AAB is not directly installable like an APK. The agent did not publish
   this file to Play or install a normal debug replacement.
2. With an approved test broker and non-sensitive fixture, open an agreement's
   owner Step 2. Exercise native file selection and camera capture for all four
   slots, actual image/multi-page PDF review, cancellation, retry, view,
   replacement and deletion. Repeat on tenant Step 3. Never use real Aadhaar,
   PAN or bank proof during this acceptance check.
3. Save progress, leave, reopen through Agreements → Resume unfinished drafts,
   and verify the step, raw inputs and uploaded files survive. Use a second
   device to verify stale saves are rejected. Change a person's identity and
   confirm the old person's copies are not attached to the new person.
4. Test normal-app logout/account switching, network loss, oversized/unreadable
   files and camera background/process recovery. Review the remaining product
   ledger before whole-app testing; the blocked business workflows above are
   deliberately not reported as completed.
