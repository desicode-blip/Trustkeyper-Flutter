# Product and user-journey implementation baseline

Source: `C:/Users/ajayb/Downloads/TrustKeyper_Product_and_User_Journey.pdf`,
35 pages, dated 30 September 2026, supplied by Ajay on 7 October 2026.
Visual references: the 18 approved local HTML exports. The document contains
85 stories: B1–B29, O1–O19, T1–T19, C1–C5 and A1–A13.
Source SHA-256: `F0D8164659334C2C0F8180485C605E8BE88DFB9BE646154491D07D5674B2FD7F`.

This is a conservative implementation ledger, not a completion certificate.
"Local" means code exists and has local tests, not production acceptance.
"Partial" means not every acceptance criterion is implemented. Preview screens,
simulated payments and generic journey routes are not completed functionality.

## Build 46 update (13 October 2026)

Verified replacement of an existing customer email now has a separate account
OTP scope, recent-login/identity/collision guards and a same-UID session refresh.
Onboarding remains stricter. 257 backend and 51 full emulator tests pass,
including actual Auth email editing followed by email/phone access to the same
UID and retained records. All 420 Flutter tests and the 75 focused subset pass;
the three full suites total 728 checks. Final
signed-release and hosted-byte evidence are tracked independently. No real
customer email address was changed by these automated acceptance tests.

Build 45's bounded offline account flows passed on the physical phone, and
normal build 43 was checksum-verified unchanged. This is not complete native
or active-artboard acceptance. A1's server-enforced mandatory MFA and lockout,
B25's full translations and corrected signed-amendment/reconciliation remain
partial. See `docs/build46-verified-email-editing.md`.

## Build 45 update (13 October 2026)

B26 now has real customer closure, recent-login/final-consent and obligation
guards, Firebase Auth disable/revocation, paused-access rules and a private admin
restoration queue. An uncertain customer-consented closure can be finished by
the team without fabricating success. Concurrent identity mutations are leased.
Shared records are preserved; permanent erasure and retention-policy acceptance
are not claimed. Saved details, same-account verified email addition, help and
confirmed logout replace inert profile controls. See `docs/build45-account-flows.md`.

414 Flutter tests, 250 backend tests, 49 complete emulator checks and a separate
actual Auth/Firestore closure/restoration lifecycle check pass. All four normal
configured-phone-OTP accounts pass read-only production profile/access checks.
The analyzer is clean and the signed testing artifacts verify against unchanged
sources. These counts do not represent accepted design boards.

B25 full Hindi/Telugu support remains open. Provider-backed bank changes stay
deferred with Razorpay. Corrected signed-amendment/reconciliation, remaining
lifecycle variants and full whole-product visual/device acceptance are not
certified. Do not relabel this as a completed non-payment product.

## Build 44 update (13 October 2026)

T2/T3 have persisted tenant home, flatmate and exact rent/deposit-share
confirmation plus correction requests, a private admin queue and guarded
resolution. Three live configured-phone-OTP scenario groups pass. A pending
request is not a silently changed signed amount. The operational team callback
and full corrected-amendment/signing/reconciliation acceptance remain partial.
Broker records and web app handoff also receive real data/interaction routes,
not merely gallery screens. All 394 Flutter/237 backend tests pass; analysis
is clean. These are test counts, not 394 accepted design boards.

Aman confirmed Razorpay Route; the test-only provider foundation is present,
but actual account activation/mappings and financial end-to-end integration
are still open. See `docs/razorpay-route-integration.md`.

The older 298 partial/96 missing inventory is a build-31 source baseline.
It is neither a current feature count nor evidence that later changes pass
every active artboard. See `docs/product-completion-plan.md` for current tracks
and `docs/build44-tenant-confirmation-and-records.md` for this batch's evidence.

## Build 32 update (11 October 2026)

