# Backend handoff – Broker "Onboard property" journey (staging)

For: the backend developer who will make this journey real.
Branch: `staging` (never `main`). App: `apps/flutter_app`. Backend: Firebase (Firestore, Storage, Cloud Functions in `functions/`, Node 22, ES modules).
Last app change covered: **Change 45** (2026-10-29). Website changes 46–56 are separate (see `website/`), not part of this handoff.

> One-line summary: the broker side of onboarding a house owner is **fully designed and built in the app**, but it runs on a **local, on-phone store with "TEST ONLY" buttons** that pretend to be the owner, our team and the e-sign provider. Your job is to replace every pretend step with a real backend, without changing the screens.

---

## 1. How to read this

1. Section 2 – what to run.
2. Section 3 – every change, one line each (details per change in `docs/CHANGELOG-staging.md`, which has a human part and an `AGENT RECORD` block per change).
3. Section 4 – what is real today and what is pretend.
4. Section 5 – the journey and its states (the state machine you must keep).
5. Section 6 – the data model, field by field (store this in Firestore as-is).
6. Section 7 – the backend work, as tasks with "done when".
7. Section 8 – client methods to swap for backend calls.
8. Section 9 – open decisions to ask Aman.
9. Section 10 – file map.

Related docs: `docs/AGREEMENT-TEMPLATES.md` (templates, placeholders, Drive plan), `docs/agreement-templates/README.md`, `docs/document-upload-links.md` and `docs/private-document-uploads.md` (the existing document-link system for rent agreements, which you can reuse).

---

## 2. Run and test

```bash
cd apps/flutter_app
flutter pub get
flutter analyze                                   # must say: No issues found
flutter test test/property_onboarding_test.dart test/agreement_filler_test.dart test/broker_property_test.dart
flutter test                                      # whole suite
```
- The whole suite has **39 old failures** (golden/pixel and old layout tests in `account_screens_test`, `broker_document_states_test`, `build44_design_test`, `design_layout_test`). They failed the same way **before** this work; none were added by it. Re-baseline the goldens separately.
- The onboarding screens show a **TEST ONLY** panel at the bottom of the house page. Use it to walk every state without a backend.
- Functions tests: `cd functions && npm test`.

---

## 3. All changes (app, staging)

| # | What changed (short) |
|---|---|
| 1–4 | Onboarding carousel redesign, dots + swipe, new illustrations, login back button / hero |
| 5–8 | Broker home: calmer layout, bottom nav as designed, "Continue" panel (drafts + bank), slim action buttons |
| 9 | **New: Onboard property journey** – Documents → Agreement → Signing → Ready |
| 10–13 | Fixed heading, floating-label fields, right keyboards, spacing |
| 12, 21 | "We know this owner" sheet (same owner, new house: reuses approved ID papers) |
| 14–15, 17 | Owner details: how many owners, choose how to reach (email / WhatsApp) first |
| 18 | Paper order; the contact used to ask is auto-approved |
| 19–20 | Months: "Other" option; more than 11 months shows "registered agreement" notice (not supported) |
| 22, 24 | Several owners: a tab per owner, each with own Aadhaar/phone/email |
| 23 | "Documents" wording, read full agreement, call our team |
| 25–27 | Fee: No fee, Decide on every deal, number box under the picked option, 3 groups incl. "days of rent every month" |
| 28–29 | One button on agreement start; "How does the owner pay you?" follows the fee type |
| 30 | Agreement reader (paper look) with Edit / Undo / changes list, like the rent agreement review |
| 31–34 | **Templates**: which template fits; 4 template copies (personal details removed) bundled in `assets/agreements/`; agreement now shows the **real template text filled with the broker's answers**, unknown fields grey |
| 35 | Agreement ready tick + "Next", "Send for signing", sent screen, home notices |
| 36 | After sending: status first; **Make changes** creates Draft 2, 3, 4 (must be sent again) |
| 37 | Email/WhatsApp: box appears after picking, cursor + right keypad, WhatsApp logo |
| 38–39 | Broker can add collaboration details **while** waiting for documents; then "Go to home" |
| 40 | **Send for signing rebuilt from the canvas** (RV3–RV6, HM1): per-owner replies, remind, manager signer (TrustKeyper or broker) |
| 41, 43 | Waiting spinner – now only on the Documents stage of the house page |
| 42 | "Send for signing" = one sheet: WhatsApp or Email, then straight to "Draft N sent!" |
| 44 | After sending: calmer page; bottom = Remind + Go to home; actions as rows |
| 45 | **Add new property**: name first, then "Add details myself / Upload sale deed / Upload old rent agreement" |

