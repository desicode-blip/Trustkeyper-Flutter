# Build 22 — versioned agreement replies

This is a progress build, **not a 100%-complete app or a production launch**.
It implements the working demo-reply portion of B15/B16/O16/T14 against approved
references 06/07–08 and 15/01–09, 15/17–18. The approved legal template and actual
signing take place externally; admin publishes the completed original from the
admin portal. Pixel-perfect acceptance is not
claimed.

## Implemented

- The broker's saved, unchanged draft opens **Send for approval · Demo only**.
  Each owner and tenant has a different private seven-day link. Copy, WhatsApp,
  SMS and reminders compose messages; they do not claim delivery receipts.
- Mobile web and the app can open the same link. The recipient verifies the
  exact contact through Firebase phone authentication without installing the app
  or completing a profile. This uses a separate Firebase auth instance and does
  not switch the broker's/default app session.
- Before matching phone proof, the endpoint returns only masked contact, role,
  broker name and expiry. Property, participants, amounts, version, digest and
  replies are withheld. Paused profiles and inactive brokers fail closed.
- Recipients see actual saved terms and their own tenant rent/deposit shares,
  read the full non-signable demo, and check both confirmations. Brokerage is
  explicitly labelled as a group amount until personal allocation is specified.
- Yes/change requests are authenticated, revision/digest-bound, server-timestamped
  and audited. Failed replies retain the exact operation and payload for retry;
  the UI never claims success on a failed/mismatched server acknowledgement.
- The broker sees live per-person **not opened / opened / said yes / asked for a
  change** states and actual change notes. Provider delivery remains unconfigured.
- Saving a new revision invalidates every old link and reply. New rounds reset
  everyone, retain previous evidence and highlight server-derived changed fields.
- Team demo review now requires every owner and tenant to say yes to the same
  saved version. A later change request reopens the demo for broker correction
  and stops review; resubmission requires a newly saved and approved revision.
- Secret capabilities and approval evidence are server-only. Brokers can read
  only their invitation status records and cannot forge approvals, rounds or links.
- The separate offline UI-test gallery contains owner, tenant and changed-version
  reply flows. Fixture replies stay in memory and cannot verify/send real OTP.
- Terms and owners/tenants use grouped bordered cards, compact amount/date rows,
  fixed reply actions and a two-check confirmation sheet based on approved export
  15. Demo warnings and group-brokerage labels intentionally avoid suggesting an
  approved legal contract or an unspecified personal brokerage split.

## Validation checkpoint

- Analyzer clean; full Flutter suite: **173 tests pass**.
- Backend: **80 tests pass**, including version invalidation, two confirmations,
  replay, changing after yes/review, proof isolation, expiry and contact changes.
- Firestore/Storage emulators: **18 tests pass**, including server-only secrets
  and evidence and cross-broker invitation denial.
- The three reply callables and the revised review gate are deployed to Firebase
  `trustkeyper`. The org-policy public-invoker restriction was recovered using
  the existing callable-transport configuration; Firebase identity and capability
  checks remain inside each endpoint. Firestore rules deployment passed.
- Live configured-test-phone checks pass: private read/proof isolation, replay,
  server-only evidence, exact-version replies, invalidation, re-consent, complete
  approval gate and change-after-review reopening. The verifier removed its exact
  temporary fixtures; no profile/auth configuration or real agreement was changed.
- Native-device acceptance and distributable builds are being verified separately.
  Local/backend tests alone are not native-device or full visual acceptance.

Logs: `output/ui-audit/build22-{analyze,flutter-tests,backend-tests,rules-tests}.log`.

## Manual testing

1. In the normal internal-test build, create/save a TEST agreement as the approved
   broker. Use configured test contacts, not real people or identity documents.
2. Reopen the saved draft, advance to its review page, and choose **Send for
   approval · Demo only**. Prepare links and copy each person's own message.
3. Open the owner's link in a separate browser/device. Verify the owner number.
   Reading a forwarded owner link with the tenant number must not reveal terms.
4. Open the full demo, return, select Yes, check both confirmations, then submit.
   Expect one demo reply and the broker's live **Said yes** status.
5. Open the tenant's link and verify the tenant number. Check personal rent and
   deposit shares. Ask for a change; enter a category and at least five characters.
6. The broker must see the change note. Save corrected terms as a new revision and
   prepare new links. Old links must fail, all replies must reset, and changed
   fields must appear in green. Both people must reply again.
7. Team demo review must fail while anyone has not agreed or requested a change.
   It becomes available only after everyone approves the exact saved revision.
8. Disconnect networking during a reply. Restore it and use **Retry same reply**;
   do not create another operation or infer success from a loading indicator.

## Remaining release gates

The design ledger still has **199 partial, 187 missing and 8 deferred active
reference variants**, plus 44 explicitly discarded variants. No variant has
final pixel-perfect acceptance. These counts are not distinct app screens.