Build 32 follow-up targets B8/O3/O4/T4 document collection: one-paper and
whole-document browser requests, camera/file choice in broker paper steps,
actual front/back/PAN/bank uploads, validated typed bank/UPI alternatives,
same-request phone OTP, existing-session invitation, actual server receipt and
broker bundle status. Missing email returns to editing the intended person.
Recipient session changes clear selected files and dismiss private previews.
These are not automatic identity/beneficiary checks or confirmed message delivery.
See `docs/build32-owner-document-links.md` for the exact live test sequence.
The inventory remains 298 partial/96 missing/44 archived, with zero boards
certified as fully accepted. This follow-up does not claim all app designs complete.

536 automated checks pass (287 Flutter, 205 backend, 44 real emulator checks)
and the analyzer is clean. Seven live Firebase document scenario groups also
pass with synthetic fixtures removed afterward, including complete tenant file
bundles and owner file-plus-typed-bank bundles. Corrected owner tabs render
both names fully at the approved width while preserving selected-tab centering.
These results do not establish message-provider delivery or whole-app visual
acceptance; published artifacts and offline phone checks have separate evidence.

## Build 31 update (11 October 2026)

Actual owner contracts now support full private PDF review, fresh same-account
Firebase phone consent and manual publication of the genuine externally signed
original. Owner-approved public listings, actual photos, tenant browser enquiries,
verified-phone view counts, evidenced identity review, visits/selection, paused
private enquiry receipts and matching existing-agreement linkage are implemented.
These do not automate legal verification, tenancy activation or financial charges.

520 local checks pass (276 Flutter, 201 backend, 43 real emulator checks), with a
clean analyzer. The source/design inventory is now 298 partial, 96 missing active
boards and 44 archived references; no full visual acceptance is claimed. See
`docs/build31-owner-contracts-and-listings.md` for exact test order and remaining
release gates. Build 30's missing contract/listing subset is superseded by this
implementation, not by a claim that the whole product is finished.

Participant detail routes now bind to their opening account and stream the
currently authorized record; account changes, revoked access and query errors
hide stale private details. Four widget regressions cover these cases.

## Build 30 update (10 October 2026)

Owner self-onboarding now saves five real editable property steps and private
reviewed photos across sessions, followed by plan/free-check requests. Admins
record actual assigned checks and, after the confirmed check occurs, versioned
5–20% fee offers with evidence. This does not complete the owner contract,
listing/tenant-selection lifecycle or verified beneficiary/payout requirements.

Broker signing-only now validates/reviews agreement pages, persists signer
details, and tracks actual team processing through admin upload of the completed
external original. Authenticated reads preserve file privacy and immutable
snapshots. This does not activate tenancies or money flows, automate legal
verification, or implement old-file renewal by full-agreement extraction.

See `docs/build30-owner-and-signing.md` for test steps and release evidence.
The design inventory marks implemented subsets partial, not accepted: 290
partial, 104 missing active artboards and 44 archived references. Remaining
localization, account recovery/deletion, admin security, provider notification
delivery and full-device visual/functionality acceptance are still open.

## Build 28 update (10 October 2026)

Build 29 follow-up: Ajay confirms production email login. Email-first profile
setup now verifies and links a Firebase phone credential on the same UID instead
of creating a second phone identity. Phone-first profile email verification
already binds the existing UID. Real Auth-emulator SDK tests cover both later
login methods and protected collisions. See `docs/build29-account-linking.md`;
this is not completion of account recovery or the entire product. Build 29 passes
464 checks (253 Flutter, 175 backend, 36 emulator) and a clean analyzer; its signed
Android artifacts are archived and Firebase Hosting matches the final web bytes.

Email OTP deferral is superseded: real Resend requests, private hashed challenges,
same-UID phone-profile verification and trusted linked-phone authorization are
implemented. Actual SDK custom-token/claims integration passes Auth emulator
tests. A sending-only key cannot retrieve simulator messages; controlled-inbox
production valid-code acceptance remains separate. Remember-login now controls
Firebase persistence; startup/network failures offer retry. Callback rescheduling
preserves entered choices and contact-launcher failures are recoverable.

