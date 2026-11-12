# TrustKeeper 2 – backend handoff (for Ajay)

Updated: 12 Nov 2026 · Branch: `staging` · Code: Change 93 · Firebase project: **trustkeyper-app-staging only**

Read this first. It says what TrustKeeper 2 (TK2) is, what is already built and
tested, and the few steps left for you to make it live on staging. Nothing here
touches production (`trustkeyper`), and nothing moves real money.

---

## 1. What TK2 is

Three apps that work together:

| Who | App | Entry point | Opened from |
| --- | --- | --- | --- |
| Broker | Mobile app (iOS / Android) | `apps/flutter_app/lib/main_tk2.dart` | App icon |
| Tenant | Web app | `apps/flutter_app/lib/main_tk2_web.dart` | Property link the broker shares on WhatsApp |
| House owner | Same web app | same | Invite link from "Send link to owner" |

The journey:

1. The broker signs up with phone OTP and sets a usual **token amount**.
2. The broker adds a house in one of two ways:
   - by hand (details → rent → visit times → visit fee and token → photos → private block);
   - or with **Send link to owner**, after which the owner fills it in on the web.
3. The broker taps **Share**. The tenant opens the link, picks a time, signs up with
   phone OTP, pays the visit fee (test) and gets a 4-digit visit code.
4. At the visit the broker types the tenant's code. The **server** checks it, and the
   fee becomes the broker's. The broker can also mark "Did not come", cancel, or add a
   gate pass. The tenant can cancel: within 5 minutes they get 98% back; after that,
   nothing comes back.
5. After the visit, the tenant says whether they liked it. They then go on with:
   block (token) → documents → details → agreement → sign → pay → keys. These steps
   are screens only for now (see section 6).

Design and copy are final. **Do not change screens.** The backend work below changes
no screen. The one exception: when the backend is on, the broker gets the existing
OTP screen at login.

## 2. Demo build vs backend build (one switch)

- **Demo build** (default): no Firebase. Everything stays on the device in
  SharedPreferences. Links carry the property inside them (`#p-…`, `#owner-…`). OTP
  is `123456`. This is what Aman tests today.
- **Backend build**: the same code with `--dart-define-from-file=tk2_cloud.json`.
  `Tk2Cloud.start()` starts Firebase, and every save also goes to Firestore. Links
  become short: `#l-<listingId>` for tenants and `#i-<inviteId>` for owners. OTP is
  real (Firebase phone auth; email OTP uses the existing `requestEmailOtp` /
  `verifyEmailOtp`).

How it fits together:

- Screens only talk to `Tk2Store` (broker data, visits) and `TkwSession` (web login,
  tenant journey, owner answers). Both still save on the device first, so the app
  works offline.
- `Tk2Sync` (`lib/src/tk2/tk2_sync.dart`) mirrors every save to Firestore and listens
  for changes. With the backend off, `Tk2Store.sync` is null and nothing changes.

| File | What it does |
| --- | --- |
| `lib/src/tk2/tk2_cloud.dart` | Firebase start from dart-defines, phone/email OTP, photo and gate-pass upload, `tk2ConfirmVisit` call |
| `lib/src/tk2/tk2_sync.dart` | Firestore reads and writes for the broker app, tenant web and owner web |
| `lib/src/tk2/tk2_store.dart` | Broker data and visit rules; calls `sync?.…` after each save |
| `lib/src/tk2/tk2_link.dart` | `tk2PublicPayload`: the only listing fields tenants may see |
| `lib/src/tkweb/*` | Tenant and owner web screens, login (`tkweb_auth.dart`), session |
| `functions/tk2.js` | `tk2ConfirmVisit` (visit code check) |
| `firestore.rules`, `storage.rules` | `tk2…` blocks, added before the final deny-all |
| `firebase.tk2.json` | Hosting for the web app (target `tk2`), separate from the main app's hosting |
| `scripts/tk2-build.sh` | Build and deploy commands |
| `apps/flutter_app/tk2_cloud.example.json` | Settings template; copy it to `tk2_cloud.json` (git-ignored) |

## 3. Data (Firestore, all collections start with `tk2`)

