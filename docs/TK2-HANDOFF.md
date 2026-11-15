# TK2 (TrustKeeper 2) – developer handoff

For any agent (Codex, Claude) or developer who picks up TK2, including the Rental Desk integration. Tied to files and commits; read this before the chat history. Written 15 Nov 2026 from the repository and the live sites; anything not verified is marked **Not verified**.

Read first: [`AGENTS.md`](../AGENTS.md) (house rules), [`TRUSTKEEPER2-START-HERE.md`](TRUSTKEEPER2-START-HERE.md), [`TRUSTKEEPER2-BACKEND.md`](TRUSTKEEPER2-BACKEND.md), [`TRUSTKEEPER2-BUILD-RECORD.md`](TRUSTKEEPER2-BUILD-RECORD.md), [`TRUSTKEEPER2-DESK.md`](TRUSTKEEPER2-DESK.md). Product decisions: Claude Doc "TrustKeyper: from finalised to moved in" (https://claude.ai/artifact/BXGQJ9RPdwzHVAcaECvba8).

---

## 1. Source of truth

| Item | Value |
| --- | --- |
| Git repository | https://github.com/desicode-blip/Trustkeyper-Flutter (remote `origin`) |
| Active development branch | `staging` — tip **`f203922086b864701e4e693f9d6c7ec5c99e2142`** (14 Nov 2026, includes Ajay's merge `3accea9`) |
| Production branch | `main` — tip `6ef6c976486f9d18034ba08dc19d3bca1789f293` (15 Oct 2026). No TK2 code on `main`. |
| Open feature branch | `feature/tk2-lead-desk` — `5375d5b` (lead desk, Change 97) + this handoff. Not merged; no PR opened yet. |
| Other remote branches | `codex/tk2-access-control` (`01c15c3`, already merged into staging), `codex/ios-phone-otp-callback` (older). |
| Staging web app (tenant/owner) | https://trustkeyper-tk2-staging.web.app/ — Firebase project `trustkeyper-app-staging`, Hosting target `tk2` |
| Lead desk (broker web, separate host) | https://app.trustkeyper.com/ — Cloudflare Pages project `trustkeyper-app` (Aman's Cloudflare account) |
| Rental Desk (ChatGPT/Codex-built) | https://desk.trustkeyper.com/ — Next.js on ChatGPT site hosting (GoDaddy CNAME `desk` → `custom-domains.chatgpt.site`). **Its source is not in this repository or on Aman's Mac.** |

### Local checkouts

| Path | State |
| --- | --- |
| `/Users/amanmaheshwari900/Documents/Trustkeyper-Flutter` (Aman's Mac; Xcode builds the phone app from here) | Git branch `main` at `6ef6c97`, but the **working tree is not managed by git pulls**: TK2 files were copied in from `staging`. On 15 Nov `lib/`, `test/` and `assets/` were checked file-by-file against `staging@f203922` and match (image files differ only by embedded metadata). Git reports 38 modified + 47 untracked files; they are the TK2 files plus **local-only iOS/Android setup that must not be committed or overwritten**: `.firebaserc`, `.gitignore`, `android/app/build.gradle.kts`, `AndroidManifest.xml`, `ios/Runner.xcodeproj/project.pbxproj`, `Runner.xcscheme`, `Runner.xcworkspace/contents.xcworkspacedata`, `AppDelegate.swift`, `Info.plist`, `RunnerTests.swift`, `ios/Flutter/*.xcconfig` (its `Generated.xcconfig` sets `FLUTTER_TARGET=lib/main_tk2.dart`). Treat this folder as a device build folder; do real work in a clean clone. |
| `/home/claude/trustkeyper-flutter` (Claude's cloud workspace) | Clone of the repo; worktrees `/tmp/newstaging` (`origin/staging`), `/tmp/desk` (`feature/tk2-lead-desk`). Not reachable by other agents. |
| `D:\Trustkeyper\Project` | Named in `AGENTS.md` as the Windows primary checkout. **Not verified** (not reachable from this session). |

### What is deployed on staging

- **Staging web (`trustkeyper-tk2-staging.web.app`): not verified.** Firebase Hosting serves `version.json` = `2.0.0+47` (no commit SHA) and `Last-Modified: Fri, 13 Nov 2026 10:43:01 GMT` (16:13 IST). That matches the time of commit `3634a5a` "Prepare dedicated TK2 Firebase staging release" (13 Nov, 16:13 IST), so the site was most likely built from `3634a5a` or a working tree near it. It is **older than the staging tip**: Changes 95–96, Ajay's later commits (`decc61f`, `9bc7bf2`, `01c15c3`) and the merge `3accea9` are not on the hosted web app. Confirm in Firebase Console → Hosting → release history.
- **Staging Functions** (`tk2ConfirmVisit`, `tk2FinalizeFile`, region `asia-south1`) and **TK2 rules**: deployed 13 Nov per `TRUSTKEEPER2-BACKEND.md` §5; exact commit **not verified**.
- **Phone app:** built locally from the Mac folder (= `staging@f203922` content) with Xcode on 15 Nov; demo build (no `tk2_cloud.json`, data on the phone, OTP `123456`).
- **app.trustkeyper.com:** built from the `feature/tk2-lead-desk` working tree on 15 Nov just before `5375d5b`. The only difference from `5375d5b`: the commit adds a `kIsWeb` guard around the desk refresh timer (tests only) and keeps `__HASH__` as a placeholder in `tool/tkdesk/_worker.js` (the deployed copy carries the real password hash).

### Uncommitted / unpushed work Codex needs to know

- None in the repo beyond `feature/tk2-lead-desk` (pushed). It is **not reviewed** and **not merged** into staging.
- Lead data files (sheet and group leads) are kept outside the repo on purpose (`/home/claude/match-work/*.json`, encrypted copies served by app.trustkeyper.com under `leads/`). Never commit them.
- The earlier standalone desk https://amanmaheshwari900.github.io/trustkeyper-match (repo `amanmaheshwari900/trustkeyper-match`) is the backup of the first prototype; it is not part of TK2.

---

## 2. From request to production

1. **Request.** Aman asks in chat. If it can be read two ways, ask one short question. Product decisions go into the Claude Doc above, not into code comments.
2. **Branch.** Fetch, compare `origin/staging` and `origin/main`, branch from current `staging`: `feature/<name>` or `fix/<name>`. One feature per branch. Never commit to `staging` or `main` directly (`AGENTS.md`). Continue an open PR branch for fixes to that feature.
3. **Change.** Reuse existing TK2 screens and flows exactly; change only what was asked. Rules in `TRUSTKEEPER2-START-HERE.md` "Product rules (don't break)" — above all: tenants never see door number, owner details, keys or private notes (`tk2PublicPayload` in `lib/src/tk2/tk2_link.dart` and `publicOnly()` in `firestore.rules` must stay in step).
4. **Test locally** (Flutter **3.38.6**, pinned in `.fvmrc`; Node 22; Java 21 + Firebase CLI for emulators):
   ```bash
   npm run setup:backend && npm run setup:flutter
   cd apps/flutter_app && flutter analyze && flutter test test/tk2   # TK2 + desk tests
   cd ../.. && npm run test:flutter        # whole app (concurrency 1)
   npm test                                # backend unit + tooling
   npm run test:rules                      # emulators, project demo-trustkeyper-rules
   ```
   Run apps: `flutter run -t lib/main_tk2.dart` (broker), `-t lib/main_tk2_web.dart -d chrome` (tenant/owner), `-t lib/main_tk2_desk.dart -d chrome` (all three, lead desk branch). Backend against emulators: see `TRUSTKEEPER2-BACKEND.md` §5 "For local testing" (`demo-tk2`, `TK2_EMULATOR_HOST`).
5. **Record.** Add a "Change NN" entry to `docs/CHANGELOG-staging.md` and, for bigger pieces, a section in the build record or a feature doc.
6. **Review.** Push the branch, open a PR **into `staging`**. Read the actual diff before merging. Ajay reviews and merges.
7. **Staging deploy (Ajay only — deployments and billable actions are restricted to him).**
   - Web: `scripts/tk2-build.sh web staging` then `scripts/tk2-build.sh deploy-web` (`firebase.tk2.json`, target `tk2` → `trustkeyper-tk2-staging`).
   - Functions: `node scripts/prepare-tk2-functions.cjs` then `firebase deploy --only functions:authentication:tk2ConfirmVisit,functions:authentication:tk2FinalizeFile --project trustkeyper-app-staging` (full steps in `TRUSTKEEPER2-BACKEND.md` §5).
   - Rules: diff against the live staging rules first; deploy only the `tk2…` blocks (§5.3).
   - Phone: Xcode scheme `tk2` / `scripts/tk2-build.sh broker staging` (`TRUSTKEEPER2-MOBILE.md`). Aman presses ▶ himself unless he asks.
   - There is **no CI workflow** in the repo (`.github/` absent); pushes do not deploy anything.
8. **Production.** Promotion `staging` → `main` is a separate reviewed release after staging validation. Production Firebase project is `trustkeyper` (`.firebaserc` alias `production`). Schema/rules changes to production are a separate step. Real money (Razorpay live) needs Aman's sign-off. No TK2 production release has happened.

### Where deployment is configured

| What | File |
| --- | --- |
| Firebase projects and Hosting targets | `.firebaserc` (`default`/`production` = `trustkeyper`, `staging` = `trustkeyper-app-staging`, target `tk2` → `trustkeyper-tk2-staging`) |
| TK2 web hosting | `firebase.tk2.json` |
| Main app hosting / functions / rules | `firebase.json`, `firestore.rules`, `storage.rules`, `firestore.indexes.json` |
| TK2 build/deploy script | `scripts/tk2-build.sh` |
| TK2 functions package | `scripts/prepare-tk2-functions.cjs` |
| Lead desk web build | `apps/flutter_app/tool/build_tkdesk.sh`; worker `tool/tkdesk/_worker.js`; hosted on Cloudflare Pages `trustkeyper-app` (manual upload in the Cloudflare dashboard; D1 database `trustkeyper-desk` bound as `DB`) |
| DNS for trustkeyper.com | GoDaddy (nameservers `ns53/54.domaincontrol.com`): `www` → `trustkeyper-website.web.app`, `desk` → ChatGPT sites, `app` → `trustkeyper-app.pages.dev` |

### Rollback

- **Firebase Hosting (staging web):** Firebase Console → Hosting → `trustkeyper-tk2-staging` → Release history → *Rollback*; or rebuild the previous commit and run `deploy-web`.
- **Functions:** check out the previous commit and redeploy the same two function selectors.
- **Firestore/Storage rules:** redeploy the previous rules file (Console → Rules → history shows earlier versions).
- **app.trustkeyper.com:** Cloudflare → Workers & Pages → `trustkeyper-app` → Deployments → *Rollback* on an earlier deployment. Data in D1 is unaffected; every save is also in the append-only `log` table.
- **Phone app:** rebuild from the previous commit in Xcode.
- **Code:** revert the merge commit on `staging` through a PR (never force-push shared branches).

### Environment variables and secrets (values live in their existing stores; never commit them)

| Name | Where it lives | Used by |
| --- | --- | --- |
| `TK2_FIREBASE_API_KEY`, `TK2_FIREBASE_API_KEY_ANDROID`, `TK2_FIREBASE_PROJECT_ID`, `TK2_FIREBASE_SENDER_ID`, `TK2_FIREBASE_STORAGE_BUCKET`, `TK2_FIREBASE_AUTH_DOMAIN`, `TK2_FIREBASE_APP_ID_WEB`, `TK2_FIREBASE_APP_ID_IOS`, `TK2_FIREBASE_APP_ID_ANDROID`, `TK2_IOS_BUNDLE_ID`, `TK2_WEB_URL`, optional `TK2_EMULATOR_HOST`, `TK2_NATIVE` | `apps/flutter_app/tk2_cloud.json` (git-ignored; template `tk2_cloud.example.json`) passed with `--dart-define-from-file` | `lib/src/tk2/tk2_cloud.dart`. Without the file the app is the demo build. |
| `TK2_WEB_APP` | `--dart-define` (lead desk build only) | `tk2WebApp` in `lib/src/tk2/tk2_link.dart`; default stays the staging site |
| `EMAIL_OTP_SECRET`, `RESEND_API_KEY`, `RAZORPAY_TEST_KEY_ID`, `RAZORPAY_TEST_KEY_SECRET`, `RAZORPAY_TEST_WEBHOOK_SECRET` | Firebase/Google Secret Manager (`defineSecret` in `functions/*.js`) | Email OTP, test payments |
| `TRUSTKEYPER_SIGNING_CREDENTIALS_FILE` | Local signing directory | Android release signing (`AGENTS.md`) |
| `TEAM_PASS_SHA256` (optional) | Cloudflare Pages secret for `trustkeyper-app` | Overrides the password hash in the desk worker |
| Desk team password | Aman (chat only) | Unlocks desk storage and encrypted lead batches |

---

## 3. What Rental Desk will touch

The lead desk on `feature/tk2-lead-desk` (Change 97, `docs/TRUSTKEEPER2-DESK.md`) is already the TK2-native version of a rental/lead desk. **Integrate Rental Desk into it, not beside it**: bring Rental Desk's features (sources, follow-ups, pitches, deletion reasons, version history) into `lib/src/tkdesk/` and its data into the lead model, instead of adding a second set of lead records.

| Area | Files |
| --- | --- |
| OTP login (TK2 broker) | `lib/src/tk2/tk2_app.dart` (`Tk2Login`: phone → code → name; Ajay's `verifiedPhone()` check), `lib/src/tk2/tk2_cloud.dart` (Firebase phone auth, email OTP calls) |
| OTP login (tenant/owner web) | `lib/src/tkweb/tkweb_auth.dart` (`TkwOtp`), `lib/src/tkweb/tkweb_session.dart` |
| OTP (main app, email) | `lib/src/features/auth/data/firebase_auth_service.dart`, `lib/src/features/auth/presentation/auth_screens.dart`, `functions/email-otp.js`, `docs/email-otp-setup.md` |
| Session handling | TK2: `Tk2Store.load()` / `forgetDevice()` in `lib/src/tk2/tk2_store.dart`, `TkwSession` in `tkweb_session.dart`; main app: `lib/src/features/auth/data/firebase_session_preferences.dart`, `recipient_web_persistence.dart`, `lib/src/core/widgets/session_bound_screen.dart` |
| Staff / admin permissions | `firestore.rules` (`isAdmin()` = `users/{uid}.roles` contains `admin` and not paused; `isBroker()` = role `broker` + approved; client roles limited to `broker/owner/tenant`), `functions/account-roles.js`, `lib/src/features/auth/data/account_roles.dart`, admin login `lib/src/features/admin/presentation/admin_auth_screen.dart` + `AdminAccessGate`, admin data `lib/src/features/admin/data/admin_repository.dart`, `docs/firebase-admin-panel.md`. TK2 collections (`tk2…`) are broker-owned, not admin. **TK2 has no staff role today**; the desk is open to any signed-in broker and its data is protected by the team password. A staff-only desk needs a decision (see §4). |
| Navigation | TK2 broker: `buildTk2Router` and `Tk2Shell` in `lib/src/tk2/tk2_app.dart` (bottom bar Home · Visits · Payments · Profile; on the lead branch a sidebar on ≥ 960 px via `DeskWide` in `lib/src/tkdesk/tkdesk_screens.dart`); tenant/owner web: `lib/src/tkweb/tkweb_app.dart`; main app: `lib/src/core/routing/app_router.dart` (`/admin/...` routes behind `AdminAccessGate`); one web entry for all three: `lib/main_tk2_desk.dart` |
| Property records | `Tk2Listing` / `Tk2Inactive` in `lib/src/tk2/tk2_store.dart`; house facts `BrokerProperty` in `lib/src/features/broker/data/broker_property_repository.dart`; Firestore `tk2Listings` (public) + `tk2Private` (door, owner, keys, notes); owner invites `tk2Invites`; sync `lib/src/tk2/tk2_sync.dart` |
| Tenant records | `tk2Visits` (bookings), `tk2Trips/{tenantUid}_{listingId}` (journey answers), `tk2Deals` (shared deal, parts `b/t/o`), deal model `lib/src/tk2/tk2_deal.dart` |
| Lead / follow-up records | **On `feature/tk2-lead-desk` only:** `Lead` (tenant and home leads, all sheet columns, must-haves, status, history, call notes, follow-up date) in `lib/src/tkdesk/tkdesk_lead.dart`; storage `lib/src/tkdesk/tkdesk_store.dart` (device → Cloudflare D1 `leads` + `log`; Firestore `tk2Leads` when the TK2 backend is on — **rules for `tk2Leads` not written yet**); matching `tkdesk_match.dart`; import `tkdesk_import.dart` (TK Lead Format v1, `docs/TK-LEAD-FORMAT.md`). On staging there are no lead records. Related main-app records: owner callback requests `functions/manager-callbacks.js` + `lib/src/features/owner/data/manager_callbacks.dart` (owner asks for a call; not leads), listing enquiries `enquireOwnerListing` in `functions/index.js`. |
| Database migrations | Firestore has no migration framework. Changes are additive collections/fields plus rules, staging first (`AGENTS.md`). Rules tests live in `functions/rules-test/*.test.mjs` (TK2: `tk2.test.mjs`). D1 (desk) creates its tables on first request in `_worker.js` (`CREATE TABLE IF NOT EXISTS leads/log`). |
| Imports and background jobs | Agreement imports: `functions/agreement-imports.js`, `agreement-import-files.js`. The only Firestore trigger: `sendBrokerUpdatePush` (`functions/index.js`, `onDocumentCreated`). No scheduled jobs exist. Lead import is client-side (Import screen) plus encrypted published batches (`tool/tkdesk/tkleads.js`, writer `tool/tkdesk/tkm_crypto.py` (`write <data_dir> <leads.json> "<source>"` needs only the public key in `leads/keys.json`)). Group reading (WhatsApp/Facebook) runs as a Claude browser session; AI helper jobs are in `lib/src/tkdesk/tkdesk_helpers.dart` / `docs/AI-HELPERS.md`. |

**Where to add a staff-only Rental Desk screen:** as a section of the desk in `lib/src/tkdesk/tkdesk_screens.dart`, registered in the `DeskWide` sidebar (index map in `DeskController`) and in `DeskNarrow` tabs, with data in `DeskStore`. Gate it the way main-app admin screens are gated (`AdminAccessGate` + `isAdmin()` rules), or add a `staff` role in `firestore.rules`/`account-roles.js` if staff should not be full admins.

---

## 4. Decisions pending that affect Rental Desk

1. **Where lead data lives long term:** Cloudflare D1 (live now, no Ajay deploy needed) or Firestore `tk2Leads` in `trustkeyper-app-staging` (needs rules + deploy by Ajay). The store already writes to either.
2. **Who may open the desk:** today any signed-in broker (demo OTP `123456` on the web build) plus the team password for data. Options: staff role, admin role, or per-person phone OTP with an allowlist.
3. **Rental Desk data:** desk.trustkeyper.com holds its own leads; export them in TK Lead Format v1 (or a sheet-header CSV) and import through the desk so nothing is retyped.
4. **Domain plan:** `app.trustkeyper.com` now serves the lead desk; `docs/TRUSTKEEPER2-BUILD-RECORD.md` §6 had suggested it for TK2 links. Decide whether TK2 staging web moves there (then `tk2WebApp` and Firebase authorized domains change).
5. Unchanged from `TRUSTKEEPER2-BACKEND.md` §6: Razorpay live, automatic WhatsApp/SMS, documents upload, e-sign, broker email OTP.

---

## Current work and next steps

_Update this section at every handover: date, who, what changed. Newest first._

### 15 Nov 2026 — Claude (handing over to Codex)

**Live on staging (`trustkeyper-app-staging`):** TK2 web app (most likely `3634a5a`, not verified), TK2 rules, `tk2ConfirmVisit`, `tk2FinalizeFile`. Staging branch tip `f203922` (Changes 93–96 + Ajay's pilot merge) is **ahead of the hosted web app**; redeploying web from `f203922` is pending (Ajay).

**Live elsewhere:** lead desk at https://app.trustkeyper.com (Cloudflare, from `feature/tk2-lead-desk`); Rental Desk at https://desk.trustkeyper.com (ChatGPT, separate code).

**Changing now:** nothing in progress. `feature/tk2-lead-desk` (`5375d5b` + this doc) is pushed, analyze clean, `flutter test test/tk2` passing (46 TK2 + 8 desk tests); waiting for review.

**Next:**
1. Open the PR `feature/tk2-lead-desk` → `staging`; Ajay reviews.
2. Integrate Rental Desk features into `lib/src/tkdesk/` (sources list, follow-up queue, pitch messages, deletion reasons, version history) and import its data (decision 3).
3. Decide decisions 1–2; if Firestore: add `tk2Leads` rules (owner `brokerUid`, no delete) + rules test, deploy to staging.
4. Laptop layouts for TK2 broker screens shown in the desk (welcome slides, phone-width pages).
5. Redeploy the TK2 staging web from `staging` tip so it matches the phone build.

**Pending migrations:** none run. Proposed, additive: Firestore `tk2Leads/{id}` (+ rules); D1 `leads`/`log` already created on first use.