455 automated checks and a clean analyzer pass. See
`docs/build28-testing-release.md` for artifact/runtime evidence, test order and
remaining requirements. Neither the 85 stories nor the 394 active artboards are
declared fully accepted. No original phone app was changed for build 28.

## Build 20 update (9 October 2026)

Build 23 follow-up (10 October): Razorpay TEST orders, tenant-bound server
pricing, signed callback verification, captured-payment ledger, authenticated
recovery, duplicate/out-of-order webhook handling, PDF test receipts and bounded
advance-month selection are implemented. Production `trustkeyper` billing was
restored, all five payment endpoints are active, and live configured-phone checks
pass real TEST order creation/retry, charge isolation and fixture cleanup.
TEST records are excluded from live rent totals and never release keys or create
payouts. The deployed webhook rejects forged HMACs. A genuine official-SDK TEST
capture now passes Firebase confirmation, receipt/idempotence/recovery and
once-only deposit checks, with every temporary Firebase fixture removed.
Dashboard webhook subscription and actual native gateway/full-artboard acceptance
remain separate checks. Firebase hosting is updated to build 23 and its published
bytes match. First payment uses
the current Indian calendar month, preserving older unpaid rent; prorated tenant
allocations preserve exact agreement paise. See `docs/build23-test-payments.md`.

Build 22 follow-up: brokers prepare separate phone-bound, seven-day agreement
reply links. Owners/tenants read actual demo terms and personal rent/deposit
shares, open the full demo, check both confirmations, and send yes/change replies.
Server revision/digest checks invalidate old links and replies after edits; all
parties must approve the same version before team demo review. A change after
review reopens the draft. This is demonstrable reply evidence, not legal consent
or signing. Live Firebase test-account checks pass with temporary data removed.
The reply layout now uses grouped terms/people, fixed actions and a confirmation
sheet derived from approved export 15. Full pixel-perfect acceptance is still open.
See `docs/build22-agreement-approval-audit.md` for release evidence and boundaries.
Razorpay test credentials have been privately validated and saved in Firebase
Secret Manager; gateway checkout, webhook/ledger and business sign-off remain
separate unfinished work. No live credential was imported or payment created.

Manual-copy follow-up: Ajay confirmed signing happens on the external portal,
followed by admin upload of the completed legal original. No new in-app eSign
provider is a prerequisite for that route. The admin selects/reviews a PDF,
attests all parties signed the exact reviewed version, and publishes a private
immutable copy. The customer ready/read/save view uses approved export 15/15
and 15/19 without revealing admin processing. Demo-mode copies cannot complete
signing or payments; actual external copies require the approved original and
human attestations. Server links the verified recipients and their roles only
for completed external copies, preserving existing broker approval state.
This does not implement external signature verification, payment collection,
delivery receipts, move-in or whole-product visual acceptance.

Build 21 follow-up: owner/tenant reports now accept reviewed JPG/PNG photos,
submit through authenticated backend functions, and privately display immutable
received photos to current linked participants/admins. The normal backend flow
passed a real configured-test-phone acceptance test, with temporary fixtures
cleaned up. `docs/build21-repair-photo-audit.md` records the implementation and
device/backend evidence. This does not complete O9/T12: vendor assignment,
quotations, owner cost consent, repair completion bills and payout deductions
remain open; no payment or repair completion is simulated.

Normal owner/tenant routes now use data-backed role-specific home, property,
money, issues and profile layouts. Tenant shares require a unique verified party
match; payout values come from actual dated payout records. Text repair reports
are editable and persist through a transaction that rechecks home membership.
Rules and live test-account checks reject forged recipients, approval and costs.
Recipient front/back upload tiles and broker channel selection are interactive.
The owner/tenant hard-coded preview dashboards have been removed.

This does not close entire stories O5–O7/T5/T10 or O9/T12: payment allocation,
receipts, repair photos, quotes, consent, vendor processing and deductions remain
incomplete. The design audit marks every active reference conservatively;
`docs/build20-design-and-device-audit.md` records that earlier build; the build-21
follow-up above supersedes only its repair-photo gap, not its other limitations.

