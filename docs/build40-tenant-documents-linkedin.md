# Tenant documents and optional LinkedIn — final build 43

## Design reference

This correction reads Aman's current Claude artboard, rather than relying on
the older downloaded export that omitted LinkedIn. The relevant pages are:

- 05 · Broker · Tenants, agreement details, brokerage: T5, T5b, T10, T11,
  TL1 and TL2. LinkedIn is a fourth detail, optional and skippable.
- 12b · Tenant web · Documents, photo checks, pay ahead: TW11, TD2, TD4,
  TD6 and TD5. The tenant sees the broker's request, Upload/Change controls,
  a LinkedIn profile dialog, and an optional skip.

The broker's tenant document page now includes LinkedIn Add/Send link,
waiting/reminder, saved/changed/deleted and skipped states. The recipient
tenant page uses the tenant-specific request wording and Upload controls.
Bank details explain their deposit-refund purpose. The three actual identity
and bank documents control document completion; LinkedIn does not block it.

## Persistence and access

LinkedIn entries are stored in the existing revision/person-scoped private
document-request collection. They survive closing/reopening the draft and
appear through the same broker subscription as document uploads. Broker
entry, recipient entry and an explicit skip are persisted, not local static
placeholders. A recipient upload requires the requested phone's normal
Firebase OTP session. Wrong phones cannot obtain grants. Neither files nor
LinkedIn submissions are included in anonymous request responses.

Both client and backend reject unrelated URLs and accept personal
`linkedin.com/in/` URLs, normalizing them to HTTPS and removing tracking
parameters. Tenant submissions produce the existing private broker update.
Deleting or replacing a LinkedIn request invalidates its previous capability;
other document requests stay unchanged. No LinkedIn file-upload permission
has been introduced and no Firestore/Storage rules are relaxed.

## Loading and selection recovery

The previous picker path awaited a fresh backend proof read before opening
the local camera/file chooser. A delayed connection therefore blocked the
picker and disabled the entire page. File selection now starts from the
verified recipient screen without that network round trip. The backend still
rechecks phone, revision, invitation and file scope before accepting an upload.

Request reads and OTP confirmation have bounded waits. Concurrent reloads
discard older results. Failed retries retain the original invitation and
selected details. An unresponsive file chooser can be cancelled, late chooser
results are ignored, and the busy indicator is released. Individual storage
uploads also time out and cancel instead of leaving an endless progress bar.

A healthy hosted build-39 baseline completed actual owner and tenant OTP
verification and file-picker opening with fresh/full-storage browser cases.
This did not reproduce an unconditional authentication failure. The build-40
regressions specifically cover stalled verification, stalled reads, actual
auth identity events, network-independent file selection and cancellation.
An unavailable network is reported truthfully with recovery rather than being
represented as a successful upload.

## Verification status

- 225 backend tests pass, including tenant-only LinkedIn, wrong-phone denial,
  normalized URLs, skip, broker-only editing and scoped deletion.
- Targeted render/recovery tests pass. Existing tenant render baselines are
  intentionally updated for the newly verified fourth detail; render goldens
  are regression evidence, not a certification of every product artboard.
- All 369 final Flutter tests pass, including auth/selection recovery and render
  regression tests. Backend tests total 225.
- Production callable/Hosting checks, signed Android
  artifacts and physical-device checks are recorded below when completed.

No real identity/bank document, real payment, real outgoing message, original
phone app/session, Git branch/commit/push, Play release, DNS or Vercel change
is part of this correction. Whole-product 100% acceptance is not certified by
these targeted checks.

## Final checking and build 41

Build 40's complete browser checks pass for both configured brokers: twelve
normal phone-OTP cases reach confirmed backend submission, including actual
image selection/review/upload, LinkedIn save and optional skip. Fresh and
read-only-storage contexts both pass, with zero runtime errors. All temporary
fixtures are removed. An interrupted earlier synthetic fixture is also
identified by its exact test marker and removed, without touching real drafts.
Five additional hosted routes and five startup/retry cases pass. Published
web asset hashes match build 40.

