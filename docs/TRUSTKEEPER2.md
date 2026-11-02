# TrustKeeper 2 – broker launch app

A small, separate app for brokers so we can launch fast. It lives in the same
Flutter project and reuses the house screens, colours and buttons.

**Entry point:** `apps/flutter_app/lib/main_tk2.dart` (no Firebase in this build)
**Code:** `apps/flutter_app/lib/src/tk2/`
**Tests:** `apps/flutter_app/test/tk2/tk2_test.dart`

## What the broker can do

1. **First open** – the main app's splash and welcome carousel as they are, then the main
   app's "Log in or sign up" look with name + mobile (kept on the phone; no OTP yet).
2. **Home** – the main app's broker home as it is (profile, logo, bell, "Namaste", slim tiles,
   "Stuck? Call us", floating bottom bar Home · Visits · Profile). Main tile: **Add property**.
   Below: compact property rows – small photo left; right: "3 BHK · name", rent with
   "incl. maintenance" or "+ ₹X maintenance", sft · furnishing, Family/Bachelors · pets ·
   available from. Until the broker adds a property, one **example property**
   (Flat 402, Madhapur) is shown with an "Example" tag and a hint. Adding the first own
   property removes it and shows "We removed the example".
3. **Add property** – the same screens as the main app (`BrokerPropertyScreen` with
   `startNew`, `showStepLabel: false`): name → add manually / sale deed / old agreement →
   address → rooms → things → check. Then a new screen: **rent, deposit, maintenance (included or extra),
   who can rent (Family / Bachelors / Anyone), pets, available from, visit fee (₹100 / ₹150 / ₹200) and up to 10 photos**.
4. **Property page** – photo slider, rent / deposit / visit fee, facts, things in the house,
   visits for this property. Menu: edit rent and photos, edit house details, remove.
5. **Share** – one tap: message preview → **Share on WhatsApp** (opens WhatsApp with the
   message) or **Copy message**. The message has the facts, rent and the link
   `https://trustkeyper.com/v/<id>`.
6. **Customer view** – what the customer sees when they open the link: photos, rent,
   facts, "fee is kept safe" note, broker name, **Book a visit · ₹fee** → pick a day (next 7)
   and time (10 am – 7 pm, past times greyed) → name + phone → pay (test payment) →
   **Visit booked!** with a 4-digit visit code.
7. **Visits tab** – "Held for you" and "Yours" totals, Coming up / Earlier lists.
   Tap a visit: call the customer, **Visit done · get ₹fee** (type the customer's code →
   fee is the broker's), **Did not come** or **Cancel visit** (fee goes back to the customer).

## Money rule

booked → fee **held** → visit done with the right code → **released** to the broker
booked → cancelled / did not come → **refunded** to the customer

## What is pretend in this build (backend work)

| Now (on the phone) | Needed for launch |
| --- | --- |
| All data in SharedPreferences key `tk2_store_v1` (`Tk2Store`) | Firestore: `brokers/{uid}`, `listings/{id}`, `visits/{id}`; broker login (phone OTP) |
| Photos are local file paths | Upload to Firebase Storage, save URLs |
| The share link page does not exist | Public web page at `trustkeyper.com/v/{id}` built from the Customer view screens (`tk2_customer.dart`) |
| Payment sheet says "Test payment" | Razorpay test mode → order per visit; hold in our account (Route/escrow or manual payout) |
| Visit code checked on the phone | Cloud Function `confirmVisit(visitId, code)` → mark released → payout to broker |
| Cancel / did not come just change status | Cloud Function → Razorpay refund |
| No notifications | WhatsApp/SMS to broker on new booking, reminder to both before the visit |

Methods to swap for backend calls: `Tk2Store.load`, `setBroker`, `saveProperty`,
`saveListing`, `removeListing`, `bookVisit`, `confirmVisit`, `closeVisit`.

Real money needs Aman's business/compliance sign-off first (see AGENTS.md).

## Installing on a phone as a separate app

The repo's iOS project is unchanged (bundle id `com.trustkeyper.mobile`). To install
TrustKeeper 2 next to the main app, the Mac build was switched locally:

- `ios/Flutter/Generated.xcconfig` → `FLUTTER_TARGET=lib/main_tk2.dart`
- `ios/Runner.xcodeproj/project.pbxproj` → Runner `PRODUCT_BUNDLE_IDENTIFIER = com.trustkeyper.tk2`
- `ios/Runner/Info.plist` → `CFBundleDisplayName` = TrustKeeper 2

From the command line: `flutter run -t lib/main_tk2.dart` (Android/iOS).
Switch these back to build the main app. A proper flavor setup is a later task.

## Later (not in this build)

Owner and tenant side over WhatsApp/email: documents one by one, signing link with a
"call broker" option; property onboarding from the main app.
