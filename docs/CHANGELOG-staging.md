# TrustKeyper App – Change Log (staging)

Mirror of the Google Doc "TrustKeyper App – Change Log (staging)" (https://claude.ai/code/artifact/1282d8b3-af50-488a-a85c-f1a0bbc47247).
Readers: human engineers and AI agents. One entry per change, newest last. Pushed to `staging` together with each code push.

## Ground rules
- Repo: `desicode-blip/Trustkeyper-Flutter`, app in `apps/flutter_app`
- All collaborative changes go to branch `staging` only. `main` = production, never touched.
- Each entry: date, what/why, behaviour, files, commit, how to test, plus an AGENT RECORD block.

## Change 1 – Onboarding carousel redesign
Date: 2026-10-15 · Commit: `900926f` on `staging` · Status: built on iPhone for review

What & why: the 4 welcome slides become one screen with a large central image and short, emotion-led copy below, replacing the small icon + long text. Goal: faster, warmer first impression.

Behaviour
- Large rounded image card per slide (existing `welcome-*.svg`, same colours); swipe it left/right.
- Auto-advances every 4 s; timer pauses while a finger is on the image and restarts after any swipe or tap.
- Bottom-left: Skip (text-only, muted, tertiary) -> `/login`. Bottom-right: Next -> next slide; on slide 4 it reads "Get started" -> `/login`.
- If slide 4 sits for 4 s, the carousel ends and goes to `/login`.
- Dots animate; title/body cross-fade.

Copy: (1) Paperwork without the stress · (2) Rent that never slips · (3) A home that feels cared for · (4) Everyone on the same page.

Files: `lib/src/features/auth/presentation/auth_screens.dart` (`OnboardingScreen` only). No route, asset or backend change.

Review notes: `flutter analyze` / tests were not run (no Flutter in the cloud sandbox); run `test/design_layout_test.dart` locally. `AGENTS.md` asks for feature branches; by owner's instruction this work is on `staging` directly.

Test: launch app -> onboarding. Check swipe, Next, 4 s auto-advance, Skip, end-of-carousel -> login.

```
AGENT RECORD – Change 1
id: CHG-001
date: 2026-10-15
repo: desicode-blip/Trustkeyper-Flutter
branch: staging   (never main)
commit: 900926f
app_dir: apps/flutter_app
file: lib/src/features/auth/presentation/auth_screens.dart
symbol: OnboardingScreen / _OnboardingScreenState
route: /onboarding -> on finish/skip: context.go('/login')
assets: assets/design/welcome-{agreement,rent,home,trust}.svg (unchanged)
rules:
  - PageView of 4 slides, image card + title/body below
  - autoAdvance = 4s Timer; reset on page change; paused on pointer down, restarted on pointer up/cancel
  - slide 4 + timer expiry or button -> /login
  - Skip (TextButton, AppColors.muted) bottom-left -> /login at any slide
  - Next / 'Get started' (PrimaryButton, width 148) bottom-right
not_changed: routes, assets, backend, other screens
verification: flutter analyze/tests NOT run (no Flutter in cloud); run test/design_layout_test.dart locally
manual_test: launch app; swipe, Next, wait 4s, Skip, finish -> login
```

## Change 2 – Onboarding progress dots + back/forward swipe
Date: 2026-10-16 · Commit: `46aee39` on `staging` · Status: built on iPhone for review

What & why: the 4 s auto-advance is now visible. The current dot stretches into a pill and fills left to right over 4 s; when full, the next slide appears. Gives users a sense of timing and control.

Behaviour
- Current slide's dot = wider pill that fills left -> right in 4 s; completed slides' dots are full, upcoming are empty.
- Fill completes -> advance to next slide; on slide 4 -> `/login`.
- Swipe left = forward, swipe right = back (any slide). Fill restarts on each slide change.
- Finger down on the image pauses the fill; lifting without changing slide resumes it.
- Next / Skip unchanged.

Files: `lib/src/features/auth/presentation/auth_screens.dart` (`_OnboardingScreenState`: `Timer` replaced by an `AnimationController`).

```
AGENT RECORD – Change 2
id: CHG-002
date: 2026-10-16
branch: staging (never main)
commit: 46aee39
file: apps/flutter_app/lib/src/features/auth/presentation/auth_screens.dart
symbol: _OnboardingScreenState (SingleTickerProviderStateMixin; field `progress` AnimationController 4s)
rules:
  - progress completed -> _next(); last slide -> context.go('/login')
  - onPageChanged -> progress.forward(from: 0)
  - Listener pointerDown -> progress.stop(); pointerUp/cancel -> resume if not completed
  - dots: active width 36, others 8; fill = FractionallySizedBox(widthFactor: progress.value) left-aligned; past dots fill 1.0
  - swipe both directions via PageView (default physics)
not_changed: copy, images, Skip/Next buttons, routes
verification: flutter analyze/tests NOT run (no Flutter in cloud)
manual_test: watch dot fill 4s then auto-advance; swipe right to go back; hold finger to pause; finish slide 4 -> login
```

## Change 3 – New onboarding illustrations + one-line "Get started"
Date: 2026-10-16 · Status: built on iPhone for review

What & why: the single-icon images looked thin. Each slide now has a richer flat illustration in the product palette (document + signature + stamp; calendar + coins + bank; house + shield + photo; three people around a trust shield). The "Get started" button wrapped onto two lines; it now widens so the label stays on one line.

Files: `assets/onboarding/welcome-{agreement,rent,home,trust}.svg` (new, replace use of `assets/design/welcome-*.svg` on this screen only); `lib/src/features/auth/presentation/auth_screens.dart` (image path, no colour filter, width 0.94; button width 148 -> 200 on last slide via `AnimatedContainer`).

```
AGENT RECORD – Change 3
id: CHG-003
date: 2026-10-16
branch: staging (never main)
files:
  - apps/flutter_app/assets/onboarding/welcome-agreement.svg, welcome-rent.svg, welcome-home.svg, welcome-trust.svg (320x360, multi-colour, no text/fonts)
  - apps/flutter_app/lib/src/features/auth/presentation/auth_screens.dart (_OnboardingScreenState)
rules:
  - SvgPicture.asset('assets/onboarding/${icon}.svg'), no colorFilter, FractionallySizedBox widthFactor 0.94
  - footer button width: isLast ? 200 : 148 (AnimatedContainer 200ms)
not_changed: assets/design/welcome-*.svg (left in place, now unused by onboarding), copy, timing, routes
verification: SVGs rendered in Chromium and checked visually; flutter analyze/tests NOT run
manual_test: all 4 slides show new art; slide 4 button reads 'Get started' on one line
```

## Change 4 – Login back button, colourful hero, no auto-jump to login
Date: 2026-10-16 · Status: built on iPhone for review

What & why: (1) Login gets a back arrow (existing `ApprovedBackButton`) so users can return to the carousel; it appears only when they arrived from onboarding and returns to slide 4. (2) The skyline behind the logo is now colourful (sky gradient, sun, clouds, four coloured buildings with windows, green ground). (3) The carousel no longer jumps to login by itself: on slide 4 the dot fills and stops; only "Get started" (or Skip) opens login.

Files: `lib/src/core/routing/app_router.dart`, `lib/src/features/auth/presentation/auth_screens.dart`, `lib/src/features/auth/presentation/approved_auth_widgets.dart`.

```
AGENT RECORD – Change 4
id: CHG-004
date: 2026-10-16
branch: staging (never main)
files: apps/flutter_app/lib/src/core/routing/app_router.dart, lib/src/features/auth/presentation/{auth_screens,approved_auth_widgets}.dart
rules:
  - onboarding -> login navigates to '/login?from=onboarding' (Get started and Skip)
  - router: /login builds LoginScreen(onBack: from==onboarding ? go('/onboarding?page=3') : null)
  - /onboarding?page=N -> OnboardingScreen(initialPage: N)
  - LoginScreen.onBack -> ApprovedLoginHero(onBack) shows ApprovedBackButton at left:24 top:14
  - onboarding progress completed on last slide: no navigation
  - ApprovedLoginHero: gradient D9E6FF->FFF1E0, sun, 2 clouds, 4 buildings (blue/green/orange/purple), green ground; logo card unchanged
not_changed: other routes; direct /login (e.g. after sign-out) shows no back arrow
verification: flutter analyze/tests NOT run
manual_test: finish carousel -> wait on slide 4 (stays); Get started -> login; back arrow -> slide 4; hero colourful
```

## Change 5 – Broker Home: calmer layout, nav pill margin
Date: 2026-10-25 · Status: built on iPhone for review

What & why: Home had too many CTAs and little breathing room. (1) Removed "What do you want to do today?" and the language selector (language stays in Settings). (2) "Make rent agreement" is one blue card, title only, whole card tappable, no Start button/subtext. (3) Tiles renamed "Onboard property" and "Add tenant", now slim horizontal tiles. (4) Pending drafts section ("Continue your agreement") sits in a soft grey panel; each draft is a spacious white card, tappable to continue, small delete icon (tooltip "Delete draft") instead of Continue/Delete buttons, 5-step progress bar kept, "Draft" chip removed. (5) Bottom nav: selected light-blue pill no longer touches the outer pill (8px horizontal padding, 2px item padding).

Files: `lib/src/features/broker/presentation/{approved_broker_home,broker_draft_cards}.dart`, `lib/src/core/widgets/approved_navigation.dart`; tests `broker_approval_test`, `broker_updates_test`, `widget_test` updated. Note `BrokerDraftCard` is shared with Agreements list and Unfinished drafts screen, so those also get the new card.

```
AGENT RECORD – Change 5
id: CHG-005
date: 2026-10-25
branch: staging (never main)
files:
  - apps/flutter_app/lib/src/features/broker/presentation/approved_broker_home.dart
  - apps/flutter_app/lib/src/features/broker/presentation/broker_draft_cards.dart (BrokerDraftCard also used in broker_agreements_list.dart, unfinished_drafts_screen.dart)
  - apps/flutter_app/lib/src/core/widgets/approved_navigation.dart
rules:
  - home: no subtext, no language button; greeting in FittedBox(scaleDown, left)
  - rent card: Material(AppColors.primary) + InkWell -> _create('/broker/start'); pending -> grey, text 'Waiting for approval', onTap null
  - tiles: 'Onboard property' -> /broker/property, 'Add tenant' -> /broker/start
  - draft card: InkWell continue -> /broker/progress/<id>; IconButton tooltip 'Delete draft' -> confirm dialog -> repository.remove
  - drafts section wrapper: AppColors.surfaceMuted, radius 28; 'See all N saved drafts' only if N>1
  - nav: container padding horizontal 8; items Padding horizontal 2 (no fixed 74 width)
not_changed: routes, repositories, bell/profile header
verification: flutter analyze/tests NOT run (no Flutter in cloud); tests edited by hand
manual_test: Home shows blue tappable card; tiles renamed; draft card tap continues, trash icon deletes after confirm; Home nav pill has gap on left
```

## Change 6 – Bottom navigation matches approved design
Date: 2026-10-26 · Commit: `f5ae60b` · Status: built on iPhone for review

What & why: bottom bar now matches the Claude Design artboard "1 · One item to continue" (canvas "TrustKeyper Broker Home – redesign"). Selected item is a soft-blue pill inset from the outer pill; unselected items are plain.

Files: `lib/src/core/widgets/approved_navigation.dart` (`ApprovedBrokerNavigation`).

```
AGENT RECORD – Change 6
id: CHG-006
date: 2026-10-26
branch: staging (never main)
commit: f5ae60b
file: apps/flutter_app/lib/src/core/widgets/approved_navigation.dart
rules:
  - outer pill: margin L12 R12 B20, height 76, padding horizontal 8, radius 38, white, border #EEF2F8, shadow rgba(heading,.14) blur 28 offset (0,8)
  - items: Row spaceBetween; icon 24, label 12px (w500 selected / w400), gap 3, item radius 26
  - selected: bg AppColors.primarySoft, color primaryDark, padding H14 V8; unselected: padding H8 V8, color muted, no fill
source_design: Claude Design artboard '1 · One item to continue'
not_changed: labels, icons, routes
verification: flutter analyze/tests NOT run
manual_test: selected tab pill has a visible gap to the outer border on all five tabs
```

## Change 7 – Home "Continue" panel (drafts + bank in one card)
Date: 2026-10-26 · Status: built on iPhone for review

What & why: pending actions are grouped in ONE panel headed "Continue", following Claude Design artboard "2 · Several items". Each unfinished agreement is a row "Complete rent agreement" with the property name as subtext (no progress bar, no delete icon on Home; delete stays in the saved-drafts list). "Add your bank" is a warm row inside the same panel with a "+" circle instead of an Add button. "See all N saved drafts" sits at the bottom of the panel when more than 2 drafts exist.

Files: `broker_draft_cards.dart` (`BrokerDraftSection` + new `_ContinueRow`; `BrokerDraftCard` unchanged and still used by agreements list / unfinished drafts), `broker_shell.dart` (passes `onAddBank`), `approved_broker_home.dart` (standalone bank card only shown when there is no drafts section).

```
AGENT RECORD – Change 7
id: CHG-007
date: 2026-10-26
branch: staging (never main)
files:
  - apps/flutter_app/lib/src/features/broker/presentation/broker_draft_cards.dart
  - apps/flutter_app/lib/src/features/broker/presentation/broker_shell.dart
  - apps/flutter_app/lib/src/features/broker/presentation/approved_broker_home.dart
rules:
  - panel: AppColors.surfaceMuted, radius 28, heading 'Continue' 18/w500
  - draft row: title 'Complete rent agreement', subtitle propertyAddress (or 'Unnamed property'), chevron, tap -> /broker/progress/<id>; max 2 rows
  - bank row (only if !profile.hasBankAccount): amber FFF3E0/F3C98B, 'Add your bank' / 'So we can send your fees', '+' circle, tap -> /broker/bank
  - 'See all N saved drafts' -> /broker/unfinished, only if N > 2
  - panel also renders (bank row only) when there are no drafts but bank is missing
not_changed: routes, repositories, BrokerDraftCard on other screens
source_design: Claude Design artboard '2 · Several items'
verification: flutter analyze/tests NOT run
manual_test: Home with 3+ drafts and no bank shows heading Continue, 2 draft rows, bank row with +, See all link, all inside one panel
```

## Change 8 – Home action buttons: one slim style, no truncated labels
Date: 2026-10-26 · Status: built on iPhone for review

What & why: "Onboard property" was cut to "Onboard prope…". The three actions now share one `_HomeTile` style (icon + label, radius 18). "Make rent agreement" is full width and filled blue with a white arrow circle (primary). "Onboard property" and "Add tenant" sit side by side (flex 6:5); labels use FittedBox(scaleDown) so they shrink instead of showing dots.

```
AGENT RECORD – Change 8
id: CHG-008
date: 2026-10-26
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/approved_broker_home.dart
rules:
  - _HomeTile(primary:true) -> AppColors.primary fill, white text 18/w600, arrow circle; disabled (approvalPending) -> AppColors.muted, label 'Waiting for approval', onTap null
  - secondary tiles: white, border AppColors.border, label 16/w500 in FittedBox(scaleDown), flex 6 (Onboard property) : 5 (Add tenant)
  - routes unchanged: /broker/start, /broker/property, /broker/start
verification: flutter analyze/tests NOT run
manual_test: all three labels fully visible on a 390pt-wide phone
```

## Change 9 – Onboard property: papers, agreement and signing journey
Date: 2026-10-26 · Status: built on iPhone for review (approved design: 110-screen "Onboard property" canvas)

What & why: "Onboard property" now opens two choices only: **Send link to owner** or **Add manually** (the old property form). Sending a link asks the owner by WhatsApp (phone) or email for 8 papers (Aadhaar, phone, email, tenant agreement, rent & deposit, bank, address, key holder). The broker sees each paper as Waiting / Checking / Approved / Not approved (with reason) / Needs you, can ask again (2-hour wait), add it themselves, call, or stop the request. When all are approved the house is created and the broker answers 4 questions (fee type, how owner pays, start date + months, notes). Then: agreement "preparing" → Draft review with key points → change requests both ways (max 3 rounds per point, versions kept) → lock final → stamp paper → printing → sign with a code (owner and broker) → house ready. Only the broker can skip the agreement. Home "Continue" panel lists houses that still need something.

IMPORTANT – what is real and what is pretend: everything is stored on the phone only (`PropertyOnboardingStore`, SharedPreferences key `property_onboardings_v1`). Sending email/WhatsApp, reading papers, writing the draft, buying stamp paper and e-sign are NOT connected. A grey "TEST ONLY" card on each house page has buttons to pretend the owner or our team did the next step. Test sign code: 123456.

```
AGENT RECORD – Change 9
id: CHG-009
date: 2026-10-26
branch: staging (never main)
new_files:
  - apps/flutter_app/lib/src/features/broker/data/property_onboarding.dart  (models + local store + test helpers)
  - .../presentation/onboarding_widgets.dart (shared UI: OnbPage, OnbRow, OnbPill, OnbBanner, OnbStageBar ...)
  - .../presentation/onboarding_start_screens.dart (OnboardChooseScreen, OnboardNewScreen)
  - .../presentation/onboarding_house_screens.dart (PropertySetupScreen, PaperDetailScreen, AskAgainScreen)
  - .../presentation/onboarding_agreement_screens.dart (questions, draft, changes, versions, SignScreen)
  - apps/flutter_app/test/property_onboarding_test.dart
changed_files:
  - core/routing/app_router.dart: /broker/property -> OnboardChooseScreen; /broker/property/manual -> BrokerPropertyScreen (old form); /broker/property/new; /broker/onboarding/:id and children paper/:key, ask/:key, questions, draft, change, changes, change/:cid, versions, sign
  - broker_agreement_steps_screen.dart: "add property" now pushes /broker/property/manual
  - broker_draft_cards.dart: Continue panel also lists open PropertyOnboarding rows (title=homeTitle, subtitle=homeSubtitle)
rules:
  - phases: papers -> questions -> preparing -> review -> printing -> signing -> ready (agreementSkipped jumps questions -> ready)
  - ask-again cooldown 2h (lastAskedAt); change rounds max 3 per clause; wrong sign code locks after 3 tries
  - fee types: days (once), percent (monthly), fixed (monthly), once (one time); percent > 20 asks to confirm; > 100 blocked
not_connected_needs_backend: WhatsApp/email sending, owner web page, automatic paper reading, draft generation, stamp paper, e-sign OTP, Firestore storage (+ rules), push
verification:
  - flutter analyze: No issues found
  - new tests test/property_onboarding_test.dart: 5 passed
  - full suite: 38 tests fail, the SAME 38 fail on the branch before this change (pixel/font tests in this Linux cloud); none are new
manual_test: Home > Onboard property > Send link > fill owner > Sent > open house > tap TEST ONLY buttons through every phase
```

## Change 10 – Onboard property: fixed heading with shadow, floating-label fields, right keyboard
Date: 2026-10-26 · Status: built on iPhone for review

What & why: (1) The heading block (progress bars, step, back button, title, subtitle) stays fixed with a soft shadow below it; the list scrolls under it. (2) Text boxes use the Material floating label: the name sits inside the box and moves up when you tap or type. Done only on the Onboard property screens first, to be approved before the rest of the app. (3) Owner contact: Email shows the full letter keyboard with @ and dot (no spaces); WhatsApp shows a number keypad, digits only, max 10.

```
AGENT RECORD – Change 10
id: CHG-010
date: 2026-10-26
branch: staging (never main)
files:
  - apps/flutter_app/lib/src/features/broker/presentation/onboarding_widgets.dart (OnbPage header container + 10px shadow gradient overlay; OnbTextField uses InputDecoration.labelText, new params formatters, capitalization)
  - apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (ValueKey('contact-<channel>') forces keyboard refresh; email=TextInputType.emailAddress; whatsapp=TextInputType.number + digitsOnly + max 10)
scope: only screens built with OnbPage/OnbTextField (Onboard property journey). Other app screens NOT changed yet - awaiting approval.
verification: flutter analyze: No issues found; test/property_onboarding_test.dart 5 passed
manual_test: Onboard property > Send link: switch Email/WhatsApp, keyboard changes each time; label floats up when typing; scroll list, content slides under the shadowed heading
```

## Change 11 – Taller screens, floating-label fields everywhere, tap outside to deselect
Date: 2026-10-26 · Status: built on iPhone for review

What & why: (1) Onboard property screens no longer show the progress bars, "Step 1 of 4" line or call button; the heading starts at the top, giving more room. (2) The approved floating-label text box (name inside the box, moves up on tap/type, rounded 16) is now the app-wide input style via the theme. (3) Tapping outside a text box closes the keyboard and deselects it, in the whole app.

```
AGENT RECORD – Change 11
id: CHG-011
date: 2026-10-26
branch: staging (never main)
files:
  - lib/src/core/theme/app_theme.dart: inputDecorationTheme = floatingLabelBehavior.auto, label 17 muted, floating label 15 primaryDark, radius 16, focus border 1.5 primary, error borders (design-system rule for ALL inputs)
  - lib/src/app.dart: MaterialApp.router builder wraps app in GestureDetector(translucent) -> FocusManager.primaryFocus.unfocus() on outside tap
  - lib/src/features/broker/presentation/onboarding_widgets.dart: OnbPage no longer renders progress bars, step label, call button (params kept but ignored)
  - lib/src/features/broker/presentation/broker_property_screen.dart: address, size and item-name fields use labelText instead of a separate title above
not_changed: login phone-number field (large special design, hint only), search fields (hint only), dropdowns
verification: flutter analyze No issues; full test suite same 38 failures as before (pixel/font tests), none new
manual_test: any form screen: label sits inside box, floats up on tap; tap blank area -> keyboard closes and box loses focus
```

## Change 12 – Onboard property: "We know this owner" sheet
Date: 2026-10-26 · Status: built on iPhone for review

What & why: The old warning ("already asked / open that request") was a plain confirm box. It is now a soft sheet with the saved owner's card (initial, name, contact, number of houses) and two choices: **Same owner, new house** (keeps the saved name and number and goes on; a new house request is created) or **No, a new owner** (back to the form to change details). It shows when the typed phone/email OR name matches an earlier request (any status).

```
AGENT RECORD – Change 12
id: CHG-012
date: 2026-10-26
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (_askSameOwner, match by contact or case-insensitive name; same owner -> copies saved ownerName/channel/contact into the form and continues to step 1)
verification: flutter analyze No issues found
manual_test: send one request for "Choco"; start another with name Choco -> sheet appears; both buttons behave as above
```

## Change 13 – Spacing on Onboard property screens
Date: 2026-10-26 · Status: built on iPhone for review
What: removed the line "We will ask this person for the papers." on Who is the owner?; space from the fixed heading to the first content is now 32 (was 20) on every Onboard property screen; gap between fields is now 26 (was 18).
```
AGENT RECORD – Change 13
id: CHG-013
date: 2026-10-26
branch: staging (never main)
files: .../broker/presentation/onboarding_widgets.dart (OnbPage list top padding 32), .../onboarding_start_screens.dart (no subtitle on step 0; field gaps 26)
spacing_rule_for_design_system: heading -> first field 32; field -> field 26 (other screens not yet changed)
verification: flutter analyze No issues found
```

## Change 14 – Onboard property: "Is there another owner?" step
Date: 2026-10-26 · Status: built on iPhone for review
What: no subtitle; no name box on the page. The page lists owners already added and a "+ Add another owner" button. Tapping it opens a page "Owner 2/3..." with the SAME form as owner 1 (name, Email/WhatsApp, email or phone with the right keyboard) and a "Save owner" button, then returns to the list. Bottom button is always just "Next". Each extra owner can be removed with the X.
```
AGENT RECORD – Change 14
id: CHG-014
date: 2026-10-26
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (_ownerForm shared by owner 1 and extra owners; _others is a list of {name, channel, contact}; otherOwners saved as "Name · contact" strings)
note: only owner 1 receives the request (extra owners are saved as names with contact); sending to extra owners needs the backend
verification: flutter analyze No issues found; property_onboarding_test passes
```

## Change 15 – Onboard property: same owner flow as the rent agreement
Date: 2026-10-26 · Status: built on iPhone for review
What: replaced my own owner pages with the rent-agreement flow: **How many owners?** (− / number / + stepper, same look) → **Owner 1 details** (Full name, Mobile number with IN +91, Email Address; chips "Owner 1 of 2" when more than one; button "Next: Owner 2") → **We will ask for these** list of papers for this use case → sent. Bottom bar is the agreement's: "‹ Back" + "Next ›". Owner 1 also chooses how we ask for papers (Email · best / WhatsApp); that field is then required. The "We know this owner" sheet still appears after owner 1.
```
AGENT RECORD – Change 15
id: CHG-015
date: 2026-10-26
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (OnboardNewScreen rewritten: _OwnerForm per owner, steps 0 count / 1 owner / 2 check / 3 sent; _bar = Back+Next bar; reuses wizard visuals in broker_agreement_wizard.dart _count/_person)
note: only owner 1 receives the request; other owners saved as "Name · contact"
removed: the old "Is there another owner?" page and "+ Add another owner" button (Change 14)
verification: flutter analyze No issues found; property_onboarding_test passes
```

## Change 16 – Bottom navigation sits lower
Date: 2026-10-27 · Status: built on iPhone for review
What: the floating bar moves down to use the empty space under it. Inside the bar: 12 above the icons, 20 below, so icons are not centred. Gap under the bar is 8; the iPhone home-bar area is no longer left empty below the bar.
```
AGENT RECORD – Change 16
id: CHG-016
date: 2026-10-27
branch: staging (never main)
file: apps/flutter_app/lib/src/core/widgets/approved_navigation.dart (SafeArea bottom:false; margin 12,0,12,8; inner padding 8,12,8,20; fixed height 76 removed)
design_system_rule: bottom nav inner padding top 12 / bottom 20; outer gap to screen bottom 8
verification: flutter analyze No issues found

## Change 17 – Owner details: choose how to reach first
Date: 2026-10-27 · Status: built on iPhone for review
What: on each Owner details page the order is now Full name → "How do we ask for the papers?" (Email · best / WhatsApp, nothing pre-selected) → only after a tap, ONE box slides in (Email Address or Mobile number with IN +91; animated). No star on email: either way is enough. Both grey notes ("We send one short email…" and "Papers go to owner 1…") removed. Each owner has their own choice; owner 1's choice is how the request is sent.
```
AGENT RECORD – Change 17
id: CHG-017
date: 2026-10-27
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (_OwnerForm.channel nullable; _validate requires name + channel + that one contact; AnimatedSize+AnimatedSwitcher 250ms for the contact box)
verification: flutter analyze No issues found; property_onboarding_test passes

## Change 18 – Papers order and auto-ticked contact; owner-side flow recorded
Date: 2026-10-27 · Status: built on iPhone for review
What: papers now go in this order: House address, Aadhaar, Phone, Email, Tenant agreement, Rent and deposit, Bank, Key holder. The phone or email we used to ask the owner is ticked (Approved) from the start. Old requests are re-sorted to this order.

OWNER-SIDE FLOW (to build in the house owner's app; the broker app needs few changes):
1. How many owners does the property have that you want registered with us?
2. If one: are you that owner? If yes, pre-fill email, phone and other details we already have.
3. Papers in order: address (creates the house) → Aadhaar → phone (auto-ticked if known) → email (auto-ticked if known) → tenant agreement (now or in the past, if any) → expected rent and deposit → bank → key holder.

```
AGENT RECORD – Change 18
id: CHG-018
date: 2026-10-27
branch: staging (never main)
files: data/property_onboarding.dart (PaperKeys.all order; papers sorted in constructor; create() approves email or phone paper from contact), presentation/onboarding_house_screens.dart (test-panel and waiting checks treat approved as ok), presentation/onboarding_start_screens.dart (check list text and order)
not_built: owner-side screens (owner count, "are you the owner", pre-fill) - need owner app + backend
verification: flutter analyze No issues found; property_onboarding_test 5 passed
