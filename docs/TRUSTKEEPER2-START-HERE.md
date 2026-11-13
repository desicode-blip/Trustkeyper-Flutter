# TrustKeeper 2 – start here (read first in every new chat)

Last updated: 13 Nov 2026 · Base branch: `staging`

## What it is
Three apps that work together:
- **Broker:** mobile app. Entry `apps/flutter_app/lib/main_tk2.dart`, code in `lib/src/tk2/`.
- **Tenant and house owner:** one web app, opened from WhatsApp links. Entry `lib/main_tk2_web.dart`, code in `lib/src/tkweb/`.

What the broker does:
- adds houses, either by hand or with "Send link to owner";
- shares them in one tap;
- tenants book a paid visit (₹0–500), with a 4-digit code that releases the fee to the broker.

After a visit the tenant blocks the house with a token. From there one shared **deal** runs in all three apps (Change 93):
token → documents → agreement → approval → stamp paper and signing → payments → key handover → 7-day repairs → society move-in → living there.
- Model and rules: `lib/src/tk2/tk2_deal.dart`. Deal page: `tk2_deal_page.dart`. Screens: `tk2_deal_screens.dart`, `tk2_deal_move.dart`. Web host: `lib/src/tkweb/tkweb_deal.dart`.
- **Product source of truth:** Claude Doc "TrustKeyper: from finalised to moved in" (https://claude.ai/artifact/BXGQJ9RPdwzHVAcaECvba8). Every product decision lives there only; this note and the backend handoff link to it instead of repeating it.
- Demo build: "Demo: do the …'s step" buttons play the other people on one phone.

Tests: `apps/flutter_app/test/tk2/` (46: `tk2_test.dart`, `tk2_deal_test.dart`, `tk2_money_test.dart`). History: `docs/CHANGELOG-staging.md`. Journeys: `docs/TRUSTKEEPER2-JOURNEYS.md`.

## Backend (Change 92)
- **Demo build** (default, what Aman tests on his phone): no Firebase; data stays on the device; OTP 123456.
- **Backend build:** use `--dart-define-from-file=tk2_cloud.json` with staging settings. The pilot covers listing and owner onboarding, test bookings, private gate passes and server-side visit confirmation. See the pilot scope in the backend handoff before using the historical deployment steps.
- Ajay's handoff, with deploy steps and what's pending (Razorpay, automatic messages, documents, agreement): **`docs/TRUSTKEEPER2-BACKEND.md`**.
- Owner/tenant demo web app: https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt (private to Aman). It is rebuilt with `/home/claude/tools/rebuild.sh` and published in patch mode.

## Current state
- Main app screens are reused as they are (splash, welcome, login, broker home, bottom bar, Onboard property, account and profile).
- Home cards: **Design B** is final. E is hidden (light code kept).
- Property list:
  - sort and filter (2+ properties);
  - a "Not active" section; deactivate with reasons, and a 10-month reminder in the bell.
- Share sheet: Recent / Add new → WhatsApp / Text / Email ticks.
- Owner invite sheet: WhatsApp / Text message / Copy link. Closing it sends nothing.
- Token:
  - the broker sets a usual amount at sign-up and in Profile;
  - it is filled in per property, and each property can change it;
  - the tenant pays that property's token.
- Counters: tap the number to type it.
- Bottom bar: Home · Visits · Payments · Profile. **Payments** (`tk2_money.dart`) lists every transaction; the Fees card on Home opens it.
- **Notifications** (`tk2_notes.dart`): the bell opens one list, laid out like WashKrew's, worked out from visits, deals and properties; only read state and turned-off kinds are saved.
- Visits: held / yours totals; the code check (server-side with the backend); cancel / did not come; gate pass.

## Product rules (don't break)
1. Never show tenants the door number, full address, owner name or number, key status or private note.
   - This applies everywhere: card, share message, link and booking.
   - With the backend, `tk2PublicPayload` and `publicOnly()` in `firestore.rules` must match. A test checks this.
2. Card heading = society name, else area. Never the broker's own label.
3. Visit fee ₹0–500. ₹0 = free visit.
4. Reuse the main app's screens and flows exactly. Change only what Aman asks, only where he asks.
5. Simple words on screen. No repeated steps.

## How we work
- Follow `AGENTS.md`. Create a feature or fix branch from current staging, review and test the diff, then use a PR targeting staging when publishing is authorized.
- Aman presses ▶ in Xcode himself. Claude only updates the code and the Mac, unless asked.
- Ask one short question when a request can be read two ways.
- Checks:
  - `flutter analyze --no-pub` and `flutter test test/tk2`;
  - with backend changes, also `npm --prefix functions test` and the rules tests on the emulators.
- Tests only for logic.
- Keep replies short and plain. Update this note at the end of each chat.

## Claude's technical routine
1. Work in the checkout of `desicode-blip/Trustkeyper-Flutter`. Use the branch in the [TK2 mobile build instructions](TRUSTKEEPER2-MOBILE.md) and Flutter 3.38.6.
2. Analyze and test. Append the changelog entry and review the feature or fix branch against staging.
3. Copy the changed files to the Mac:
   - `device_commit_files` to `~/Documents/Trustkeyper-Flutter/...`;
   - check md5 via `device_bash` (`$HOME/mnt/Trustkeyper-Flutter`).
4. Emulator end-to-end:
   - Firebase CLI: `npm i -g firebase-tools`;
   - `firebase emulators:start --only auth,firestore,storage,functions --project demo-tk2`;
   - build both apps for web with `TK2_EMULATOR_HOST=127.0.0.1` in the settings file;
   - drive them with Playwright (Flutter semantics on).

## Mac build setup

Follow [TK2 mobile build instructions](TRUSTKEEPER2-MOBILE.md) and select the shared `tk2` scheme in `Runner.xcworkspace`.

## Open items
- Run the broker pilot on physical Android and iOS devices using the staging backend.
- Test-only until connected: Razorpay (all payments; real money needs Aman's sign-off), Leegality e-sign, society email from a TrustKeyper address, automatic WhatsApp/SMS, signed-agreement PDF.
- The rent agreement template needs a lawyer's review.
- Product decisions (owner's ₹250, society timing, fees…): see the Claude Doc above.
