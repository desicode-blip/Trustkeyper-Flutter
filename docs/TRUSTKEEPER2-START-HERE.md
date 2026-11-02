# TrustKeeper 2 – start here (read first in every new chat)

Last updated: 2 Nov 2026 · Branch: `staging` only (never `main`) · Last change: 66

## What it is
A separate launch-fast broker app inside the same Flutter project. The broker adds properties, shares them in one tap, and customers book a visit by paying a fee (₹0–500). The fee is held and goes to the broker after the visit, or back to the customer if the visit doesn't happen.
Entry: `apps/flutter_app/lib/main_tk2.dart` (no Firebase). Code: `apps/flutter_app/lib/src/tk2/`. Tests: `apps/flutter_app/test/tk2/tk2_test.dart`. Details and backend plan: `docs/TRUSTKEEPER2.md`. History: `docs/CHANGELOG-staging.md` (Changes 58–66).

## Current state
- Splash, welcome carousel, logo, login look, broker home, floating bottom bar (Home · Visits · Profile): main app screens reused as they are.
- Add property = the main app's **Onboard property** journey (Send link to owner / Add manually), shared via `brokerPropertyRoutes()` in `lib/src/core/routing/app_router.dart`. Add manually → house details (no "Things in the house") → rent & details screen.
- Home cards: **Design E and Design B are the finalists** (`lib/src/tk2/tk2_designs.dart`). A, C, D are hidden from home (code still there).
  - E: left panel 2 BHK loudest → rent → maintenance; right: society name (else area), then the address without house numbers; facts in 2 columns with a light divider (left: sft, furnishing, who can rent; right: pets, available from, space for more). One outlined icon family.
  - B: swipeable photos with 3 dots (house illustration placeholder); title "2.5 BHK · ₹30,000 incl. maintenance"; same address line as E; facts.
- Property page: broker-only "Complete address and details" block with a green lock banner.
- Visits tab: held / yours totals, visit done with the customer's 4-digit code, cancel / didn't come refunds.
- All data is on the phone (SharedPreferences). Payments are test-only. The share link page isn't live yet.

## Product rules (don't break)
1. Never show tenants the door number, full address, owner name/number, key status or private note: not in the card title, share message, customer page or booking. These live only in the broker-only block.
2. Card heading = society name, else area. Never the broker's own label for the property.
3. Visit fee: broker types ₹0–500. ₹0 = free visit, no payment step.
4. "Things in the house" is asked later, during agreement drafting, not when adding a property.
5. Reuse existing main-app screens and flows exactly. Change the look only where it's critically needed.
6. When Aman asks to change one design or section, change only that one (or add it as a new variant). Don't touch the others.
7. Simple words on screen (low-literacy users). No repeated steps.

## How we work (to save credits)
- **Batch.** Aman sends several changes in one message. Claude makes them all, then stops.
- **Build only when Aman says "build".** Aman can also press ▶ in Xcode himself. Claude doesn't screenshot Xcode to confirm. The chime on the Mac means the build is done; Aman says if something failed.
- **Ask one short question** when a request can be read two ways (e.g. "previous version"), before building.
- **Design options:** make quick mockups first. Code only the option Aman picks.
- **Checks:** `flutter analyze --no-pub` and only `test/tk2` (quiet output: pipe to `tail`). Full suite only before a release. It has 39 old failures that were there before TK2.
- **Tests only for logic** (privacy, money, fee, address rules). Not for layout tweaks.
- **One commit + one changelog entry per batch.** Short reply: what changed, in plain words.
- Read only the part of a file you need. Don't print long logs.
- Start a fresh chat per feature, and update this note at the end of each chat.

## Claude's technical routine (per batch)
1. Edit in `/home/claude/trustkeyper-flutter` (clone of `desicode-blip/Trustkeyper-Flutter`, branch `staging`). Flutter at `/tmp/flutter/bin` (`export PATH=/tmp/flutter/bin:$PATH CI=true`). Re-clone or install if the session is new.
2. Analyze + `test/tk2`.
3. Append the changelog entry (human text + "AGENT RECORD – Change N"). Commit with the session trailers, `git pull --rebase origin staging`, push. Another session pushes website changes.
4. Copy the changed files to the Mac with `device_commit_files` (force) to `~/Documents/Trustkeyper-Flutter/...`, then verify with md5 via `device_bash` (`$HOME/mnt/Documents/Trustkeyper-Flutter`).
5. Build only when asked: Xcode (click-only access) → Run.

## Mac build setup (local only, not in the repo)
The Mac's iOS project is switched so TK2 installs as its own app, "TrustKeeper 2":
- `ios/Flutter/Generated.xcconfig`: `FLUTTER_TARGET=lib/main_tk2.dart`
- `ios/Runner.xcodeproj/project.pbxproj`: `PRODUCT_BUNDLE_IDENTIFIER = com.trustkeyper.tk2` and `CODE_SIGN_ENTITLEMENTS = ""` (no push/App Attest, so the team wildcard profile signs it)
- `ios/Runner/Info.plist`: display name "TrustKeeper 2"
- Originals backed up in `~/Documents/tk1-ios-backup/`. Restore them before building the main TrustKeyper app.

## Open items
- Pick between E and B. Then remove the rest.
- Properties added via "Send link to owner" show in the Continue panel but not as property cards yet.
- Real backend: login (OTP), Firestore, photo upload, public link page, Razorpay held fee / payout / refund, notifications (see `docs/TRUSTKEEPER2.md`). Real money needs Aman's sign-off.
- Rent agreements are not in TK2 yet ("Make rent agreement" goes home).