| Collection | Holds | Who reads | Who writes |
| --- | --- | --- | --- |
| `tk2Brokers/{uid}` | Name, phone, default token, contacts, account details | That broker | That broker |
| `tk2Listings/{id}` | **Public** listing = `tk2PublicPayload` + `brokerUid`, `ownerUid`, `inviteId`, `active`, `ph` (photo URLs) | Anyone, by id (no listing all) | Broker; the owner who added it |
| `tk2Private/{id}` | Full listing: door no., owner name and phone, keys, note, off-market reason, `ownerAnswers` | Broker; that owner | Broker; that owner |
| `tk2Invites/{id}` | "Send link to owner": broker, house name, owner name; then `ownerUid`, `listingId` | Anyone with the id | Broker creates; the owner claims once |
| `tk2Visits/{id}` | Visit: listing, broker, tenant, time, fee, status, gate pass | Broker and tenant of the visit | Tenant books; status changes are limited, see rules |
| `tk2Visits/{id}/secret/code` | 4-digit visit code | **Tenant only** | Tenant, once |
| `tk2Trips/{tenantUid}_{listingId}` | Tenant journey answers (step, liked, details) | Tenant; that broker | Tenant |

Storage: `tk2/listings/{id}/…` holds house photos (public read; the broker or owner
uploads). `tk2/visits/{id}/…` holds the gate pass (broker uploads; broker and tenant
read). `tk2/people/{uid}/…` holds private documents (owner only; not wired yet).

Privacy rules the code and the rules enforce:

- Tenants never see the door number, full address, owner name or number, keys or
  notes. The public doc may only have the keys listed in `publicOnly()` in
  `firestore.rules`. A Flutter test checks that the code and the rules list match.
- Visit fee is ₹0–500. A booking must match the listing's fee and broker, and only
  while the listing is `active`.
- Only `tk2ConfirmVisit` can set a visit to `done`. The broker never sees the code.
- Within 5 minutes of booking, the tenant may set `customerCancelled` (refund). After
  that, only `customerCancelledLate` (no refund). The broker may set `cancelled` or
  `noShow`. Visits are never deleted.

No composite indexes are needed: every query is a single `where(... isEqualTo ...)`.

## 4. What is tested

- **Rules:** `functions/rules-test/tk2.test.mjs`, 6 tests, all passing. The whole rules
  suite gives 56 of 57; test 46 ("team-photo grants…") fails the same way without the
  TK2 changes.
- **Function:** `functions/test/tk2.test.js`. The full `npm test` passes, 259 tests.
- **Flutter:** `apps/flutter_app/test/tk2/tk2_test.dart`, 33 tests. These include
  public-doc privacy, owner answers, token and visit money rules.
- **End to end on the Firebase emulators**, with the web builds of both apps driven in
  a headless browser:
  - broker phone OTP → profile saved → house added with a photo, which uploads to
    Storage. The public doc has no door or owner; the private doc has them;
  - tenant opens `#l-<id>` → phone OTP → books → the visit and secret code are saved;
  - the broker sees the visit live. A wrong code shows "That code is not right"; the
    right code makes it `done` through `tk2ConfirmVisit`;
  - owner opens `#i-<id>` → OTP → invite claimed → adds a house with a photo and key
    holder. The house appears in the broker's list, with the owner's name, number and
    keys filled into the private block.

## 5. Make it live on staging (your steps, in order)

All commands run from the repo root with `--project staging`
(= `trustkeyper-app-staging`, see `.firebaserc`).

1. **Register the apps** in the Firebase console (staging): a **Web app** ("TK2 web")
   and an **iOS app** with bundle id `com.trustkeyper.tk2`. Add Android only if
   needed. Copy `apps/flutter_app/tk2_cloud.example.json` to `tk2_cloud.json` and fill
   in `apiKey`, `messagingSenderId`, `storageBucket`, `authDomain` and the app ids.
   These are public identifiers, not secrets. The file is git-ignored anyway.
2. **Auth:** Phone sign-in must be on. Add the TK2 hosting domain under
   Authentication → Settings → Authorized domains (web phone OTP needs it). Owner
   email OTP uses the existing `requestEmailOtp` / `verifyEmailOtp` functions and
   their email setup. Check that they are deployed on staging.