A final review catches two related LinkedIn delete details: its confirmation
must say profile rather than photo, and deletion must close the profile scope
even if it came from a bundled document request. Build 41 applies these
corrections without removing Aadhaar, PAN or bank receipts. The additional
backend regression confirms the remaining four required upload slots survive.
Build 42 additionally clears a pending picker when the invitation or verified
identity changes. Two additional regressions confirm this cannot leave stale
Cancel controls or strand the new invitation's loading state. The seven
focused authentication/selection regressions pass. Build 42 supersedes the
provisional builds 40 and 41 for authentication/selection recovery.

The connected-phone check then identifies contact text breaking across three
lines and the adjacent person tab clipping off the screen. Build 43 gives
contact details their own one-line width beneath the name/completion row,
centres both person tabs when they fit a narrow phone, and keeps the three
completed-document actions horizontal with full 44-point buttons. Four new
real-font regressions pass at 363.4 and 390 logical pixels. Existing render
baselines are updated for this verified layout correction. Final delivery
uses build 43, not the intermediate artifacts.

## Final build 43 acceptance evidence

- All 369 Flutter tests and 225 backend tests pass; Flutter analysis is clean.
- Each configured broker passes 12 live Firebase scenario groups and six real
  browser cases. Owner/tenant OTP, actual synthetic image selection/review/upload,
  confirmed backend receipts and LinkedIn save/skip pass with zero runtime errors.
  Fresh mobile and read-only-storage contexts pass. Both runs remove their
  temporary records and files. A new broker session restores the saved flow and
  every private upload update.
- Production Firebase Hosting is released. The four checked published assets,
  including `main.dart.js`, match the final local build byte-for-byte. The five
  affected document callables are deployed; their backend source is unchanged
  since the successful build-40 deployment.
- On 13 October, the connected OnePlus CPH2707 runs the separate build-43 UI Test
  app. Its installed APK SHA-256 matches the archive. Owner received, tenant
  waiting and tenant received screens are captured and visually checked. Both
  person tabs fit, owner contact text stays on one line, and completed actions
  remain horizontal. The fourth LinkedIn row is reachable by scrolling; Add
  opens its dialog, the profile field accepts focus and opens the keyboard, and
  Save/Skip are enabled. These are offline fixture checks, not native production
  authentication, upload or push-delivery acceptance.
- The original app remains version 37, with its unchanged update timestamp and
  installed APK SHA-256. It is neither updated nor uninstalled. Final fixes in
  the Android production app require installation of build 43 through the normal
  signed distribution/testing path.

The signed testing bundle is
`C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build43-testing.aab`.
SHA-256: `DD059DBEFAB1CADDEE05678BBD8107E3B0B88A87818F5F652A032CB4F082055D`.
The isolated offline APK is
`C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build43.apk`.
Its SHA-256 is
`764EBF8E2016FD73C7493C2EBD982F74D2B07200A09809FD9946BFCBE3D19F82`.
The source snapshot and Play upload signature are verified. Crashlytics symbol
upload is deferred; the release mapping is archived.

Detailed evidence is in `output/ui-audit/build43-artifacts.json`,
`build43-device-check.json`, `build43-live-broker1.log`,
`build43-live-broker2.log`, and `build43-published-byte-check.log`.
Screenshots include `build43-owner-complete.png`, `build43-tenant-waiting.png`,
`build43-tenant-complete.png` and `build43-linkedin-add.png`.
The shareable test guide is
`C:/Users/ajayb/Downloads/TrustKeyper-build43-testing-guide.md`.

Physical Android push receipt and full-product/pixel-perfect acceptance across
all artboards remain separate checks. This correction does not certify those
unperformed checks or a real-money launch.