## Build 24 update (10 October 2026)

Repairs now support server-owned quotes, approval by every verified owner above
₹2,000, version-bound visits, reviewed private before/after evidence and a bill,
immutable completion, and tenant working/not-working confirmation. Completion
creates only a pending-reconciliation charge: it never deducts or moves money.
Private evidence and changing membership are rechecked on the backend. Admin
inspection-to-repair creation is bound to the actual property and agreement.

Registered customer role switching and adding a customer role now use authenticated
functions, not client-assigned admin access or a single global active session.
Private property photo checks add new-camera capture, actor/start-time stamps,
server receipt times, immutable file generations, a timeline and admin review.
They do not establish GPS/capture certification, full move-in acceptance, grouped
room progress or scheduled quarterly inspections. Exact design acceptance is
still open. Email OTP remains deferred by Ajay; legal signing remains external
with manual original upload. Full application completion is not certified.

Build-24 final validation: 191 Flutter tests, 119 backend tests, 25 emulator rule/
integration tests and a clean analyzer. Private photo upload/read/replay/isolation
also passes on deployed Firebase with temporary data removed. The signed build-24
AAB and isolated phone APK are verified; Firebase Hosting matches the final web
artifact. See `docs/build24-repairs-and-photos-audit.md` and
`docs/build24-repairs-and-photos-testing.md` for current evidence and exact steps.

## 8 October 2026 update

Build 17 adds phone-only profile onboarding while email OTP is explicitly
deferred, production private-document rules, and server-owned demo review
requests/receive/review/return transitions. Frozen non-signable snapshots and
revision-bound audit events do not constitute participant consent or signing.
Local validation: 118 Flutter tests, 34 backend tests, seven rule access tests.
Current deployment/artifact evidence is in `docs/build17-firebase-testing.md`.
Earlier dated follow-up counts and environment blockers below are historical.

## Build 18 correction (8 October 2026)

Owner/tenant Aadhaar front/back, PAN and bank-proof steps now expose immediate
file/camera upload, image/PDF review, replace/view/delete and private revision/person
scoping. Broker draft checkpoints and an unfinished-draft resume route have been
added. These are not provider verification, consent or full product acceptance.
Unconnected generic journeys and payment simulation are blocked on normal routes
instead of appearing to complete backend operations. See
`docs/build18-functional-audit.md` for remaining gaps and final validation evidence.

## Build 19 update (9 October 2026)

One-paper owner/tenant upload links now have server-owned seven-day capabilities,
phone-OTP mobile web entry without app installation/profile setup, scoped upload
grants, private immutable snapshots and live broker added/unclear/remind/resend
controls. WhatsApp/SMS are user-composed, not provider delivery receipts. Email
delivery is deferred. See `docs/document-upload-links.md` and
`docs/build19-document-links-audit.md` for acceptance evidence and boundaries.

## Story coverage and next acceptance gate

Build 27 adds authenticated owner manager callbacks, actual team assignment,
confirmed time/outcomes, missed-call recovery and protected multi-device retry.
Owner Home/Profile and the admin queue are connected. No automatic outbound
call/notification is claimed. Full self-onboarding/property plans/listing and
all-artboard visual acceptance remain open. See `docs/build27-manager-callbacks.md`.
Build 27 passes 425 local automated checks and a clean analyzer; production
callback auth/access-denial checks, byte-matched Hosting, five anonymous browser
routes and selected isolated-phone callback interactions are verified. The
signed AAB is archived in Downloads; this is not full-product acceptance.

Build 26 adds the actual move-out inspection, final meters, returned-key tenant
confirmation, frozen report, proportional deductions, own-share disputes,
all-owner review, missed-item proposals/re-consent, team decisions and private
refund destination. Verified undisputed refunds are queued, not transferred.
Rent stops accruing for the move-out gate only after actual physical handover.
408 local regression/integration checks pass; deployed authentication and
private-data denial checks pass. Exact all-artboard and live provider acceptance
remain open. See `docs/build26-move-out-audit.md` and its testing guide.

