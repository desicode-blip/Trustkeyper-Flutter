# TrustKeeper 2 – the three journeys (broker, tenant, owner)

Last updated: 2 Nov 2026 · Branch: `staging` · Status: UX/UI being finalised. Backend is not connected yet: everything below works on test data.

This document is for people (founders, developers). It says what each person sees, in order, and which rules the money follows. Code details are in `docs/CHANGELOG-staging.md`.

## Where things live

| Who | What they use | Where |
|---|---|---|
| Broker | Mobile app (Flutter) | `apps/flutter_app/lib/src/tk2/` · entry `lib/main_tk2.dart` |
| Tenant | Web app (Flutter web) opened from a WhatsApp link | `apps/flutter_app/lib/src/tkweb/` · entry `lib/main_tk2_web.dart` · live demo: https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt |
| House owner | Same web app, owner invite link (later also a WhatsApp chat bot) | `lib/src/tkweb/tkweb_owner.dart` |

The web app is Flutter web and reuses the apps' own screens and design system: the login screen (logo hero, name, Phone/Email switch, any country code), the 6-box OTP, the onboarding headers, the "Add property" steps and the customer page. Build it with `apps/flutter_app/tool/build_tkweb.sh` (output `build/tkweb`, static files). Links: `#p-<base32 public details>` opens a property; `#owner-<base32 {bn, h}>` opens an owner invite; no hash opens a start page.

## 1. Broker (mobile app)

1. Home → **Add property** → type a name only he sees (e.g. "Flat 402, Madhapur").
2. Choose: **Send link to owner** (owner fills everything, see journey 3) or **Add manually**.
3. Add manually: address (required), size, door facing, parking → rooms, floor, furnishing.
   The address is asked in parts: flat/house no. (private), society, area, city.
4. Then 5 short steps:
   - **Rent details**: rent + maintenance (included/extra → amount) · security deposit · who can rent (tick boxes: Anyone, Family, Bachelor male, Bachelor female, Companies) · pets · property available from (calendar, today pre-selected).
   - **Visit times**: days (Every day + Mon–Sun chips, any mix; all seven = Every day), times (7 am – 11 pm range).
   - **Visit fee** (₹0–500).
   - **Photos** (up to 10, 3 per row; ★ or drag to set the cover; can skip). Every photo carries a light TrustKeeper watermark.
   - **Only for you** (green, never shared): owner name and phone, keys, note, and **brokerage**: who pays (Owner / Tenant / Both / None) and how much each. Only the tenant's part is shown to tenants.
5. Property page → **Share**: WhatsApp message with the property link. The link carries only public details. On home cards (Design B) a **Send** button: pick a tenant added before or type a new number (any country code) → WhatsApp / text message / both → "Sent".
6. **Visits** tab: upcoming visits. **Add gate pass** on each visit (photo/screenshot) → sent to the tenant on WhatsApp. The 1-hour reminder call also reminds him, and the app pings him. After the visit he types the tenant's 4-digit code to get the fee (code works from 24 h before to 24 h after the visit time).

## 2. Tenant (web, from the property link)

1. Opens the link: photos, rent card, facts, visit-fee rules, "What happens next" (book → visit → token blocks it, house hidden from others → agreement → sign → pay deposit, brokerage if any, 1 month rent → keys). No "In the house" list (brokers don't fill it at this stage). **No login.**
2. **Book a visit**: picks a day and hour. Days/hours outside the broker's visit times are greyed. Many people can book the same hour.
3. Signs up: name + mobile (any country code) → 6-digit OTP.
4. Pays the visit fee → **Your visit** screen, in this order: status · **When** (date, time, Add to Google Calendar) · **Where** (society, area, city – no flat number – Open in Google Maps) · **Your broker** (name, number, Call) · visit code · good to know (reminder call 1 hour before, gate pass on WhatsApp, be on time) · Cancel visit (any time; refund minus 2% only within 5 minutes, after that no refund and the broker gets half).
5. **I visited the place** → **Did you like it?** Yes → pays **token ₹15,000** → house is blocked. No → "We told the broker": he sends more houses; tenant can call him or wait. (Later: tenant can browse the broker's other houses.)
6. Shares details for the agreement: full name, email, current address, work, people, Aadhaar. At the same time the owner is asked for their details.
7. When both are in, the **rent agreement** is generated and shared with broker, tenant and owner. Only the broker can change it (changes are agreed offline). Broker marks it final.
8. Tenant and owner **e-sign**.
9. Tenant pays on the platform: **security deposit + first month rent + brokerage**.
10. **Key handover.** After keys are handed over, TrustKeeper releases the brokerage to the broker.

## 3. House owner (web, from the broker's invite; later also WhatsApp bot)

1. Opens the invite: "Your broker asked you to add your house". What we ask, and a privacy note.
2. Signs up: name + **phone or email** (sliding switch; any country code) → 6-digit OTP.
3. How many owners + are you one of them → the same house steps the broker uses (address in parts, size, facing, parking, rooms, floors, furnishing) → rent details, visit times, photos (owner mode: no visit fee, no brokerage) → **Keys**: who has them – Me (sheet: how the broker collects keys when a visit is booked), Another property broker (name + number), Security (name + number + optional note), Someone else (name + number + optional note). Papers (Aadhaar, bank, old agreement) are asked later, only when a tenant blocks the house.
4. Owners are **not** asked brokerage (broker sets it).
5. Done: broker can share the house; WhatsApp updates on bookings.

## Money rules

| Case | Tenant | Broker | TrustKeeper |
|---|---|---|---|
| Visit happens (broker enters code) | – | full visit fee | – |
| Tenant cancels within 5 minutes of booking | fee minus 2% | – | 2% |
| Tenant cancels after 5 minutes | no refund | – | fee |
| Tenant does not come / >15 min late | no refund | half the fee | half (not shown to anyone) |
| Broker or owner not available (broker cancels) | full refund | – | – |
| Token amount (₹15,000) | paid to block the house | – | kept by TrustKeeper (not shown to tenant) |
| Brokerage | paid with deposit + first rent | released after key handover | holds until then |

Visit fee is ₹0–500 (₹0 = free visit, no payment step). Brokerage for "days of rent" = rent × days ÷ 30.

## Privacy rules

Never shown to tenants (not in the share message, link, web app or booking): door/flat number, full address, owner name and number, keys, private note. The link payload is built in `tk2_link.dart` (`tk2PublicPayload`) and is covered by a test.

## For the developer – what to connect

Today it is demo only. Each item is marked in the code/prototype as "Demo".

1. Accounts + OTP (phone for tenants; phone or email for owners; demo code today: 123456).
2. Data: properties, visits, owners, tenants in Firestore (replace on-phone storage in `Tk2Store`).
3. Payments (Razorpay): visit fee (held), token, deposit/rent/brokerage, refunds and payouts per the money rules. Real money needs Aman's sign-off.
4. WhatsApp + SMS: share message, Send to tenant (WhatsApp / SMS / both — `Tk2Store.sendListing` records it today), owner invite, owner question-by-question bot, updates.
5. Google Calendar invite (prototype uses a calendar link), reminder call 1 hour before (tenant + broker).
6. Rent agreement generation from templates, broker approval, e-sign.
7. Burn the TrustKeeper watermark into every uploaded photo (the app shows it as an overlay today).
8. Host the web app on trustkeyper.com (Flutter web) and point `tk2WebApp` in `tk2_link.dart` to it.