3. **Hosting site**, once:
   ```
   firebase hosting:sites:create <site-name> --project staging
   firebase target:apply hosting tk2 <site-name> --project staging
   ```
   Put `https://<site-name>.web.app/` in `TK2_WEB_URL`.
4. **Rules.** These deploy for the whole staging project. The TK2 blocks are additive
   (new `tk2…` paths only) and sit before the deny-all. Run the rules tests first:
   ```
   firebase emulators:exec --only auth,firestore,storage --project demo-trustkeyper 'npm --prefix functions run test:rules'
   firebase deploy --only firestore:rules,storage --project staging
   ```
5. **Function**, only the new one:
   ```
   firebase deploy --only functions:tk2ConfirmVisit --project staging
   ```
   The predeploy runs `npm test`. Region `asia-south1`, like the others.
6. **Web app:**
   ```
   scripts/tk2-build.sh web staging
   scripts/tk2-build.sh deploy-web
   ```
7. **Broker app on a phone:** `scripts/tk2-build.sh broker staging` (`flutter run`
   with the settings).
   - iOS phone OTP needs the usual Firebase setup for the TK2 bundle id: an APNs key
     in Firebase, or the reCAPTCHA fallback URL scheme (the encoded app id) in
     `Info.plist`. See `docs/ios-phone-otp-callback-fix.md`.
   - The repo's iOS project is still the main app's (`com.trustkeyper.mobile`). Aman's
     Mac switches the bundle id, display name and target locally (see
     `docs/TRUSTKEEPER2.md`). A proper flavor for TK2 is the clean way to ship it
     (section 6).
8. **Smoke test:**
   - broker signs up;
   - adds a house with a photo;
   - shares it and opens the link on another phone;
   - the tenant books;
   - the broker confirms with the code;
   - the broker sends an owner link and the owner adds a house;
   - the house shows up in the broker's list.

For local testing without staging, put `"TK2_EMULATOR_HOST": "127.0.0.1"` in the
settings and run `firebase emulators:start --only auth,firestore,storage,functions
--project demo-tk2`. OTP codes show at
`http://127.0.0.1:9099/emulator/v1/projects/demo-tk2/verificationCodes`.

## 6. Still pending (decide or build before a real launch)

Critical:

1. **Payments (Razorpay).** The visit fee, token and move-in payment are still test
   screens: a visit is saved as booked with no charge. Needed:
   - an order per visit or token;
   - hold, then payout to the broker after `done`;
   - refunds for cancel / did not come (98% within 5 minutes, 50% to the broker on a
     no-show);
   - the 50/50 owner/broker split when a tenant backs out of a token.

   Real money needs Aman's sign-off (AGENTS.md).
2. **iOS packaging:** a TK2 flavor or target with its own bundle id, icon and phone
   OTP setup. Today it only builds through Aman's local Mac switch.
3. **Messages to people.** The broker sends listings and owner invites from their own
   WhatsApp, SMS or copy; that already works. Not sent automatically yet:
   - the broker isn't told about a new booking;
   - nobody gets a reminder before the visit;
   - the gate pass isn't sent to the tenant.

   These need a provider decision, then a Firestore trigger on `tk2Visits`.

Next:

4. **Documents.**
   - Owner and tenant documents (`TkwOwnerDocs`, `TkwTenantDocs`) stay in the
     browser. Wire the uploads to `tk2/people/{uid}/…`; the rules are ready.
   - Broker-side document requests from the main app aren't connected to TK2 either.
5. **Agreement and e-sign** (Leegality), stamp paper, move-in, repairs. These are
   designed (Claude Doc "TrustKeyper: from finalised to moved in") but not built.
6. **Broker account email:** in Profile, the email is still checked with the demo code
   `123456` (`tk2_account.dart`). Use a real email OTP for TK2 brokers, or hide the
   field.
7. **Delete account:** removes the broker's listings and profile and keeps visit
   records. Firebase may ask for a fresh login before it deletes the login itself; the
   app then signs out instead.
8. **App Check, analytics, crash reports:** not on for TK2.
9. **Owner-added houses:** if the owner restarts, a second house is created for the
   same invite (one invite → many houses). Fine for now.

## 8. After the token: the deal (Change 93)