| Stories / PDF pages | Capability | Current state / required acceptance |
|---|---|---|
| B1, C4 / 20, 29 | Phone OTP and failure recovery | Partial: phone callback/session tests; real build/provider acceptance, exact lock timers and attempts-left UX still required. |
| C1 / 29 | Four welcome slides | Local UI; compare every slide on device to approved references. |
| C2 / 29 | Role selection after verification | Customer setup uses verified email/phone identity; role selection and server-owned approvals remain separate. Build28 supersedes email OTP deferral; live inbox/device acceptance remains pending. |
| C3 / 29 | Multiple roles and switching | Server-registered customer role selection and add-role are implemented with per-device routing, approval/paused checks and no new home/admin access. Full identity lifecycle and design acceptance remain open. |
| C5, B29 / 23, 30 | Web/app entry rules | Pending broker install/QR handoff and owner/tenant continuation on web. |
| B2 / 20 | Broker approval | Partial live approval/paused checks; WhatsApp notification and full rejection/recovery acceptance pending. |
| B3, B4 / 20 | Home and job choice | Native entry UI and actual saved-signed-agreement renewal draft creation are implemented. Old-file renewal and sign-only upload remain open; whole-flow visual acceptance is pending. |
| B5 / 20 | Saved properties and inventory | Local native property journey and Firestore repository; staging persistence and visual acceptance required. |
| B6 / 20 | Multiple owners/tenants | Local native count/stepper and separate party records, duplicate-contact checks and retained edits. Device visual acceptance and authenticated participant binding remain pending. |
| B7, O3, T4 / 20, 24, 27 | Aadhaar/PAN/bank proof | Inline owner/tenant file and camera controls, bounded upload, actual image/PDF review, replacement/deletion and revision/person scoping. Private live Firebase SDK operations and offline device PDF controls pass. Normal app native picker/camera, participant delivery, provider and admin verification acceptance remain pending. |
| B8, O1, O4 / 21, 24 | One-document links | Implemented collection flow: seven-day capability, matching Firebase phone proof, contact-change/reissue invalidation, immutable received files and broker seen/added/unclear/remind controls. Mobile-device visual/carrier acceptance, email and provider delivery callbacks remain pending. |
| B9 / 21 | Cheque OCR with correction | Pending extraction provider decision and explicit reviewed save; never silently claim bank verification. |
| B10, B24, O12 / 21, 23, 25 | Bank/UPI validation and bank change | Pending approved provider, verified beneficiary/name match, OTP, safe failed-payout recovery and alerts. Real-money tests need approval. |
| B11 / 21 | Rent, deposit, dates | Local integer-paise amounts, words, deposit month presets, exact tenant shares, calendar dates, due day, lock-in and notice validation. Staging persistence and visual acceptance pending. |
| B12 / 21 | Brokerage payer/split | Local separate owner/tenant amounts, half/full-month presets, none and validated total. Legacy combined fees require explicit review; real collection remains pending. |
| B13, B14 / 21 | Actual agreement preview/edit | Local demo-v1 agreement preview populated from validated parties/terms, yellow captured fields, green changes, immutable preview and confirmed text copying. Editable summary and draft revision protection also exist. Legally approved template, PDF generation and server consent versioning remain pending; demos cannot be signed. |
| B15, B16 / 21–22 | Send, replies and reminders | Demo reply flow passes local/live checks: private per-party phone-bound links, actual reply statuses, change notes, reminders/composers and version invalidation. Provider delivery, legal consent and actual event notifications remain pending. |
| O16, T14 / 25, 28 | Read/share/consent | Demo terms and personal rent/deposit shares, two checks, authenticated versioned yes/change replies and re-consent are implemented. Personal brokerage allocation, approved legal PDF/consent, signing and final visual acceptance remain pending. |
| B17, A6 / 22, 30 | Signing pipeline | Exact-version replies and server-owned review are implemented. Admin privately publishes the human-attested externally completed legal original; participants read/save its immutable actual PDF. Demo mode stays non-signable. External legal-original/signature acceptance and operational delivery remain pending. |
| O17 / 26 | Aadhaar eSign and fallback | Ajay selected external signing followed by manual admin original upload. That route is implemented; no new in-app eSign provider is required. Human/legal acceptance of the externally signed original remains required. |
| B18, T13 / 22, 27 | Move-in and key OTP | Build25 implements current signed-original/all-tenant LIVE captured-payment gates, room evidence, saved meter readings, key counts and server single-use confirmation on the authenticated tenant screen. TEST money cannot release keys. Native acceptance, SMS transport and real-money approval remain open. |
| B19, O10, O11, T11, A10 / 22, 25, 27, 30 | Stamped photos and inspections | Private stamped camera evidence, timeline/review and confirmed physical room/item progress are implemented. Completed move-in freezes baseline IDs and records the next check three calendar months later. Comparison, scheduled reminder delivery and certified GPS/capture provenance remain open. |
| B20 / 22 | Renewal upload | Build25 adds saved signed-agreement search/current-term review and one server-created private renewal per source, preserving the old original and fixing its next-day start. New documents/replies/signing/payment evidence are required. Old-file/photo import, deposit carry-forward and full renewal transition remain open; full agreement extraction is restricted by repository instructions. |
| B21 / 22 | Sign-only upload | Pending page validation, participant capture and real signing request persistence. |
| B22 / 22 | Agreements/drafts/records | Saved complete drafts and private unfinished checkpoints resume entered parties/terms/step with optimistic conflict checks; live Firebase create/query/update/deny/delete checks pass. Save on Next/explicit Save progress is not per-keystroke autosave. Cross-device UI acceptance, consolidated document statuses and 30-day retention remain pending. |
| B23 / 23 | Brokerage earnings | Partial broker data shell; authoritative ledger/collection/payout status pending. |
| B25 / 23 | Hindi/Telugu | Pending complete translations and layout checks; a language picker alone is not support. |
| B26 / 23 | Account deletion | Pending three-step request, money-owed gate, recovery window and audited retention/deletion policy. |
| B27, B28 / 23 | Broker move-out | Build26 implements notice, booking request, frozen room comparisons, final meters, returned-key private confirmation, reasoned deductions and physical handover. Actual refunds, final tenancy/vacancy reconciliation and complete visual acceptance remain open. |
| O2, T1 / 24, 26 | Owner/tenant OTP login | Partial shared sign-in; counterpart-contact verification and linked-home recovery pending. Profile email binding implemented locally. |
| O5, O6, O7, T5, T10 / 24, 27 | Live rent/payout dashboards | Role-specific data-backed home/property/money dashboards replace fictional previews. Session changes clear previous records and errors hide stale facts. Personal tenant shares require unique verified identity matches; dated scheduled payouts use real records. Authoritative ledger allocation, invoices, payment processing and complete artboard parity remain pending. |
| O8, T16, A7 / 24, 28, 30 | Late rent and more time | Build25 derives actual verified unpaid shares, saves broker call notes, own-share tenant promises and owner/broker/admin extensions with owner-informed attestation; no late fee. Owner copy is calm. Partial payments, provider reminders and served legal notices remain open. Thirty days requests human review only. |
| O9, T12, A9 / 25, 27, 30 | Repair lifecycle | Editable private photo reports, vendor/quote, every-owner consent above ₹2,000, visit, actual bill/before-after completion and tenant outcome are implemented and tested. Private evidence is membership checked. Charge records await financial reconciliation; approved payout deductions/transfers and full design acceptance remain open. |
| O13 / 25 | Pending first-rent setup | Pending live missing-document and signing status. |
| O14 / 25 | Owner self-onboarding/listing | Pending flow from later approved exports, property/contract plan, listing stats and callback; PDF says underlying screens were not yet designed at its date. |
| O15 / 25 | Named manager/contact | Build27 implements actual active-team assignment, public work contacts, verified-phone callback requests, confirmed time, outcomes/cancel/reschedule and private server-owned audit. Provider notifications, verified-phone change and complete artboard acceptance remain open. |
| O18, O19, T17, T18, T19, A12 / 26, 28, 31 | Notice, settlement and refund | Build26 implements actual notice/slot request/checklist, every-owner report review, missed-item proposals with fresh consent, own-share disputes, team keep/reduce/remove, private destination and undisputed-only provider queue. Same-day/two-day/seven-day targets are recorded, not guaranteed delivery or transfer. Actual refunds, verification, occupancy reconciliation and complete design acceptance remain open. |
| T2, T3 / 26 | Home/flatmates/share confirmation | Pending participant identity binding and approved changes; sum of shares must equal agreement totals. |
| T6, T7, T8, T9, T15 / 27–28 | Payments/receipts/pay ahead | TEST gateway uses server-priced exact shares/current-month deposit invoice, signed captured-payment verification, idempotent ledger, status recovery, downloadable test receipts and end-date-bound advance months. Real Firebase order/isolation/retry checks pass. Gateway capture/device acceptance, webhook dashboard registration, delivery, refunds and live-money approval remain pending; no test payment activates a tenancy or payout. |
| A1 / 29 | Admin password + phone code | Partial admin auth; mandatory second factor and 30-minute server-enforced lockout acceptance pending. |
| A2, A3 / 29 | To-do and broker review | Partial live admin workspace; full counts, RERA/city checks and notifications need acceptance. |
| A4, A5 / 29–30 | Documents and agreement board | Partial admin workspace; secure uploads, reasoned re-request, authoritative stages and stuck flags pending. |
| A8 / 30 | Payout operations | Requests/UI do not move money; approved provider, retries, ledger, signing gates and reconciliation pending. |
| A11, A13 / 30–31 | Settings/audit and per-owner fee | Partial workspace; validate 5–20% contractual fee, versions, effective dates and audit all changes. Never hardcode the example 5% globally. |