---

## 4. Real vs pretend today

| Area | Today | Needs backend |
|---|---|---|
| Onboarding records | `PropertyOnboardingStore` saves JSON in **SharedPreferences** on the phone (key `property_onboardings_v1`). Not shared, lost on reinstall. | Firestore collection + rules + repository (Task A) |
| Asking the owner for papers | Nothing is sent. TEST: "Owner sends some documents", "Fix everything, all approved". | Messages + owner upload page/WhatsApp + checking (Task B) |
| Checking papers (Aadhaar readable, bank name matches…) | Pretend. | Review by team or automated reading (Task B) |
| Agreement text | **Real**: chosen template (bundled copy) filled on the phone from answers. Unknown fields stay as grey `[PLACEHOLDER]`. | Optional server PDF; Drive fetch later (Task C) |
| "Agreement is being made" | TEST: "Agreement is ready (Draft 1)". | Team/automation marks ready (Task C) |
| Sending draft to owners | Records `via` + time per owner; nothing is sent. | WhatsApp / email + owner review page (Task D) |
| Owner opens / says yes / asks change | TEST buttons. | Owner page / WhatsApp buttons write replies (Task D) |
| Remind | Records `remindedAt` (once per hour rule in app); nothing is sent. | Real reminder message (Task D) |
| Stamp paper, printing | TEST: "Our team: next step". | Admin/ops action (Task E) |
| Signing | TEST: "Owner signs", "TrustKeyper signs"; broker "Sign now" screen is a demo. | E-sign provider (Task F) |
| Property name | **Real**: saved in Firestore `properties.name`. | – |
| Upload sale deed / old agreement | Shows "coming soon". | Upload + reading (Task H) |
| Done-sound on build | Mac-only Xcode build phase (`~/Documents/trustkeyper-done-sound.sh`), not in repo. | – |

---

## 5. The journey and states

Phases (`OnboardingPhase`, field `phase`): `papers → questions → preparing → review → printing → signing → ready`.

```
papers      Owner(s) send papers. Broker may fill collaboration details early (answers saved, phase stays papers).
            All papers approved → if answers exist: preparing, else questions.
questions   Broker answers: fee, how the owner pays, start date + months, notes → preparing.
preparing   We write the agreement (template + answers).            → review (draftNo=1, readyAck=false)
review      readyAck=false: "Your agreement is ready" tick, Next sets readyAck=true.
            Not sent: broker reads, edits (fee/dates/notes), "Send for signing" (pick WhatsApp or Email)
                      → each owner gets it (replies[o].via, sentAt) → draftSent=true, edits=[].
            Sent: per owner replies[o].status: '' (not opened) → seen → yes | change.
                  Owner asks a change → changes[] (status waitingYou) → broker answers (Answer button).
                  Broker "Make changes" → draftNo+1, draftSent=false, replies=[] (new draft, send again).
                  All owners yes → ownerAgreedFinal=true → broker "Lock and continue" → printing.
printing    printStep 0 stamp paper · 1 printing · 2 ready → signing.
signing     Owners sign (ownerSigned / coOwners[i].signed). Manager signs (brokerSigned):
            signsAs='trustkeyper' → TrustKeyper's signatory signs; signsAs='me' → the broker signs ("Sign now").
            Everyone signed → ready.
ready       House ready.
```
Rules the backend must keep:
- A change after sending **never** auto-sends: it makes the next draft, unsent.
- One reminder per owner per hour.
- Months ≤ 11 (longer needs a registered agreement – not supported).
- Owner index 0 is the main owner and holds the house papers; owners 1..n give only Aadhaar / phone / email.
- The contact used to reach an owner (email or WhatsApp number) is auto-approved.