Everything after a tenant picks a house is one **deal**, shared by all three apps.
The ten stages: token → documents → agreement draft → changes and approval → stamp
paper and signing → payments → key handover → 7-day repairs → society move-in →
living there. The product description is the Claude Doc "TrustKeyper: from finalised
to moved in".

| File | What it does |
| --- | --- |
| `lib/src/tk2/tk2_deal.dart` | `Tk2Deal`: the data, the stage, each person's tasks, money rules. No UI. Start here |
| `lib/src/tk2/tk2_deal_page.dart` | The deal page (next step, who we wait for, the ten stages). Same widget for broker, tenant, owner |
| `lib/src/tk2/tk2_deal_screens.dart` | Stages 1–6: pay, document review, terms, agreement, stamp paper, sign |
| `lib/src/tk2/tk2_deal_move.dart` | Stages 7–9: handover, tenant's check, record, repairs, society steps |
| `lib/src/tk2/tk2_agreement.dart` + `assets/agreements/rent_leave_licence.md` | Agreement text from TrustKeyper's leave & licence template |
| `lib/src/tkweb/tkweb_deal.dart` | Web host: deal links, sign-in, document screens |

How it works:

- **One document per deal**, `tk2Deals/{id}`, with three parts: `b` (broker), `t`
  (tenant), `o` (owner). Each person writes only their own part; the rules enforce it.
  The stage and "who is holding it up" are computed (`Tk2Deal.stage`, `tasks`), never
  stored. Tenant-started deals have id `<tenantUid>_<listingId>`.
- **Starting:** the tenant pays the token on the web, or the broker taps "… wants this
  house" on a finished visit and the tenant pays from their link. A paid token turns the
  listing off (`active: false`); ending the deal turns it on again.
- **Links:** `#d-<dealId>` (backend) for tenant and owner. The owner claims the deal the
  first time they open it. Demo build: `#deal-…` carries a copy of the deal.
- **Files:** `tk2/deals/{dealId}/…` in Storage (documents, stamp paper, handover photos
  and video, repairs), readable by the three parties only.
- **Society playbooks:** `tk2Playbooks/{society-slug}`, shared by brokers. The first
  broker creates it; later edits land in `proposed`. **The TrustKeyper team copies
  `proposed.steps` into `steps` from the console** once checked.
- **Demo build:** "Demo: do the tenant's step" buttons play the other people's steps on
  one phone (`Tk2Deal.demoDo`). They are hidden when the backend is on.

Tests: `test/tk2/tk2_deal_test.dart` (8, including a full ten-stage walk) and two more
rules tests in `functions/rules-test/tk2.test.mjs` (8 in all).

Still test-only or pending in the deal:

1. **All deal payments** (token, move-in, owner's ₹250, repairs) are test payments.
   Razorpay: one order per payment; token refund/split on a broken deal
   (`Tk2Deal.tokenSplit`); payout of repair costs to the broker.
2. **E-sign:** signing is a typed name. Connect Leegality (decision: Leegality); keep
   `t.signed` / `o.signed` as the result.
3. **Society email:** opens the sender's mail app (`mailto`, tenant in CC). Decision:
   send from a TrustKeyper address with broker, owner and tenant in CC. Needs a callable
   that only the deal's broker can use, with the fixed template and a rate limit.
4. **Messages:** the broker's "Remind" opens WhatsApp/SMS by hand. Automatic reminders
   and "owner is told when the house is blocked" need the messaging provider.
5. **Rules are by part, not by field.** A tenant can write any key inside `t` (for
   example `paid: true`). Once Razorpay is in, payment flags must be written by the
   server only (move them out of `t`/`o` or check them in a function).
6. **The agreement template** was made from one signed TrustKeyper agreement. Have a
   lawyer review `rent_leave_licence.md` before real use. Aadhaar/PAN numbers are not
   printed in it yet.
7. **PDF** of the signed agreement is not generated.

## 7. How to change things safely

- The shape of a public listing lives in two places: `tk2PublicPayload`
  (`tk2_link.dart`) and `publicOnly()` (`firestore.rules`). Change both. The Flutter
  test fails if they drift.
- Money rules live in `Tk2Visit` (`tk2_store.dart`). Server checks live in
  `functions/tk2.js` and the rules.
- Run `flutter analyze`, `flutter test test/tk2`, `npm --prefix functions test`, and
  the rules tests on the emulators.