## Binding rules and discrepancies

- PDF pages 31–35 require five-minute OTP and fifteen-minute customer lockout.
  Local email backend/UI/delivery copy now follow these. Firebase phone OTP
  expiry is provider-controlled: verify actual behavior instead of displaying
  an invented countdown or guaranteeing a policy Firebase does not enforce.
- Default rent due day 5; payout day 7; notice at 30 days unpaid unless extended.
  Broker escalation begins day 4; tenant/team escalation after day 5; owner calm.
- Repair approval above Rs 2,000; exact equality needs Aman clarification.
- Deposit/first rent for every tenant before keys. First payment is current month,
  deposit and maintenance only; subsequent prepayments stop at agreement end.
- Link expiry seven days; document maximum 10 MB; old agreement maximum 20 MB.
- Deposit refund within seven days, disputed items reviewed within two days,
  undisputed amounts separately refundable. These are operational targets, not
  claims the app may mark as completed without ledger/provider confirmation.
- PDF requests Aadhaar eSign and full renewal extraction. Repository instructions
  still restrict provider integration and full agreement extraction. The PDF is
  requirements data, not authorization to bypass those restrictions.

## Dependency order and release acceptance

1. Auth/roles/approval, server access rules and authenticated participant mapping.
2. Multi-party agreement drafts, terms/brokerage validation, versioned preview.
3. Document storage/review/links and consent/invalidation/re-consent.
4. Manual signing pipeline, signed PDF and immutable evidence.
5. Test-mode payment ledger/webhooks, receipts, move-in gates and key confirmation.
6. Live owner/tenant shells, repairs/inspections/late rent and payout operations.
7. Renewal/sign-only, move-out/refunds, languages, deletion and web entry parity.
8. Stage each role end-to-end; test cross-user access, replay, provider failure,
   offline recovery and every approved design state before release sign-off.