---

## 6. Data model (`apps/flutter_app/lib/src/features/broker/data/property_onboarding.dart`)

Store each record as one Firestore document; the JSON below is exactly what `toJson()` writes today, so `fromJson()` keeps working.

`PropertyOnboarding`
| field | type | meaning |
|---|---|---|
| id | string | record id |
| ownerName, channel, contact | string | main owner; channel `email` or `whatsapp`; contact = email or 10-digit phone |
| createdAt, lastAskedAt | int ms | created; last time papers were asked |
| coOwners | `CoOwner[]` | owners 2..n |
| papers | `OnboardingPaper[]` | main owner + house papers |
| phase | string | see Section 5 |
| agreementSkipped | bool | broker skipped the agreement |
| rent, deposit | int ₹ | from the owner's "rent and deposit" paper |
| address | string | house address |
| answers | `AgreementAnswers` | broker's collaboration details |
| draftNo | int | current draft number (0 = none) |
| draftSent, draftSentAt | bool, int ms | current draft is with the owners |
| readyAck | bool | broker saw the "agreement ready" page (old saves default true) |
| ownerAgreedFinal | bool | all owners said yes to the current draft |
| changes | `DraftChange[]` | changes asked (by owner or broker) |
| versions | `DraftVersion[]` | {number, summary, at} history |
| edits | `AgreementEdit[]` | broker's own changes since last send: {group fee/dates/notes, before: AgreementAnswers} |
| replies | `OwnerReply[]` | one per owner, same order as owners |
| signsAs | string | `trustkeyper` (default) or `me` |
| printStep | int | 0 stamp paper · 1 printing · 2 ready to sign |
| brokerSigned, ownerSigned | bool | manager signed; main owner signed |

`CoOwner`: name, channel, contact, papers (Aadhaar/phone/email only), signed, lastAskedAt.

`OnboardingPaper`: key (`address · aadhaar · phone · email · tenantAgreement · rentDeposit · bank · keys`), status (`waiting · checking · approved · notClear · needsYou · notNeeded`), reason (shown to the broker/owner when not clear), value (text shown, e.g. "HDFC Bank · 5010 …"). **Add** for the backend: a Storage path for the file.

`AgreementAnswers`: feeType (`percent · daysMonthly · days · fixed · once · none · later`), feeValue (number), payWay (`cut` deduct from rent · `direct` owner pays · `signing` at signing; one-time fees only allow `cut`), startDate (`yyyy-MM-dd`), months (1–11), notes.

`OwnerReply`: status (`'' · seen · yes · change`), via (`'' · whatsapp · email · both`), sentAt, remindedAt.

`DraftChange`: id, clause, before, asked, askedBy (`owner`/`broker`), status (`waitingYou · waitingOwner · agreed · notAgreed`), round (max 3), note.

`BrokerProperty` (`broker_property_repository.dart`, Firestore `properties`): **new `name`** (what the broker calls it), address, rooms, floor, totalFloors, furnishing, sizeSqFt, facing, carParking, bikeParking, inventory. Rules need no change (no field allowlist).

---

## 7. Backend work (tasks)

### Task A – Store onboardings in Firestore
- Collection `propertyOnboardings/{id}` with `brokerUid`, `participantUids` (like `properties`), plus the JSON above.
- Rules: broker reads/writes own records; owners (when they have accounts) read only their record; phase changes that belong to the team (preparing→review, printing steps) only by admin/functions.
- Replace `PropertyOnboardingStore` storage (SharedPreferences) with a repository that streams Firestore; keep the same public methods so screens don't change.
- One-time migration: upload any local `property_onboardings_v1` records on first launch (optional).
- Done when: two phones with the same broker see the same houses; reinstall keeps them.

