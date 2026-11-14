# TrustKeeper 2 – build record (Changes 93–96)

One condensed list of what Aman and Claude built on 12–14 Nov 2026, so nothing has
to be redesigned or rewritten. Product decisions live in the Claude Doc
"TrustKeyper: from finalised to moved in" (https://claude.ai/artifact/BXGQJ9RPdwzHVAcaECvba8);
the full history is in `CHANGELOG-staging.md`.

**Status (14 Nov, 18:41):** all of it is already in `staging`. Ajay's merge
`3accea9` ("Integrate the TrustKeyper staging pilot with current staging") joined his
pilot branch with Changes 93–96 and the colour fix. Checked on that commit:
`flutter analyze` clean, `flutter test test/tk2` all passing. If a later Ajay
version drops any of this, the commits below can be re-applied.

| Change | Commit | What |
| --- | --- | --- |
| 93 | `3fe45a5` | Whole move-in after the token, in all three apps |
| 94 | `a49a5c0` | Payments tab, notifications, owner payment choice, society at signing |
| 95 | `247e15a` | Token asked with the first property, not at sign-up |
| 96 | `968a400` | Phone + code login, clean start, example property, own web link |
| – | `360ddca` | Example photo in colour, card not faded |

## 1. Move-in deal (Change 93)

- One shared **deal** per blocked house, with three parts: broker `b`, tenant `t`,
  owner `o`. Each person writes only their own part. The stage and next steps are
  worked out from the data, never stored.
- Ten stages: token → documents → draft → approval → stamp paper and signing →
  payments → handover → 7-day repairs → society → living there.
- **Code:**
  - `tk2_deal.dart`: the model and rules.
  - `tk2_deal_page.dart`: the next-step button, who it waits on, reminders and the tracker.
  - `tk2_deal_screens.dart` and `tk2_deal_move.dart`: one screen per step.
  - `tk2_agreement.dart` and `assets/agreements/rent_leave_licence.md`: the agreement template.
  - Web: `tkweb_deal.dart`.
- **Backend:**
  - Firestore `tk2Deals` and `tk2Playbooks`; Storage `tk2/deals/{id}`.
  - Rules: each person can write only their own part; the owner can claim the deal once.
- **Demo build:** "Demo: do the tenant's / owner's step" buttons and `#deal-` links.
- **Tests:** `test/tk2/tk2_deal_test.dart`, which includes a walk through all ten stages.

## 2. Broker app additions (Change 94)

- **Bottom bar:** Home · Visits · Payments · Profile. Visits has a calendar-with-tick
  icon (`assets/design/nav-visits.svg`).
- **Payments tab** (`tk2_money.dart`):
  - Totals: earned, this month, and "Coming to you".
  - Filters: All, Received, On hold, Refunded. Group by month, property or type.
  - The detail screen shows where the money went and what happened when.
  - The list is built from visits and deals; nothing extra is stored.
  - The Fees card on Home opens this tab.
- **Notifications** (`tk2_notes.dart`):
  - Laid out like WashKrew: filters, unread count, Mark all as read, Today and Earlier.
  - Covers every visit, money, move-in and property event, plus a "Your turn" item
    for each broker step.
  - The gear turns a kind off.
  - Read state is saved on the phone only.
- **Owner payment:** the ₹250 agreement fee any time after the token (optional), or
  together with his brokerage after signing and before the keys. The keys wait for
  both tenant and owner. The deal keeps `ownerBrokerage`.
- **Society steps** open as soon as both have signed.
- **Timestamps added:** `Tk2Visit.changedAt`; deal `signedAt`, `keysAt`, repair
  `at`, `endedAt`.
- **Tests:** `test/tk2/tk2_money_test.dart`.

## 3. Token (Change 95)

- No token question at sign-up.
- On the **first property** the token field shows in full, filled with ₹15,000;
  what he saves becomes his usual amount (`Tk2Store.tokenSet`).
- On **later properties** it shows filled in with **Edit**; an edit applies to that
  property only.
- **Profile** still changes the usual amount.

## 4. Login, clean start, example, link (Change 96 + colour)

- **Login (`Tk2Login` in `tk2_app.dart`):** phone number → 6-digit code.
  - A known account goes to Home with "Welcome back, <first name>", gone after 3 seconds.
  - A new account is asked "What is your name?", then sees "Welcome, <first name>".
- **Clean start:** a new or different number calls `Tk2Store.forgetDevice()`. It
  clears properties, visits, deals, notification state and the main app's
  half-finished onboardings (`PropertyOnboardingStore.clear()`), so no stale
  "Continue" cards. Log out and Delete account clear these too.
- **Example property (`Tk2ExamplePhoto` in `tk2_widgets.dart`):** a real home
  photo in colour (`assets/images/example-home.jpg`, from Unsplash, which is free
  to use) with "EXAMPLE" written across it. It disappears with the first real
  property, and the heading changes from "Example property" to "Your properties".
- **Links:** `tk2WebApp` in `tk2_link.dart` is `https://trustkeyper-tk2-staging.web.app/`,
  no longer the Claude preview page.

## 5. Decisions already settled (12–14 Nov)

- Agreement fee: ₹500 in total, ₹250 each from owner and tenant. It covers stamp
  paper, drafting and Leegality e-sign.
- Owner's ₹250: paid early, or together with the brokerage before the keys.
- The owner pays for repairs in the app.
- The society is told at signing.
- Users: broker, tenant and owner only.
- Login: phone and code; the name is asked only for new accounts.
- The token is asked with the first property.
- The example property uses a colour photo with a watermark.

## 6. Still open

- Real Razorpay payments (need Aman's sign-off), Leegality e-sign, signed PDF.
- Society emails from a TrustKeyper address (today the app opens the person's own mail app).
- Phone alerts and automatic WhatsApp/SMS.
- A lawyer's review of the agreement template.
- Our own domain for links (for example `app.trustkeyper.com`): Ajay adds it in
  Firebase Hosting with a DNS record, then `tk2WebApp` changes.
- `ownerBrokerage` can be read by the tenant in the deal document (never shown in
  the app); move it to a private place if that matters.
- The phone needs the backend build (Ajay's `scripts/bootstrap-macos.sh tk2` on the
  Mac) before owner and tenant answers reach the broker's phone.

## 7. Re-applying on a new version

1. Check what is missing: `git grep -n "class Tk2Payments\|bool tokenSet\|forgetDevice\|Tk2ExamplePhoto\|feeEarly" -- apps/flutter_app/lib`.
2. For anything missing, cherry-pick that commit (`3fe45a5`, `a49a5c0`, `247e15a`,
   `968a400`, `360ddca`) or copy the files named above, then run
   `flutter analyze --no-pub` and `flutter test test/tk2`.
3. On the Mac (demo build): copy the changed files into
   `~/Documents/Trustkeyper-Flutter`; the target stays `lib/main_tk2.dart`.