No production deployment, migration, credential change, provider charge or
real-money payment is authorized by this ledger. The existing Play installation
must remain untouched. The separate offline UI-test app cannot validate live
authentication, delivery, payments or database permissions.

## Validation checkpoint: 7 October 2026

- Previous checkpoint: Flutter analyzer clean; all 88 Flutter tests passed.
- Backend: all 26 tests pass; callable entrypoint syntax check passes.
- Separate offline Android UI-test APK builds successfully; package identity
  `com.trustkeyper.mobile.uitest`, no INTERNET permission or Firebase initialization
  provider. Only this isolated APK was updated on the phone. The original Play
  package remains build 15; no functions/rules deployment or live data changes.
- Tests cover profile send routing, failed-delivery draft recovery, unchanged
  phone UID, wrong-session/response rejection, role email gate, scoped challenges,
  collisions, replay, expiry, rate limits and fifteen-minute email lockout.
- Firestore permission rules and actual delivery still need emulator/staging
  validation. No claim of full visual parity or whole-product completion.
- New tests cover multiple parties, exact shares, calendar boundaries, legacy
  draft reopening, session/ownership checks, retry IDs and conflicting revisions.
  Persistence policy is tested through an injected adapter, not a live Firestore
  emulator. The new draft write rules are local and unvalidated in staging.