### Task B – Ask owners for papers, receive and check them
- On create / "Remind" / "Not replying → remind": send the owner a link (email or WhatsApp) to an upload page (reuse the existing document-link system: `functions/document-requests.js`, `document-request-files.js`, web recipient pages).
- Owner uploads → paper status `checking` → team or automation sets `approved`, `notClear` (+reason) or `needsYou`.
- Co-owners: same, only Aadhaar/phone/email.
- "Same owner, new house": copy approved ID papers from the earlier record (already done in the app – keep the rule server-side).
- Done when: the TEST buttons "Owner sends some documents" / "Fix everything" are no longer needed.

### Task C – Make the agreement
- Template choice: `features/broker/data/agreement_templates.dart` (`AgreementTemplates.pick`). Today: percent → monthly percent; daysMonthly → 3-days (needs rent on our platform; warns if `direct`); days → yearly 15-days; NRI → NRI hybrid (no NRI question yet, so never picked); fixed/once/none/later → no template (plain-words page).
- Filling: `features/broker/data/agreement_filler.dart` fills placeholders from the record. Templates: `apps/flutter_app/assets/agreements/*.md` (copies; change only when Aman asks). Gaps not asked yet: Mr/Ms, relation + father's/spouse's name, age, owner's own address, property description/area, fixtures, owner bank, switch-deadline date (15-days).
- Backend: when phase becomes `preparing`, a function (or the team in admin) produces Draft 1 (store text/PDF in Storage, set `phase=review, draftNo=1, readyAck=false, versions=[...]`). Optional later: fetch templates from Google Drive every time (plan in `docs/AGREEMENT-TEMPLATES.md`).
- Done when: "Agreement is ready (Draft 1)" TEST button is not needed and the home shows "Agreement is ready".

### Task D – Send the draft, collect replies
- `sendDraftWithConfirm` (app) → call a function `sendDraftForSigning(id, via)`; it sends each owner a personal link on `sendWayFor(owner, via)` (WhatsApp or email; falls back to the other if missing) and writes `replies[o] = {via, sentAt}`, `draftSent=true`, `draftSentAt`, `edits=[]`.
- Owner review page (web, no app): read the draft, **Yes** or **Ask a change** (clause + text). Writes `replies[o].status = seen | yes | change` and `changes[]`. Delivery/read receipts (WhatsApp) can set `seen`.
- All owners `yes` → `ownerAgreedFinal=true`, `changes` waitingOwner→agreed.
- Remind: function `remindOwner(id, owner)`; enforce once per hour server-side; writes `remindedAt`.
- New draft (broker "Make changes"): server mirrors the app rule – `draftNo+1, draftSent=false, ownerAgreedFinal=false, replies=[]`, new `versions` entry.
- Done when: "opens it / says yes / asks a change" TEST buttons are not needed; home notice "Under review by X · 1 of 2 said yes" is live.

### Task E – Lock, stamp paper, printing
- "Lock and continue" → phase `printing`. Ops/admin moves `printStep` 0→1→2 → phase `signing`.

### Task F – Signing
- E-sign provider (e.g. Aadhaar e-sign via a provider such as Digio or Leegality). Owners sign from a link; manager signs per `signsAs`:
  - `trustkeyper`: TrustKeyper's signatory signs (templates name Paravent, signatory Aman Maheshwari); no "Sign now" for the broker.
  - `me`: the broker signs in the app. Note: templates still name Paravent – an outside-broker template is an open decision.
- Write `ownerSigned`, `coOwners[i].signed`, `brokerSigned`; all signed → `phase=ready`; signed PDF to Storage and to everyone.

### Task G – Notifications
- Home notices already read the record (`agreementJustReady`, `underOwnerReview`, `yesCount`). Add push notifications for the same moments: papers need you, agreement ready, owner replied, everyone signed.