Still required: authoritative multi-role/participant linking; approved legal
PDFs and external signing acceptance; bank/beneficiary verification;
Razorpay orders, signed idempotent webhooks, ledger, receipts and reconciliation;
move-in/key confirmation and stamped inspections; complete repair quotes/consent/
bills; late-rent promises and extensions; renewal/sign-only, move-out settlement/
refunds, owner self-onboarding, languages, deletion and full design acceptance.

Ajay confirmed **Razorpay** as the payment provider and authorized using the
private supplied PDFs. The test-mode pair was extracted in memory, successfully
authenticated with a read-only Razorpay request, and saved/privately checked as
`RAZORPAY_TEST_KEY_ID` and `RAZORPAY_TEST_KEY_SECRET` in Firebase Secret Manager.
This import did not log keys/PDF contents or copy them into source or app files.
No live-mode credential was imported, and no order, payment or charge was made.
Credential readiness is not checkout/webhook/ledger implementation. Ajay confirmed
external signing followed by manual admin upload; a new in-app eSign provider is
not required for this workflow. The demo must not become signable.
Email OTP/delivery remains deferred by the earlier explicit request.

## Manual signed-original workflow

- Based on Ajay's correction, signing is performed outside the app. The admin
  portal accepts the externally signed original, not an invented app signature.
- After all parties approve the exact saved version and team review is completed,
  open its admin record and choose **Upload completed agreement PDF**. Select
  **Externally signed legal PDF**, identify the approved original, review every
  page, and confirm all signatures and matching reviewed terms before publishing.
- Demo PDFs have a separate mode and remain non-signable; they do not mark the
  agreement signed, activate move-in, bind participant roles or confirm payments.
- PDFs are bounded to 20 MB, immutable, generation/checksum-bound and private.
  Final objects cannot be read directly by any client, including admins. Reads
  require server-authorized admin, owning broker or exact verified recipient proof,
  with access rechecked after download. Retry preserves the selected file/operation.
- The owner/tenant ready-copy view follows reference 15/15 and 15/19: confirmation,
  signed-PDF card, actual save/read actions and server-derived count/start date.
  It never exposes admin processing or claims unverified WhatsApp/email delivery,
  a payout, payment or signature-provider verification. External signatures are
  human-attested by the admin, not cryptographically verified by this software.
- Local validation passed. All three copy callables, updated link reads/replies
  and Storage rules are deployed to Firebase `trustkeyper`. Existing org-policy
  invoker restrictions were handled with the established callable transport;
  runtime bucket permission is limited to copy upload/final object prefixes.
- Live configured-phone checks passed actual admin review, private PDF upload,
  immutable publish/retry, exact verified-recipient bytes, outsider/direct-Storage
  denial and same-version reply evidence. The synthetic PDF used **demo mode**;
  external legal signature publication was not fabricated in production. All
  exact temporary data, PDF and isolated admin account were removed afterward.
- Normal build 22 AAB compiled, passed bundletool validation and matched the
  required Google Play upload certificate. File:
  `C:/Users/ajayb/Downloads/TrustKeyper-v2.0.0-build22-agreement-copies.aab`.
  SHA-256: `42344D8ED008DD186C200EF5B649BA2C138D0F883BE0C9F552149A7F29741B26`.
  Release R8 mapping is archived as `output/ui-audit/build22-mapping.txt`.
  Crashlytics build-time symbol upload is deferred. Native-device/web acceptance
  is still separate from signed bundle compilation.
- Firebase hosting deployment passed; the hosted `main.dart.js` bytes match the
  local build (SHA-256 `2187D4CB1DD9009DADB83717C959FE2D003F8C491CE51982B5BA1505CEEBD4C9`).
- Isolated UI Test build 22 installed on the connected CPH2707. Package identity,
  version and absence of INTERNET permission were checked before installation.
  Actual native PDF rendering passed (one real TEST page), native Save confirmed
  success, and the saved 599-byte PDF exactly matched the synthetic fixture.
  Owner reply was checked through full-demo reading, both confirmation checkboxes
  and the **You said yes** in-memory result. This is not a real legal signature.
- Normal phone package remains build 18, last updated `2026-10-08 23:45:12`;
  its data/session was not cleared or replaced. Offline APK:
  `C:/Users/ajayb/Downloads/TrustKeyper-UI-Test-build22.apk`, SHA-256
  `FB425546B9ECF1D910C26F73D297EABC6259F49D01471F5FA267AC4DDC8DD781`.
- Native screenshots/XML, saved fixture, deployment, live isolation checks and
  hash evidence are retained under `output/ui-audit/build22-*`. The native checks
  cover these flows only, not all 438 reference variants. Instructions are in
  `docs/build22-manual-copy-testing.md`.
