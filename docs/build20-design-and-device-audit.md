# Build 20 — design coverage and connected-device audit

Date: 9 October 2026. This is a progress/evidence report, not full-app completion.

## All design exports accounted for

The approved reference archive contains 18 HTML exports and 438 artboards.
Exports 13 and 14 explicitly contain discarded designs: 44 historical boards.
There are 394 active references, including alternate layouts and error states,
not 394 independent app routes. Downloads no longer contained the original
HTML files at audit time; `D:\Trustkeyper\Artifacts` was empty. Cached extracted
HTML, screenshots, fonts and export hashes remain in `output/design-reference`.

Run `node scripts/audit-mobile-coverage.cjs` to regenerate the complete
`output/design-reference/implementation-audit.csv` and JSON counterpart.
Every row includes its original title, component evidence, route, limitations
and source hash. Counts are **186 partial, 200 missing, 8 deferred and 44
archived**. Partial means some relevant implementation exists, not that the
artboard is finished. **Zero artboards are certified pixel-perfect.**

## Implemented in this change

- Normal owner and tenant routes now use the designed branded header, role
  badge, floating bottom navigation, home cards and record details instead of
  generic linked-record lists. Owner tabs: Home, Properties, Money, Issues,
  Profile. Tenant tabs: Home, Pay, Issues, Profile.
- Firestore-scoped records populate these views. Empty/loading/error/retry
  states replace invented money, homes or contacts. Scheduled payout values are
  read from actual dated records, not inferred from gross agreement rent.
- A tenant's personal share requires a unique matching UID or verified phone
  on an agreement that explicitly includes that UID. Missing/ambiguous shares
  are never guessed by dividing rent. Agreement totals are clearly distinguished
  from paid funds and personal payouts.
- Both participants can submit an editable text repair report for a linked home,
  select the problem category, see validation/retry and read the saved report.
  Firebase creation is transactional and copies the agreement's participants
  and property address rather than trusting client-selected recipients.
- Device testing caught clipped category chips. They were replaced with
  responsive icon tiles; validation and Send now stay in a keyboard-safe footer.
  The old hard-coded owner/tenant preview dashboards were removed entirely.
  Production account changes rebuild the workspace and clear old session data.
- Issue rules enforce agreement linkage, allowed fields/category, initial open
  status and server timestamps. Participants cannot invent repair approval,
  costs or completion. Existing admin photo-to-repair creation is preserved and
  regression-tested. Admins retain their existing repair processing capability.
- Recipient uploads now have working front/back selection tiles and a camera/
  file choice sheet. Files are previewed before selection. Remove, replacement,
  required-page gating and separate server-confirmed send remain functional.
- Broker document-link sharing now uses selectable channel cards. WhatsApp/SMS
  open real composers; copying does not claim delivery. Email stays unavailable
  as requested. The capability-bound backend from build 19 remains in use.

## Tests and deployment scope

- Flutter analyzer: no issues. The final full suite passed **151 tests**,
  including the narrow-screen keyboard regression. The targeted workspace
  suite passed 11 tests.
- Rules emulator suite: **15 passing tests**, including repair creation,
  forgery/unauthorized reads and preserved admin repair creation.
- Layout checks exercise 440, 363 and 320 logical pixels, all participant tabs,
  and 1.3 text scaling on narrow layouts. Recipient OTP/privacy and incomplete
  Aadhaar/failed submission regressions remain covered.
- The updated issue rules and normal Flutter web build were deployed to Firebase
  project `trustkeyper`. Hosting is `https://trustkeyper.web.app`. A fresh anonymous
  browser checked the invalid document-link guard at 363 logical pixels without
  uncaught JavaScript errors. The hosted JavaScript SHA-256 matches the local build:
  `7257aceebe6b4d3f21f5ef41e8b2ae5bbc37db7955a8cd2bb1a079e65e96aee4`.
  No functions, DNS, Vercel or GitHub changes are part of this change.
- Live production-project acceptance used only the already-configured test
  phones and uniquely named temporary fixtures: real Firebase phone verification,
  transactional issue creation, owner read, server timestamps, unlinked read
  denial and approval/cost/recipient forgery denial passed. Every fixture was
  removed. Existing user records and account roles were not changed.

## Connected phone

The authorized USB device is an OPPO CPH2707, 1272×2800 at density 560,
with system font scale 1.0. The separate **TrustKeyper UI Test** package
`com.trustkeyper.mobile.uitest` was updated to version 2.0.0, build 20.
Its APK manifest was checked before installation: no Internet permission.
Fixture screens use memory only; their example balances are not live data.

The installed normal Play package `com.trustkeyper.mobile` was build 18 before
the audit and is deliberately not replaced, uninstalled or cleared. Testing the
new normal app requires publishing/installing the signed build-20 bundle through
Play internal testing; the separate UI-test app cannot test live OTP/payments.

Owner Home/Properties/Money/Profile and tenant Home/Issues navigation were
checked on the phone. The final tenant issue form was exercised with the real
phone keyboard: category labels and Send remained visible, the offline report
received an acknowledgement and appeared in the issue list. The recipient
Aadhaar front/back tiles, disabled incomplete submission and camera/file choice
sheet were inspected; the chooser was cancelled without reading personal files.
Captures and accessibility hierarchies are under `output/ui-audit/phone-*.png`
and `.xml`. The normal app remains build 18, last updated 8 October at 23:45:12.
Full device regression and exact visual acceptance across every artboard are
still outstanding.

## Checked build artifacts

- Normal release bundle:
  `C:\Users\ajayb\Downloads\TrustKeyper-v2.0.0-build20-design-updates.aab`.
  Package `com.trustkeyper.mobile`, version `2.0.0`, code `20`.
  Bundletool validation passed. The upload signing certificate matches Play:
  `94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7`.
  SHA-256: `44EB50896917BB4EBF56894BF3A07EB34AE87B8BA35F18B521AEABE89B14DFC9`.
- Installed offline UI-test APK:
  `C:\Users\ajayb\Downloads\TrustKeyper-UI-Test-build20.apk`.
  SHA-256: `24754A7B4E057DEC27DD94A54BC2A7D93EEF62EC61FA0F736B1A89EFFD74D94A`.
- Release mapping is archived in `output/ui-audit/build20-release-mapping.txt`.
  Build-time Crashlytics symbol upload was deferred; runtime reporting is not
  disabled. No Play release has been published by this change.
- This is a testable progress build, **not a complete production-ready app**.

## Remaining work — do not represent as completed

The ledger lists every outstanding reference. Important remaining groups:

1. Broker owner/tenant and review screens still need dedicated artboard layouts;
   manual bank/UPI entry and real beneficiary/QR verification are not implemented.
2. Owner self-onboarding/listing/plans/visits/manager handoff and tenant home,
   flatmate and share-change approval journeys need complete workflows.
3. Move-in/move-out photo checks, stamped camera evidence, meter readings,
   key OTP, notice, deductions/disputes and deposit refund are not implemented.
4. Real legal agreement consent, stamp paper, provider signing and signing-only/
   renewal remain incomplete. Demo terms never act as a signature or consent.
5. Payment collection, receipts, payout automation, pay-ahead, partial payment
   and late-rent notifications require verified backend/provider processing and
   the existing business/compliance sign-off before live money.
6. Photo repair attachments, owner cost approval, full profile editing/language/
   account deletion, notifications and exact admin desktop layouts remain open.
7. Email OTP and email document-link delivery are intentionally deferred.

These are implementation gaps as well as provider dependencies. A phone preview
or an existing generic journey entry does not close them.