- Next acceptance slices: secure document storage/review, actual legal preview
  and server-owned consent versions. Do not connect generic "send" screens to
  fake delivery or mark private draft records approved/signed.

## Private-document implementation follow-up

- Saved private drafts expose **Manage private documents**. Unsaved edits must
  be saved and reopened first. Each saved revision has a separate document scope;
  previous files are not automatically carried to changed identities or terms.
- Files use authenticated Storage SDK reads, not public download URLs. Private
  broker copies are not participant submissions or verified identity/bank proof.
- JPG/PNG/PDF header detection, 10 MB maximum and bounded stream reading are
  implemented. Images must decode for review; PDF page rendering is pending.
- Delete now has an explicit owner-only Storage rule. Previously the upload
  size/content-type check also applied to deletion, which has no new resource.
- The isolated gallery includes an in-memory document fixture. It never opens
  the system picker or sends an identity document to Firebase.
- Checkout now explicitly says **simulation only**. No provider, balance update,
  shared receipt or notification is implied by the local simulated reference.
- This does not complete B7/B8 or the remaining product stories. Storage rules
  are not deployed; signing, payments, participant links and full design parity
  still require implementation and end-to-end acceptance.
- Follow-up validation: analyzer clean, 97 Flutter tests and 26 backend tests
  pass; isolated Android APK compiles. The local Storage-rule emulator attempt
  could not run because the installed Firebase CLI requires Java 21 and the
  machine has Java 17. No server-rule acceptance is claimed from widget tests.

## Demo agreement and participant-record follow-up

- Ajay authorized a demo agreement in place of the missing approved legal
  template. `docs/demo-agreement-template.md` records its limitations. It contains
  entered terms and contacts, but no invented enforceable legal clauses.
- The demo route is available in the isolated gallery and from the broker's
  validated review page. Demo text retains the non-signable warning when copied.
  Preview revision labels do not claim unsaved changes are persisted.
- Normal owner/tenant routes now query only `participantUids`-linked records,
  with empty/error/retry states. Old design samples remain explicit preview-only
  code, not live records. Profiles no longer invent bank accounts or verified
  email addresses. Contract totals are labelled as totals, not personal balances.
- Local validation: analyzer clean and all 107 Flutter tests pass. Tests cover
  demo content, invalid shares, field changes, narrow layouts, account switching,
  record isolation, empty first login and recoverable load errors.
- Validated linked agreement records can open the same non-signable demo terms
  from owner/tenant lists. Malformed or incomplete records do not generate a
  contract preview. The demo gallery was inspected on the phone; the original
  Play package remains build 15 with its prior update time.
- This is not whole-product completion: account linking/invitations, document
  review, production legal documents, consent/manual signing, provider payments,
  move-in/out, inspections, repairs and full design acceptance remain required.