### Task H – Add property from a paper
- "Upload sale deed" / "Upload old rent agreement" (Change 45) show "coming soon". Needs upload to Storage + reading (OCR/LLM) → prefill the property steps for the broker to check.

### Task I – WhatsApp-only owners and tenants (planned, not built)
- Goal: owners/tenants never install the app; every app event triggers a WhatsApp message and replies flow back.
- Shape: event outbox in Firestore → provider adapter (Meta Cloud API or a BSP) → approved templates; webhook (signature-checked) → updates the same records; per-recipient conversation state; media download to Storage; opt-out; quiet hours; a simulator provider for tests (like `razorpay-test-provider.js`).
- Needs from the company: Meta Business verification, WhatsApp Business account and number, template approvals, budget, consent text review (DPDP).

### Security and privacy (all tasks)
- Aadhaar, PAN, bank: store files in private Storage paths, show masked values, keep access to participants + admin, log access, delete on request (DPDP Act). Never put them in URLs or message text.

---

## 8. Client methods to swap (`PropertyOnboardingStore`)

| App method | Becomes |
|---|---|
| `create`, `update`, `remove`, `addOwner`, `removeOwner` | Firestore writes (Task A) |
| `changeAgreementPart`, `undoAgreementPart` | Firestore write; keep `_newDraftIfSent` rule server-side too |
| `sendDraftTo`, `finishSending` | `sendDraftForSigning` function (Task D) |
| `remindOwner` | `remindOwner` function (Task D) |
| `setSignsAs` | Firestore write (who signs as manager) |
| `testOwnerSendsPapers`, `testFixAllPapers` | **remove** – real uploads + checks (Task B) |
| `testDraftReady` | **remove** – agreement generation (Task C) |
| `testOwnerOpens`, `testOwnerSaysYes`, `testOwnerAgrees`, `testOwnerAsksChange` | **remove** – owner page/WhatsApp (Task D) |
| `testNextPrintStep` | **remove** – admin action (Task E) |
| `testOwnerSigns`, `testManagerSigns` | **remove** – e-sign webhooks (Task F) |
The TEST ONLY panel is built in `_testPanel` in `onboarding_house_screens.dart`; hide it when the backend is live.

---

## 9. Open decisions (ask Aman)
1. How do we know the broker is TrustKeyper staff vs an outside broker? Template for outside brokers?
2. Where to ask "Owner lives outside India (NRI)?" (enables the NRI template).
3. Templates for fixed amount / one-time amount / no fee / decide each deal.
4. Missing agreement fields to ask (Mr/Ms, father's/spouse's name, age, owner address, property area/description, fixtures, owner bank).
5. WhatsApp: Meta directly or a provider; languages; first scope.
6. E-sign provider and stamp-paper process owner.

---

## 10. File map
- Data: `apps/flutter_app/lib/src/features/broker/data/property_onboarding.dart` (model + store), `agreement_templates.dart`, `agreement_filler.dart`, `broker_property_repository.dart`.
- Screens: `presentation/onboarding_start_screens.dart` (new house, owners), `onboarding_house_screens.dart` (house page per phase, TEST panel), `onboarding_agreement_screens.dart` (questions, reader, edit, changes, sign demo), `send_for_signing_screens.dart` (send sheet, sent screen, who signs), `agreement_paper.dart` (template page), `onboarding_widgets.dart` (shared UI), `broker_draft_cards.dart` (home notices), `broker_property_screen.dart` (add property).
- Routes: `lib/src/core/routing/app_router.dart` under `/broker/onboarding/:id/...` and `/broker/property`.
- Templates: `apps/flutter_app/assets/agreements/` + `docs/AGREEMENT-TEMPLATES.md`.
- Tests: `test/property_onboarding_test.dart`, `test/agreement_filler_test.dart`, `test/broker_property_test.dart`.
- Change history: `docs/CHANGELOG-staging.md` (Changes 1–45 app, 46–56 website).
