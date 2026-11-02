# TrustKeeper 2 – the three journeys (broker, tenant, owner)

Last updated: 2 Nov 2026 · Branch: `staging` · Status: UX/UI being finalised. Backend is not connected yet: everything below works on test data.

This document is for people (founders, developers). It says what each person sees, in order, and which rules the money follows. Code details are in `docs/CHANGELOG-staging.md`.

## Where things live

| Who | What they use | Where |
|---|---|---|
| Broker | Mobile app (Flutter) | `apps/flutter_app/lib/src/tk2/` · entry `lib/main_tk2.dart` |
| Tenant | Web app opened from a WhatsApp link | Prototype: `docs/prototypes/tk2-web/index.html` · live demo: https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt |
| House owner | Web app opened from a WhatsApp link (later also a WhatsApp chat bot) | Same web app, `#owner` link |

The tenant/owner web app is an HTML prototype for agreeing the flow. When the flow is final, it will be rebuilt in Flutter web (same screens), hosted on trustkeyper.com.

## 1. Broker (mobile app)

1. Home → **Add property** → type a name only he sees (e.g. "Flat 402, Madhapur").
2. Choose: **Send link to owner** (owner fills everything, see journey 3) or **Add manually**.
3. Add manually: address (required), size, door facing, parking → rooms, floor, furnishing.
4. Then 4 short steps:
   - **Rent details**: society, area · rent + maintenance (included/extra → amount) · security deposit · brokerage (none / 15 days rent / 1 month rent / fixed amount) · who can rent (tick boxes: Anyone, Family, Bachelor male, Bachelor female, Companies) · pets · available (now / from a date).
   - **Visits**: days (every day / Mon–Fri / Sat–Sun), times (7 am – 11 pm range), visit fee (₹0–500).
   - **Photos** (can skip).
   - **Only for you** (green, never shared): flat/door, owner name and phone, keys, note.
5. Property page → **Share**: WhatsApp message with the property link. The link carries only public details.
6. **Visits** tab: upcoming visits; after the visit he types the tenant's 4-digit code to get the fee.

## 2. Tenant (web, from the property link)

1. Opens the link: photos, rent card, facts, visit-fee rules, "What happens next". **No login.**
2. **Book a visit**: picks a day and hour. Days/hours outside the broker's visit times are greyed. Many people can book the same hour.
3. Signs up: name + mobile → OTP.
4. Pays the visit fee → **Visit booked**: 4-digit visit code, **Add to Google Calendar**, reminder call 1 hour before (to tenant and broker).
5. After the visit: **I want this house** → pays **token ₹15,000** → house is blocked.
6. Shares details for the agreement: full name, email, current address, work, people, Aadhaar. At the same time the owner is asked for their details.
7. When both are in, the **rent agreement** is generated and shared with broker, tenant and owner. Only the broker can change it (changes are agreed offline). Broker marks it final.
8. Tenant and owner **e-sign**.
9. Tenant pays on the platform: **security deposit + first month rent + brokerage**.
10. **Key handover.** After keys are handed over, TrustKeeper releases the brokerage to the broker.

## 3. House owner (web, from the broker's invite; later also WhatsApp bot)

1. Opens the invite: "Your broker asked you to add your house". What we ask, and a privacy note.
2. Signs up: name + **phone or email** → OTP.
3. One question per screen (progress bar, Back goes one question back):
   how many owners → are you one of them → full address → rooms → size and floors → furnishing → rent, maintenance, deposit → who can rent + pets → when free → visit days/times → photos (skip) → Aadhaar of every owner → old/current rent agreement (if any) → bank (cancelled cheque) → who has the keys.
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

1. Accounts + OTP (phone for tenants; phone or email for owners).
2. Data: properties, visits, owners, tenants in Firestore (replace on-phone storage in `Tk2Store`).
3. Payments (Razorpay): visit fee (held), token, deposit/rent/brokerage, refunds and payouts per the money rules. Real money needs Aman's sign-off.
4. WhatsApp: share message, owner invite, owner question-by-question bot, updates.
5. Google Calendar invite (prototype uses a calendar link), reminder call 1 hour before (tenant + broker).
6. Rent agreement generation from templates, broker approval, e-sign.
7. Host the web app on trustkeyper.com (Flutter web) and point `tk2WebApp` in `tk2_link.dart` to it.
