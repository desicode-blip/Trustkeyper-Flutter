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

## Change 19 – "For how many months?" has an Other option
Date: 2026-10-27 · Status: built on iPhone for review
What: next to 11 / 12 / 24 / 36 months there is now an **Other** chip. It opens a small sheet with a number box (1 to 120). After saving, the chip shows the number, e.g. "18 months", and stays selected.
```
AGENT RECORD – Change 19
id: CHG-019
date: 2026-10-27
branch: staging (never main)
file: apps/flutter_app/lib/src/features/broker/presentation/onboarding_agreement_screens.dart (_askMonths, Other chip)
verification: flutter analyze No issues found

## Change 20 – More than 11 months: registered agreement notice
Date: 2026-10-27 · Status: built on iPhone for review
What: choosing 12, 24, 36 or an Other number above 11 shows a small sheet: "Registered agreement needed – an agreement for more than 11 months must be registered. We cannot make that in this app yet." Buttons: **Use 11 months** (sets 11) or **Close** (keeps the earlier choice). Registered agreements are out of scope for now.
```
AGENT RECORD – Change 20
id: CHG-020
date: 2026-10-27
branch: staging (never main)
file: onboarding_agreement_screens.dart (_pickMonths; used by chips and Other)
rule: duration > 11 months => cannot be selected; registered agreement not supported yet
verification: flutter analyze No issues found

## Change 21 – "We know this owner": complete both paths
Date: 2026-10-27 · Status: built on iPhone for review
What: 
- **Same owner, new house**: keeps the saved name and contact and COPIES the ID proofs from the earlier request: Aadhaar, phone, email (ticked, with the old values). House papers (address, tenant agreement, rent and deposit, bank, key holder) are asked again because they belong to the new house. A new house request is created.
- **No, a new owner**: goes on to the next step with what was typed. NOTHING is copied except the phone or email just typed (ticked). Aadhaar and the rest are asked fresh.
- Closing the sheet keeps you on the page.
```
AGENT RECORD – Change 21
id: CHG-021
date: 2026-10-27
branch: staging (never main)
files: data/property_onboarding.dart (create(carryFrom) copies approved aadhaar/phone/email), presentation/onboarding_start_screens.dart (_carryFrom set on same owner, cleared otherwise; new owner no longer returns to the form), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test 6 passed

## Change 22 – House with more than one owner: a tab for each owner
Date: 2026-10-27 · Status: built on iPhone for review
What: when the broker picks 2 or more owners, the house page ("Setting up") shows a **tab for each owner** (Owner 1 · Ravi, Owner 2 · Sita). Each tab shows that owner's own status (Done / 1 needs you / Waiting), own papers, own reminder, own contact. With one owner the page is exactly as before.
- **Owner 1 tab** = Aadhaar, phone, email AND the house papers (address, tenant agreement, rent and deposit, bank, key holder). House papers are asked once, from the main owner.
- **Other owner tabs** = Aadhaar, phone, email only. A row "House papers come from Ravi" jumps back to Owner 1.
- Top banner sums up everyone: "Needs you: Ravi (2), Sita (1)" / "1 of 2 owners done. Waiting for Sita" / "All papers from all owners are approved".
- **Continue** appears only when every owner's papers and the house papers are approved.
- Each owner is asked in their own way (email or WhatsApp). Their typed contact is ticked at the start. If an extra owner has the same phone/email as someone from an earlier house, their approved ID proofs are kept.
Edge cases built:
1. Same person twice (same name, phone or email) is blocked in the start flow, in "Add owner", and in "Change contact".
2. "+ Add owner" chip (papers stage, up to 10 owners): asks the new owner for papers.
3. "Remove X from this house" for other owners (with a confirm). The main owner cannot be removed (use Stop this request). If the removed owner was the last one waiting, Continue appears.
4. Not replying: remind (2 hour wait counted per owner), call, change contact are per owner.
5. Ask again / paper pages open for the right owner (`?o=N`); if that owner was removed meanwhile, a plain "owner was removed" page shows.
6. Questions stage lists every owner as approved.
7. Signing: every owner must sign. Rows per owner, banner "1 of 2 owners have signed". The house becomes Ready only when the broker and all owners have signed.
8. Home "Continue" panel names the owner whose paper needs you. Older saved requests (other owners stored as text) still open.
Not built (needs more thought): making Owner 2 the main owner if Owner 1 is unreachable; adding owners after the papers stage; changes on the draft asked by a specific owner (still shown as "the owners").
```
AGENT RECORD – Change 22
id: CHG-022
date: 2026-10-27
branch: staging (never main)
files: data/property_onboarding.dart (CoOwner model with own papers/signed/lastAskedAt; PaperKeys.personal; owner-aware getters; store.addOwner/removeOwner; create(coOwners) keeps known proofs; test helpers per owner; old otherOwners strings migrate), presentation/onboarding_house_screens.dart (_ManyOwnersPapers tabs, _AddOwnerSheet, per-owner reminder/contact/paper/ask screens, signing rows), presentation/onboarding_start_screens.dart (CoOwner objects, duplicate-owner checks), presentation/onboarding_agreement_screens.dart (all owners sign), core/routing/app_router.dart (?o= owner on paper and ask routes), test/property_onboarding_test.dart
rule: house papers come only from owner index 0; allPapersDone and allOwnersSigned require every owner
verification: flutter analyze No issues found; property_onboarding_test 9 passed

## Change 23 – "Documents" wording, read the full agreement, call our team
Date: 2026-10-27 · Status: built on iPhone for review
What:
- **Words:** the first stage is now called **Documents** (was Papers). Every "papers/paper" the broker sees is now "documents/document" (the stamp paper stays "stamp paper"). The line on "Making your agreement" now reads "We are writing it using the documents from the owner and what you told us."
- **Read the full agreement:** in the agreement stage (questions, making the agreement, review) a soft-blue button **Read the full agreement** sits as the second button, under the main one. It uses the same look as "Read full agreement" in the rent agreement review. It opens a **Full agreement** page between the **owner(s) and the broker**: who signs, the details in yellow cards (green + "Changed" when changed after the first draft), and 8 plain-word clauses. Before the final draft exists it shows how the agreement will read, and anything not decided yet says "Not decided yet".
- **Who is the broker:** the name of the registered broker who is logged in (our own team or an outside broker). If no name is available it says "You (the broker)".
- **Call our agreement team:** a call button next to **Cancel agreement** (review), and on "Making your agreement" and the questions screen. It calls the company number already used in the app (+91 80885 16875).
Not built: the real legal text (the clauses are plain-word template wording, our team confirms the legal words); a broker company name from a registered profile (only the logged-in name is used); a separate number for the agreement team.
```
AGENT RECORD – Change 23
id: CHG-023
date: 2026-10-27
branch: staging (never main)
files: presentation/onboarding_widgets.dart (OnbReadFullButton, stage name Documents), presentation/onboarding_house_screens.dart (_footer inserts read-full as 2nd button in questions/preparing/review; _callTeamButton; wording), presentation/onboarding_agreement_screens.dart (OwnerAgreementScreen, _brokerName from FirebaseAuth displayName), presentation/onboarding_start_screens.dart + data/property_onboarding.dart (wording), core/routing/app_router.dart (route /broker/onboarding/:id/agreement), test/property_onboarding_test.dart
rule: only string literals were renamed; code names (papers, PaperKeys, routes) unchanged
verification: flutter analyze No issues found; property_onboarding_test 10 passed
```

## Change 24 – More than one owner: back to the earlier page, with browser-style tabs
Date: 2026-10-27 · Status: built on iPhone for review
What: the multi-owner Documents page goes back to the same layout as the one-owner page (banner, list of documents, "not replying?", Stop this request). On top there are **tabs like a desktop browser**: "Owner 1 · CTC", "Owner 2 · Sita" and a **+** to add an owner. The open tab joins the page; a small icon on each tab shows done, needs you or waiting. The banner now belongs to the open tab only ("Asked just now. Waiting for Sita."). Removed: the summary banner for everyone, the owner card, the big tab cards.
```
AGENT RECORD – Change 24
id: CHG-024
date: 2026-10-27
branch: staging (never main)
file: presentation/onboarding_house_screens.dart (_ManyOwnersPapers: _tab as browser tab using outer/inner box, no summary banner, no owner card), test/property_onboarding_test.dart
note: Flutter cannot paint borderRadius with a non-uniform Border, so the tab is an outer coloured box with an inner box
verification: flutter analyze No issues found; property_onboarding_test 10 passed
```

## Change 25 – "What is your fee?": No fee, and Decide on every deal
Date: 2026-10-28 · Status: built on iPhone for review
What: two more options under Days of rent / Percent / Fixed / One time: **No fee** ("We do not charge the owner") and **Decide on every deal** ("Ask me later, deal by deal"). Picking either needs no number and skips the next question (how the owner pays), going straight to "When does it start?". Back from there returns to the fee question. The check page, key points, and the full agreement show "No fee" or "Decided on every deal"; the "how owner pays" lines are hidden. Clause 3 of the full agreement says the broker charges no fee, or that the fee is agreed for every deal in writing before that deal starts.
```
AGENT RECORD – Change 25
id: CHG-025
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (AgreementAnswers feeType none/later, feeHasNoAmount, feeSummary, payWayText), presentation/onboarding_agreement_screens.dart (_feeTypes, _next skips pay-way step, back, check page, keyPoints, clause 3), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test passed
```

## Change 26 – Fee number box opens under the option you picked
Date: 2026-10-28 · Status: built on iPhone for review
What: on "What is your fee?", the box for the number (days, percent, rupees) now opens **right under the option you tap**, with a short slide. The picked option stays where it is and the options below move down. "No fee" and "Decide on every deal" open no box. Before, the box was at the very end of the list.
```
AGENT RECORD – Change 26
id: CHG-026
date: 2026-10-28
branch: staging (never main)
files: presentation/onboarding_agreement_screens.dart (fee step: field inside the option loop with AnimatedSize), test/property_onboarding_test.dart
rule (design system): when an option needs an entry field, the field opens directly under that option
verification: flutter analyze No issues found; property_onboarding_test 11 passed
```

## Change 27 – Fee options in three groups, and days of rent every month
Date: 2026-10-28 · Status: built on iPhone for review
What: "What is your fee?" now has three groups with small headings.
- **Paid one time:** Days of rent, one time (example 15 days, once) · Fixed amount, one time.
- **Paid every month:** **Days of rent, every month** (new, example 3 days each month) · Percent of rent · Fixed amount.
- **No fee now:** No fee · Decide on every deal.
The new option asks "How many days of rent?" (up to 30) and shows the money each month, e.g. "3 days of rent every month (₹ 3000 each month)". It works like the other options: the box opens under it, and the next question (how the owner pays) is asked as before.
```
AGENT RECORD – Change 27
id: CHG-027
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (feeType daysMonthly in feeSummary), presentation/onboarding_agreement_screens.dart (_feeGroups with headings, validation max 30 days), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test passed
```

## Change 28 – Agreement stage start: one button only
Date: 2026-10-28 · Status: built on iPhone for review
What: on the page shown after all documents are approved, the bottom now has **one button: "Next: collaboration details"** (opens the questions about fee, start date and so on). Removed here: "Read the full agreement" and "Skip agreement". "Read the full agreement" is still on the "Making your agreement" and review pages. Because "Skip agreement" is gone from this page, the only way to skip the agreement is no longer offered (the "Make the agreement now" option for houses skipped earlier stays).
```
AGENT RECORD – Change 28
id: CHG-028
date: 2026-10-28
branch: staging (never main)
files: presentation/onboarding_house_screens.dart (_footerCore questions, _footer no longer adds read-full for questions), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test passed
```

## Change 29 – "How does the owner pay you?" follows the fee you chose
Date: 2026-10-28 · Status: built on iPhone for review
What: the words say **deduct** now, and the options depend on the fee from the screen before. All money moves on our app (safer), so:
- **Fee paid one time** (days of rent, fixed amount): option 1 is **"We deduct it from the first month's rent"** (picked by default). "Owner pays you directly" and "Owner pays once, at signing" are shown greyed out with "Not available now. Payments stay on our app, it is safer." They cannot be tapped.
- **Fee paid every month** (days of rent, percent, fixed): **"We deduct it from every month's rent"** and **"Owner pays you directly"**. The signing option is gone.
- No fee / decide on every deal: this question is still skipped.
The check page, key points and full agreement use the same words.
```
AGENT RECORD – Change 29
id: CHG-029
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (feeIsOneTime, payWayText by fee kind), presentation/onboarding_agreement_screens.dart (_payWays by fee kind with canPick, default cut for one time), test/property_onboarding_test.dart
rule: one-time fee => only deduct can be picked; monthly => deduct or direct; 'signing' kept only so old saves still read
verification: flutter analyze No issues found; property_onboarding_test passed
```

## Change 30 – The owner agreement now reads and edits like the rent agreement
Date: 2026-10-28 · Status: built on iPhone for review
What: "Read the full agreement" now uses the same flow as the rent agreement review, this time between the **owner and the broker** (the broker is you, or our company when it is us).
- **Your agreement** (paper page): title, "Draft N", a line "Yellow = details you added" (and "Green = just changed" once something changed). Names, address, fee, how it is paid, rent, deposit, start date and months are highlighted. A gap shows grey dots. Notes appear as clause 9 when there are notes.
- **Edit** (while the agreement is being made, or in review): opens **What to change?** with *Your fee*, *Start date and length*, *Other notes*. Each opens a pre-filled screen with a yellow **"Editing agreement · Cancel"** strip and the button **Save and see agreement**. A short toast says what changed.
- **Edge cases from the rent flow:** leaving with unsaved changes asks "Leave without saving?"; empty or wrong fee shows a red message and "Fix the red box to save"; nothing changed shows "Nothing changed yet" and the button becomes "Back to agreement"; changing a monthly fee to a one-time fee while the owner was set to pay directly asks "Change how the owner pays too?"; after the draft is sent, any change asks "Everyone must say yes again" and makes a new draft (Draft 2, 3...) that the owner must approve again.
- **N changes · See all:** lists what changed (old text struck through, new text below) with **Undo** for each part. Changing a part back to how it was in the first draft removes it from the list.
- **Send:** "Send to Ravi" (or "Send to these 2 people?" with every owner shown) asks first, then shows **Agreement sent!** with what happens next. The same confirm is used by the button on the house page.
- Not built: download icon (nothing to download yet), owners/rent/deposit editing here (they come from the owner's documents, change them on the house page), the "check everything" card list with Change links, sending per person by WhatsApp or email.
Needs the backend later: really sending the draft, and the owner saying yes or asking a change.
```
AGENT RECORD – Change 30
id: CHG-030
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (AgreementEdit, edits[], AgreementAnswers groups/groupText/withGroup/sameGroup, store changeAgreementPart/undoAgreementPart/_newDraftIfSent), presentation/onboarding_agreement_screens.dart (OwnerAgreementScreen rewritten as paper reader, AgreementEditScreen via _QuestionsBody(part:), AgreementSentScreen, confirmSendDraft/sendDraftWithConfirm/confirmNewDraft), presentation/onboarding_house_screens.dart (Send uses confirm), presentation/onboarding_widgets.dart (OnbPage.topBanner), core/routing/app_router.dart (routes edit?part=, sent), test/property_onboarding_test.dart
source design: v2 canvas page "06 Broker Review, edit and send": RV2, RV3, RV5, EA1, EA2, EA3, EA4, EA5, EA6, EA7, EA12, EA15
rule: edits only tracked while phase=review; one change row per part (fee/dates/notes); after draftSent a change bumps draftNo and clears ownerAgreedFinal
verification: flutter analyze No issues found; property_onboarding_test 18 passed
```

## Change 31 – Which agreement template to use (rules only)
Date: 2026-10-28 · Status: not on the phone yet (no screen changed)
What: you shared 4 template agreements (percent every month · 3 days every month · 15 days once a year · NRI) and 2 Google Drive links. The app now knows **which template fits**: percent → monthly percent; days every month → monthly days (needs rent on our app); days one time → yearly 15 days; NRI owner → NRI template; other broker, no fee, decide each deal, fixed amounts → "our team will pick". It also knows the Drive file ids of the two linked templates. Nothing is fetched yet and no screen shows it: fetching private Google Docs needs the backend (see docs/AGREEMENT-TEMPLATES.md, which also lists placeholders, gaps in the docs and open questions).
```
AGENT RECORD – Change 31
id: CHG-031
date: 2026-10-28
branch: staging (never main)
files: data/agreement_templates.dart (new), test/property_onboarding_test.dart, docs/AGREEMENT-TEMPLATES.md (new)
rule: template text is always fetched from Drive at agreement time, never copied into the app
verification: flutter analyze No issues found; property_onboarding_test 19 passed
```

## Change 32 – Percent template link added
Date: 2026-10-28 · Status: not on the phone yet (no screen changed)
What: you shared the Drive link for the **percent of rent** template. The app now knows its file. It is a Word file in Drive (not a Google Doc), so it will be read a different way later. It is also a filled agreement of one real owner (9.1%, Aug 2025 dates), so it needs placeholders before use. The 3-days template link is still missing.
```
AGENT RECORD – Change 32
id: CHG-032
date: 2026-10-28
branch: staging (never main)
files: data/agreement_templates.dart (monthlyPercent.driveDocId, isWordFile, exportUrl for Word files), test/property_onboarding_test.dart, docs/AGREEMENT-TEMPLATES.md
verification: flutter analyze No issues found; property_onboarding_test 19 passed
```

## Change 33 – Blank copies of the 4 agreement templates kept in the repo
Date: 2026-10-28 · Status: not on the phone yet (documents only)
What: the Drive links could not be shared as links, so copies are kept instead. Each was cleaned of personal details (names, addresses, PAN, bank, phone, email, old dates and fee numbers) and the gaps are written as `[PLACEHOLDERS]`. They sit in `docs/agreement-templates/`. The "fetch from Drive each time" plan stays for later. Until then these copies are the source, and they change only when Aman asks.
```
AGENT RECORD – Change 33
id: CHG-033
date: 2026-10-28
branch: staging (never main)
files: docs/agreement-templates/{README,monthly_percent,monthly_days_3days,yearly_15days,nri_hybrid}.md, docs/AGREEMENT-TEMPLATES.md
rule: copies are replaced only on Aman's request; personal details never stored in templates
verification: grep for old names, PAN, bank, phone, email, years returned nothing
```

## Change 34 – The agreement now uses the real template, filled with your inputs
Date: 2026-10-28 · Status: on the phone after the next build
What: "Your agreement" (and the page you send to the owner) no longer shows the short plain-words page for fees we have a template for. It shows the **real agreement words** from the right template, with your inputs filled in:
- **Yellow** = told by you (owners' names, house address, fee, start date, months, owner email, today's date as the signing date, notes).
- **Green** = just changed. **Grey** = still empty; shown with its label such as [FATHER’S / SPOUSE’S NAME]. A bar at the top says "N details are still empty" and lists them.
- Several owners: every owner gets their own line and signature name. Notes you add appear as "ADDITIONAL TERMS" before the signing page.
- Fee wording follows your numbers (percent, or any number of days; the 3-days template changes "ten percent (10%)" for you). Months from your answer replace "one (1) year" for the first term (12 months keeps "one (1) year"); end date is worked out.
- Which template: percent → percent template; days every month → 3-days template; days one time → 15-days template. Assumes TrustKeyper is the broker and the owner is not an NRI (nothing asks that yet, so the NRI template is not picked). Fixed amount, no fee, decide each deal still show the plain-words page with a note.
- Template files are now bundled in the app (assets/agreements) as copies, not fetched from Drive. Edit them only when asked.
Not yet asked, so grey: Mr/Ms, relation and father's/spouse's name, age, owner's own address, property description and area, fixtures, owner bank, switch-deadline date (15-days).
```
AGENT RECORD – Change 34
id: CHG-034
date: 2026-10-28
branch: staging (never main)
files: data/agreement_filler.dart (new), presentation/agreement_paper.dart (new), data/agreement_templates.dart (fileName), presentation/onboarding_agreement_screens.dart (_body, legend), assets/agreements/*.md (moved from docs, 15-days owner lines split per owner, fixtures list blanked), pubspec.yaml (assets), test/agreement_filler_test.dart (new), test/property_onboarding_test.dart
rule: fill only from user inputs; unknown = grey gap; template words never edited by code except term/fee-days phrases listed in docs/agreement-templates/README.md
verification: flutter analyze No issues found; agreement_filler_test + property_onboarding_test 24 passed
```

## Change 35 – Agreement ready, send for signing, sent, home notices
Date: 2026-10-28 · Status: on the phone after the next build
What changed, in the order the broker sees it:
1. **Making your agreement:** no "Read the full agreement" button any more (it is not written yet).
2. **Agreement ready:** the spinner becomes a **green tick** with "Your agreement is ready. Read it once. Then send it for signing." One button: **Next**. The home page shows a green notice **"Agreement is ready · house · Review it"**.
3. **After Next:** one main button **Send for signing**. Under it two buttons: **Read full agreement** and **Read only key points**. Changes and Versions moved to a small **More** list (the "Draft 1" row only shows after sending).
4. **Send for signing:** the confirm sheet says "Send to Ravi for signing?" and the button "Yes, send for signing". The reader page button is also "Send for signing".
5. **Agreement sent:** tick screen "Agreement sent" with what happens next. Main button **Go to home** (was "Go to this house"); second button "See the agreement".
6. **Home:** an amber notice **"Under review by {owner} · house · Agreement sent for signing"** stays on top until the owner says yes. The Continue row also says "Agreement under review".
```
AGENT RECORD – Change 35
id: CHG-035
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (readyAck, agreementJustReady, underOwnerReview, homeTitle/homeSubtitle), presentation/onboarding_house_screens.dart (_agreementReady, footer, More), presentation/onboarding_agreement_screens.dart (confirm texts, AgreementSentScreen), presentation/broker_draft_cards.dart (_AgreementNotice), test/property_onboarding_test.dart
rule: readyAck defaults true for old saves; only testDraftReady sets it false
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 26 passed
```

## Change 36 – Status first, Make changes, Draft 2, 3, 4...
Date: 2026-10-28 · Status: on the phone after the next build
- **Draft / Changes / Versions card removed from the top.** They are now small grey links at the very end of the page under "More" (Key points · Changes · Versions · Call our agreement team · Cancel agreement).
- **After you send:** the page shows **"Draft N status"** first: **Sent** (when) → **Opened** (Yes / Not yet) → **Answer** (Waiting / asked a change / agreed).
- **Make changes** button (until the owner signs): opens "What to change?" (fee, start date and length, notes). Saving makes the **next draft** (Draft 2, then 3, 4...). It is **not** sent by itself: the page says "Draft 2 has your changes. Read it, then send it for signing." and **Send for signing** sends it. Changes made before sending stay in the same unsent draft (no extra numbers). Every send of a new version is the next draft, and the owner must say yes again.
- After you send, the green "just changed" marks start fresh from that draft.
```
AGENT RECORD – Change 36
id: CHG-036
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (_newDraftIfSent: draftSent=false, draftNo+1), presentation/onboarding_house_screens.dart (_review rewritten, _moreLinks, Make changes in footer), presentation/onboarding_agreement_screens.dart (showWhatToChange public, confirmNewDraft text, send clears edits), test/property_onboarding_test.dart
rule: a change after sending makes draftNo+1 and draftSent=false; send sets draftSent=true and clears edits
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 27 passed
```

## Change 37 – Email / WhatsApp: box only after you pick, cursor jumps in, WhatsApp logo
Date: 2026-10-28 · Status: on the phone after the next build
- **Owner details** and **Add another owner**: nothing is picked at first and there is no contact box. Tap **Email · best** or **WhatsApp** and the box appears with the cursor already in it, so the keypad opens by itself: letters with @ for email, numbers for WhatsApp. Switching between the two moves the cursor to the new box.
- **Add another owner** no longer starts with Email already picked. If you press the button without picking one, it says "Pick one".
- The WhatsApp button now shows the **WhatsApp logo** (green) instead of a chat bubble. One shared button is used in both places.
```
AGENT RECORD – Change 37
id: CHG-037
date: 2026-10-28
branch: staging (never main)
files: presentation/onboarding_widgets.dart (OnbChannelChip, OnbTextField.focusNode), presentation/onboarding_start_screens.dart (_pickChannel, focus nodes, old _ChannelChip removed), presentation/onboarding_house_screens.dart (_AddOwnerSheet channel nullable, box after pick, focus), assets/design/whatsapp.svg (Simple Icons, CC0, fill #25D366), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 28 passed
```

## Change 38 – Don't wait for the owner: add collaboration details while papers come
Date: 2026-10-28 · Status: on the phone after the next build
- **Documents stage, still waiting:** new main button **Add collaboration details** with the line "{owner} can take their time. You can go on." It opens the same questions (What is your fee? → how the owner pays → start date → anything else → check).
- The last button there says **Save details** (not "Make the agreement") while documents are still coming. Saving keeps the house in Documents, shows "Saved. We make the agreement when {owner} sends the documents." and a green **Collaboration details · Saved** row on the house page (tap to change). The footer then offers **Change collaboration details**.
- **When all documents are approved:** if details are already saved, the button is **Make the agreement** and goes straight to making it (no questions again). If not, it is **Continue** as before.
```
AGENT RECORD – Change 38
id: CHG-038
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (hasAgreementDetails), presentation/onboarding_house_screens.dart (papers footer, _detailsSaved), presentation/onboarding_agreement_screens.dart (_send keeps papers phase, Save details label), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 29 passed
```

## Change 39 – Details saved, still waiting for the owner: main button "Go to home"
Date: 2026-10-28 · Status: on the phone after the next build
- On the house page, after the collaboration details are saved and the owner is still sending documents, the bottom button is now **Go to home**. The "Change collaboration details" button is removed; change them from the green **Collaboration details · Saved** row on the page.
```
AGENT RECORD – Change 39
id: CHG-039
date: 2026-10-28
branch: staging (never main)
files: presentation/onboarding_house_screens.dart (papers footer when hasAgreementDetails), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 29 passed
```

## Change 40 – Send for signing rebuilt from the canvas (page 06: RV3–RV6, home HM1)
Date: 2026-10-28 · Status: on the phone after the next build
The journey after "Send for signing" now follows the artboard:
1. **Confirm (RV3):** "Send to Ravi for signing?" with every owner, plus a line saying who signs last: "TrustKeyper signs last, after the owners." (or "You sign last").
2. **Send to each owner (RV4) – new screen:** "Send on (you can pick both)" ticks for **WhatsApp** (logo) and **Email**. One card per owner: name · Owner N, what we have for them (WhatsApp / Email, or a warning "No WhatsApp number" / "No email"), and **Send to Ravi**. After sending: green **Sent** pill and "On email · just now". The bottom says "1 owner not sent yet" and the button changes from **Send to everyone** to **Done**. A **Signs at the end** card shows the manager: **TrustKeyper · Manager** or **You · Broker**, with **Change**.
3. **Agreement sent (RV5):** green tick, "Draft 1 sent!", and a joined timeline: Sent → They read it (Now) → They say yes → Everyone signs ("Ravi and TrustKeyper"). Buttons: **Go to home** and **See who replied**.
4. **Who replied (RV6) on the house page:** Rent · Starts · Your fee strip, **Who said yes 1 of 2** bar, one row per owner (Said yes / Seen, no reply / Not opened / Asked a change) with **Remind** (or **See** for a change), and the manager row "Signs last". Bottom: **Remind all 2** (soft green), Read full agreement, Make changes.
5. **Home (HM1):** the amber notice now says "1 of 2 said yes".
6. **Signing:** the manager row says **TrustKeyper · Signs for the company** or **You · Your turn**. "Sign now" shows only when you sign; when TrustKeyper signs, the test button "TrustKeyper signs" finishes it.
Edge cases covered: owner with no WhatsApp number or no email (warning, Send off for that owner until the other tick is on), both ticks off ("Pick WhatsApp or email above."), send to some then Done, leaving after sending to some ("Leave this page?" → marks as sent), remind once an hour ("Reminded · 5 min ago"), owner asks a change (row says so, "See"), all say yes (Lock and continue), a change after sending makes the next draft and clears every reply, more than one owner, old saves (shown as "Not opened"). Not possible yet without the backend: real sending, delivery failures, "not on WhatsApp", email bounces, copy link.
```
AGENT RECORD – Change 40
id: CHG-040
date: 2026-10-28
branch: staging (never main)
files: data/property_onboarding.dart (OwnerReply, replies[], signsAs, replyAt/withReply/yesCount/sentCount/trustkeyperSigns/ownerPhoneAt/ownerEmailAt, store sendDraftTo/finishSending/remindOwner/setSignsAs/testOwnerOpens/testOwnerSaysYes/testManagerSigns; _newDraftIfSent clears replies), presentation/send_for_signing_screens.dart (new: SendToEachScreen, AgreementSentScreen moved here, SignTimeline, WhoReplied, ManagerSignRow, pickWhoSigns), presentation/onboarding_agreement_screens.dart (confirm sheet scrolls + manager line, send goes to /send), presentation/onboarding_house_screens.dart (review uses WhoReplied, Remind all, signing manager row, test buttons), presentation/broker_draft_cards.dart (notice progress), presentation/onboarding_widgets.dart (OnbPill label ellipsis), core/routing/app_router.dart (route send), test/property_onboarding_test.dart
source design: v2 canvas page 06 RV3, RV4, RV5, RV6; A2; HM1; ES1/ES5 for "everyone signs"
rule: signsAs defaults to 'trustkeyper' (templates name Paravent); 'me' = broker signs
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 31 passed; full suite 39 failures, the same 39 as before this change (old golden/layout tests)
```

## Change 41 – One "waiting" spinner everywhere
Date: 2026-10-29 · Status: on the phone after the next build
Wherever we wait for someone (a document, an owner's reply, a signature, our team), a small spinning ring now shows instead of a still clock:
- **Pills** that say Waiting, Checking, Not opened, Seen, no reply (house page documents, owner tabs, signing rows, who replied).
- **Banners** with the clock ("Asked just now. Waiting for Chevy.", "We are reading it…", "Draft 1 sent… waiting").
- **Owner tabs** that are still waiting, the **home notice** "Under review", home **Continue** rows that say "Waiting for…", "…is reviewing it", "We are making the agreement", "Getting stamp paper ready", and the **Waiting** chip on the older document-link screen.
Rule for new screens: use `OnbWaitSpinner` (or a pill/banner with the waiting word or clock icon) for every waiting state. It shows a still clock if the phone is set to reduce motion.
```
AGENT RECORD – Change 41
id: CHG-041
date: 2026-10-29
branch: staging (never main)
files: presentation/onboarding_widgets.dart (OnbWaitSpinner; OnbPill.loading + waitingLabels; OnbBanner clock → spinner), presentation/onboarding_house_screens.dart (owner tab), presentation/broker_draft_cards.dart (notice + Continue rows), document_requests/presentation/broker_document_links.dart (Waiting chip)
rule: spinner is still (clock) under reduce-motion and in flutter tests (FLUTTER_TEST) so pumpAndSettle works
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 31 passed; full suite same 39 old failures as before
```

## Change 42 – "Send for signing" is one sheet: WhatsApp or email
Date: 2026-10-29 · Status: on the phone after the next build
The "Send to Bini for signing?" sheet with the avatar and "Yes, send for signing", and the extra "Send to each owner" page, are gone. Now, like the canvas "Send link?" sheet (SL1):
- Tap **Send for signing** → one sheet: green send icon, **Send to Bini for signing?**, "To Bini · +91 …" (or "To Ravi and Sita"), and two choices: **WhatsApp** (logo, "Best – most people use it") or **Email** (the owner's email). No SMS.
- A line says who signs: "Bini reads it and says yes. TrustKeyper signs last." with **Change**.
- **Send for signing** sends it and goes straight to **Draft 1 sent!** (timeline, Go to home, See who replied). **Cancel** closes the sheet.
- Edge cases: no number for anyone → WhatsApp is greyed "No WhatsApp number"; no email → Email greyed "No email added"; WhatsApp is picked first when there is a number. With several owners, one choice covers all: an owner without that contact gets it the other way, and the sheet says so ("Sita gets it on email (no WhatsApp number).").
```
AGENT RECORD – Change 42
id: CHG-042
date: 2026-10-29
branch: staging (never main)
files: presentation/send_for_signing_screens.dart (pickSendWay sheet, sendWayFor; SendToEachScreen removed), presentation/onboarding_agreement_screens.dart (confirmSendDraft removed; sendDraftWithConfirm = sheet → send to all → /sent), core/routing/app_router.dart (route send removed), test/property_onboarding_test.dart
source design: v2 canvas page 04 SL1 / SL1b / SLE1 ("Send link?" sheet), without SMS
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 32 passed; full suite same 39 old failures as before
```

## Change 43 – Spinner only on the Documents screen (Change 41 narrowed)
Date: 2026-10-29 · Status: on the phone after the next build
As asked, the spinner is no longer used everywhere. It stays only on the house page while documents are coming (Documents stage): the "Asked … Waiting for {owner}" / "has not replied" banner, the **Waiting** pills on each document, and the owner tabs when there are several owners. Everywhere else (who replied, signing, home notice, home Continue rows, the older document-link screen, other banners) is back to the still icons from before Change 41.
Rule now: do **not** add the spinner to new screens unless Aman asks.
```
AGENT RECORD – Change 43
id: CHG-043
date: 2026-10-29
branch: staging (never main)
files: presentation/onboarding_widgets.dart (OnbPill.loading and OnbBanner.loading default false, no auto-detect), presentation/onboarding_house_screens.dart (loading: true on the 4 papers-stage banners and the paper Waiting pills), presentation/broker_draft_cards.dart and document_requests/presentation/broker_document_links.dart (restored to 07a39d8)
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 32 passed
```

## Change 44 – After sending: calmer page, two buttons at the bottom
Date: 2026-10-29 · Status: on the phone after the next build
House page after "Send for signing", while waiting for the owner:
- **Bottom:** only two buttons side by side: **Remind Bini** (secondary, left; "Remind all 2" with several owners; greyed "Reminded" for an hour after reminding) and **Go to home** (primary, right). Read full agreement and Make changes are no longer bottom buttons.
- **Removed:** the "Who said yes 0 of 1" bar and the Rent · Starts · Your fee strip.
- **Who signs** (card): each owner with their status (Not opened / Seen, no reply / Said yes / Asked a change → tap See) and the manager row (TrustKeyper · Manager, "Signs last"). With one owner there is no second Remind in the card (it is at the bottom); with several owners each row has its own Remind.
- **Your agreement** (card of tappable rows): **Read full agreement** ("Draft 1 · ₹32,000 rent · 89 days, once") and **Make changes** ("Makes Draft 2. You send it again.").
- **More** (card of tappable rows with icons and arrows, was grey text links): Key points, Changes, Versions, Call our agreement team. **Cancel agreement** in red below it. The same More card is used on the other agreement states too.
- When all owners say yes, the bottom shows only **Lock and continue** (Make changes is on the page).
```
AGENT RECORD – Change 44
id: CHG-044
date: 2026-10-29
branch: staging (never main)
files: presentation/onboarding_house_screens.dart (_review sent: Who signs / Your agreement / More sections, _sectionLabel, _moreLinks as card rows, footer Row Remind+Go to home, _RemindAllButton removed, no read-full button in footer once sent), presentation/send_for_signing_screens.dart (WhoReplied: no fact strip, no progress bar, per-row Remind only with several owners), test/property_onboarding_test.dart
verification: flutter analyze No issues found; property_onboarding_test + agreement_filler_test 32 passed; full suite same 39 old failures as before
```

## Change 45 – Add new property: name first, then "how do you want to add details?"
Date: 2026-10-29 · Status: on the phone after the next build
Rent agreement · Step 1 · **Add new property** now goes:
1. **Name the property** (new): one box "Property name" (e.g. "Flat 402, Madhapur"), required, "Only you see this name. You can change it later." Empty → "Type a name for the property".
2. **How do you want to add the details?** (new): three choices. **Add details myself** is first, bigger, blue icon, "Best" tag and picked by default. Under "Or let us read a paper": **Upload sale deed** and **Upload old rent agreement**.
   - Reading those papers needs the backend, so picking one and tapping Next shows "Reading a sale deed is coming soon. For now, add the details yourself." with **Add details myself** (or Go back). Nothing is uploaded yet.
3. Then the usual steps: address and size (the box is now "Full address (optional)"), rooms, things in the house, check.
- The name is saved with the property and shown everywhere the property is listed (search also finds it by name). Editing a saved property starts at the name and skips the "how" question.
```
AGENT RECORD – Change 45
id: CHG-045
date: 2026-10-29
branch: staging (never main)
files: features/broker/data/broker_property_repository.dart (BrokerProperty.name, toMap 'name', displayName prefers name), features/broker/presentation/broker_property_screen.dart (stages renumbered: 0 picker · 1 name · 2 how · 3 address · 4 rooms · 5 things · 6 check; _nameField, _howToAdd, _uploadNotReady; back from 3 when editing → 1), test/broker_property_test.dart
note: Firestore rules for properties have no field allowlist, so 'name' saves without a rules change
verification: flutter analyze No issues found; broker_property_test 5 passed; full suite same 39 old failures as before
```

## Change 46 – New `website/` folder: trustkeyper.com website + its backend
Date: 2026-11-01 · Status: code complete; not deployed
Adds the rebuilt public website and its enquiry backend in a new top-level folder. Nothing in the app, `functions/` or root Firebase config changed.
- `website/site/`: the website source and build script (homeowner, property agent with EN/HI/TE, builders, contact and legal pages; WhatsApp button; verify-first enquiry form).
- `website/api/`: Dart backend for Cloud Run: `/api/otp/send`, `/api/otp/verify`, `/api/contact`, using Firestore collections `web_otp`, `web_rate`, `web_leads`.
- `website/docs/DEVELOPER_GUIDE.md`: what was built, the developer's to-do list (MSG91 + DLT, Resend, secrets, deploy, hosting, Firestore TTL/rules), considerations and go-live tests.
```
AGENT RECORD – Change 46
id: CHG-046
date: 2026-11-01
branch: staging (never main)
files: website/** (new folder only)
deploy: none (no CI workflow; backend and site deploys are manual, see website/docs/DEVELOPER_GUIDE.md)
verification: site build.py OK; api dart analyze no issues; dart test 18 passed
```

## Change 47 – Website: phone and tablet layouts
Date: 2026-11-01 · Status: code complete; not deployed
- Header: full menu only at 1200 px and wider; below that the ☰ menu (it was missing between 768 and 1023 px, so tablet visitors could not reach the Property Agents or Builders pages). On tablets Contact Us and Sign Up stay visible.
- Tablet layouts (640–1199 px) for all pages: two- or three-column grids, side-by-side comparison cards, normal-width buttons; headings scale smoothly with screen width.
- Small phones (under 375 px): tighter role pills and OTP boxes.
- Checked 360, 390, 600, 768, 820, 1024 and 1280 px on 7 pages: no sideways scrolling.
```
AGENT RECORD – Change 47
id: CHG-047
date: 2026-11-01
branch: staging (never main)
files: website/site/src/website.css, website/site/src/agent.css, website/site/src/builder.css (appended "Responsive pass" blocks)
verification: playwright scan at 7 widths × 7 pages, scrollWidth == viewport; visual check at 390/768/1024/1280
```

## Change 48 – Website: "Start now" button in How it works
Date: 2026-11-01 · Status: code complete; not deployed
Homeowner page, How it works, step 1 ("Tell us about your home") now has a small green **Start now →** button that scrolls to the enquiry form (`#get-started`). All screen sizes.
```
AGENT RECORD – Change 48
id: CHG-048
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (.tkh-start link in first .tkh-steps item), website/site/src/website.css (.tkh-start styles)
verification: checked at 390/768/1280 px; click lands on form heading; no sideways scroll
```

## Change 49 – Website: enquiry form fixed on phones and tablets
Date: 2026-11-01 · Status: code complete; not deployed
- Bug: below 900 px the form was squeezed into a narrow column (the hidden photo column still took 300 px). The card is now a single full-width column whenever the photo is hidden, on the homepage and Contact Us.
- On phones (≤640 px) the floating WhatsApp button fades away while the form is on screen, so it never covers a field, and returns when the visitor scrolls away.
```
AGENT RECORD – Change 49
id: CHG-049
date: 2026-11-01
branch: staging (never main)
files: website/site/src/website.css (.tkf-wrap single column ≤900px; .tk-wa-away), website/site/src/website.js (IntersectionObserver on .tkf-wrap toggles .tk-wa-away)
verification: form width 272/302/640/445/700 px at 360/390/768/901/1280 viewports; full OTP→submit flow test passed at 1440; OTP popup checked at 390
```

## Change 50 – Website: one FAQ heading instead of label + heading
Date: 2026-11-01 · Status: code complete; not deployed
The FAQ sections showed a small label ("Frequently Asked Questions" / "Questions") above a big heading ("Common questions answered." / "Your questions, answered"). Now there is one big heading only: **Frequently asked questions.** Homeowner page and Property Agent page (EN: Frequently asked questions · HI: अक्सर पूछे जाने वाले सवाल · TE: తరచుగా అడిగే ప్రశ్నలు). All screen sizes.
```
AGENT RECORD – Change 50
id: CHG-050
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (FAQ eyebrow removed, h2 text), website/site/src/__agent_page__/index.html (faq.eyebrow removed), website/site/src/i18n/agent-page.json (faq.title EN/HI/TE, faq.eyebrow key removed)
verification: checked at 390 and 1280 px
```

## Change 51 – Website: Ghanalaxmi T. testimonial updated
Date: 2026-11-01 · Status: code complete; not deployed
Homeowner page, Owner stories, third card: location now "Owner, ASBL Spectra"; quote now about finding, verifying and onboarding a tenant within 24 hours. Wording drafted for the owner's approval.
```
AGENT RECORD – Change 51
id: CHG-051
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (third .tkh-quote: blockquote text, figcaption small)
verification: checked at 390 and 1280 px
```

## Change 52 – Website: How it works – quieter numbers, compact phone layout
Date: 2026-11-01 · Status: code complete; not deployed
- All sizes: the 1/2/3 badges are now white with a soft shadow and navy number (the green fill looked like a button).
- Phones only (under 640 px, as requested): number sits to the left of the step title and text, cards are tighter, and the Start now button lines up under the text. Tablet and desktop keep the 3-card row.
```
AGENT RECORD – Change 52
id: CHG-052
date: 2026-11-01
branch: staging (never main)
files: website/site/src/website.css (.tkh-num restyle; @media (max-width:639px) grid layout for .tkh-steps li)
verification: checked at 360/390/768/1280 px; no sideways scroll
```

## Change 53 – Website: property tax card toned down
Date: 2026-11-01 · Status: code complete; not deployed
Homeowner page, All services: the "Property tax, paid on time" card was dark navy and stood out too much. It now matches the other cards (light, dark text) with a faint green tint and thin green outline, plus the existing NEW tag. All screen sizes.
```
AGENT RECORD – Change 53
id: CHG-053
date: 2026-11-01
branch: staging (never main)
files: website/site/src/website.css (.tkh-services .tkh-wide restyle)
verification: checked at 390 and 1280 px
```

## Change 54 – Website: removed "Register your property" button under How it works
Date: 2026-11-01 · Status: code complete; not deployed
The dark "Register your property" button below the three steps is removed on all screen sizes. Step 1's "Start now" button already leads to the enquiry form.
```
AGENT RECORD – Change 54
id: CHG-054
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (.tkh-cta block in #how-it-works removed)
verification: checked at 390 and 1280 px
```

## Change 55 – Website: phone-only hero cleanup; FAQs start collapsed
Date: 2026-11-01 · Status: code complete; not deployed
Homepage hero, phones only (under 640 px, as requested); tablet and desktop unchanged:
- Darker shade over the top of the photo so the text is readable; the house shows clearly below.
- Shorter text: "Tenants, rent and repairs, handled by one local team." Button reads **Register now**. The "No upfront commitment…" line is hidden.
- Manager photo hidden; Property Status card shrunk to a small card (2 rows) at the bottom right, so the house photo is visible.
All sizes: every FAQ (homepage, Property Agent page) now starts collapsed; tapping a question opens it.
```
AGENT RECORD – Change 55
id: CHG-055
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (.tkh-hero-m/.tkh-hero-d text variants, .tkh-hero-visual, .tkh-hero-shade; FAQ aria-expanded=false + hidden panels), website/site/src/website.css (phone hero block), website/site/build.py (agent FAQ: first item no longer open)
verification: hero checked at 360/390/768/1280 px; FAQ: 0 panels open at load on both pages, click opens one
```

## Change 56 – Website: hero button short and compact
Date: 2026-11-01 · Status: code complete; not deployed
Homepage hero button now reads **Register now →** on all sizes (was "Register and we'll get back to you soon" on tablet/desktop). Compact (50 px tall, auto width), semibold label, soft drop shadow so it reads as a button, gentle lift and arrow nudge on hover.
```
AGENT RECORD – Change 56
id: CHG-056
date: 2026-11-01
branch: staging (never main)
files: website/site/src/index.html (hero CTA label, .tkh-hero-btn class), website/site/src/website.css (.tkh-hero-btn)
verification: checked at 390/768/1280 px
```

## Change 57 – Backend handoff document for the Onboard property journey
Date: 2026-11-02 · Status: document only (no app change)
New `docs/BACKEND-HANDOFF-property-onboarding.md` for the backend developer: how to run and test, every app change 1–45 in one table, what is real vs pretend (TEST ONLY buttons), the state machine, the full data model, backend tasks A–I with "done when", the app methods to replace with backend calls, open decisions, and a file map.
```
AGENT RECORD – Change 57
id: CHG-057
date: 2026-11-02
branch: staging (never main)
files: docs/BACKEND-HANDOFF-property-onboarding.md (new), docs/CHANGELOG-staging.md
verification: document only; facts checked against property_onboarding.dart, agreement_templates.dart, app_router.dart and the test suite (39 old failures, unchanged)
```

## Change 58 – TrustKeeper 2: broker launch app (properties, one-tap share, paid visits)
Date: 2026-11-02 · Status: code complete; test build only (data on phone, test payment)
A separate small app for brokers (`lib/main_tk2.dart`). Home shows properties as clean cards, with one example property until the broker adds their own. Add property reuses the existing house screens, then asks rent, deposit, move-in date, visit fee (₹100/150/200) and photos. Share sends the details to WhatsApp in one tap. Customer view shows what the customer sees: book a day and time, pay the visit fee (held), get a visit code. Visits tab: fee held until the broker types the customer's code after the visit; cancel or did not come refunds it. Full notes and backend plan: `docs/TRUSTKEEPER2.md`.
Shared screen change: `BrokerPropertyScreen` got `startNew`, `showStepLabel`, `doneLabel` (main app unchanged by default).
```
AGENT RECORD – Change 58
id: CHG-058
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/main_tk2.dart (new), apps/flutter_app/lib/src/tk2/{tk2_app,tk2_store,tk2_widgets,tk2_listing,tk2_customer,tk2_visits}.dart (new), apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (startNew/showStepLabel/doneLabel), apps/flutter_app/test/tk2/tk2_test.dart (new), docs/TRUSTKEEPER2.md (new), docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 5/5 pass (store rules + full welcome→book→paid flow); full suite 39 old failures, same as before this change
install: Mac-only local switch to bundle id com.trustkeyper.tk2 + FLUTTER_TARGET=lib/main_tk2.dart (repo iOS project unchanged)
```

## Change 59 – TrustKeeper 2 reuses the main app's screens; sleek property rows
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
Feedback: the first TK2 build redesigned things that didn't need it. Now TK2 uses the main app's splash, welcome carousel, logo, login look, broker home (header, Namaste, slim tiles, call card) and floating bottom bar as they are. Own animations removed. Home property cards are now compact rows: small photo, "3 BHK · name", rent incl./+ maintenance, sft · furnishing, who can rent · pets · available from, WhatsApp share icon. Rent screen asks maintenance, who can rent and pets.
Shared screen hooks (main app unchanged by default): `SplashScreen.nextRoute`, `ApprovedBrokerNavigation.labels/icons` (`defaultLabels`), `ApprovedBrokerHome.actions/trailing/below/showBankPrompt`, public `HomeTile`/`HomeIcon`.
```
AGENT RECORD – Change 59
id: CHG-059
date: 2026-11-02
branch: staging (never main)
files: lib/src/tk2/{tk2_app,tk2_store,tk2_widgets,tk2_listing,tk2_customer}.dart, lib/src/features/auth/presentation/auth_screens.dart, lib/src/core/widgets/approved_navigation.dart, lib/src/features/broker/presentation/approved_broker_home.dart, test/tk2/tk2_test.dart, test/design_layout_test.dart (defaultLabels), docs/TRUSTKEEPER2.md
verification: flutter analyze clean; test/tk2 6/6; full suite 39 old failures (unchanged)
install (Mac only): bundle id com.trustkeyper.tk2, FLUTTER_TARGET=lib/main_tk2.dart, entitlements off (no push/App Attest) so the team wildcard profile signs it
```

## Change 60 – TrustKeeper 2: private details hidden from tenants, 4 card/page designs, visit fee ₹0–500
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
- Customers (shared message, link page, booking) now see only: rooms · society, area, rent, facts. Door number, full address, owner name/phone, keys and a note live in a broker-only "Complete address and details" block with a green lock banner ("Only you can see this. It is never shared with tenants").
- Rent screen: "Customers see" (society, area) and the private block (door, owner, phone, keys, note).
- Home shows 4 designs one under the other – A Classic row, B Wide photo, C Price first, D Ticket – each with soft shadow, icons, no WhatsApp/arrow; each opens its own property page design (A icon tiles · B tabs "Customers see / Only you" · C rent card + grouped sections · D grey page with grouped rows).
- Visit fee: type any amount ₹0–500; 0 = free visit (no payment step).
```
AGENT RECORD – Change 60
id: CHG-060
date: 2026-11-02
branch: staging (never main)
files: lib/src/tk2/tk2_designs.dart (new), tk2_store.dart (society, locality, door, ownerName, ownerPhone, keys, note, publicTitle, fullAddress, feeText, maxVisitFee), tk2_listing.dart (form; old detail removed), tk2_customer.dart (public fields, free visit), tk2_app.dart (/p/:id?d=), tk2_widgets.dart, test/tk2/tk2_test.dart
verification: flutter analyze clean; test/tk2 8/8 (incl. door/owner never in share text or customer view; all 4 pages open)
```

## Change 61 – TrustKeeper 2: Design E (refined Ticket) + one icon family
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
Design E (shown first on home, D kept for comparison): left panel – **2 BHK** loudest, then rent, then maintenance; right – full society name (no Example pill, so it only cuts off at the card edge), area, then facts in two columns split by a light vertical line (left: sft, furnishing, who can rent; right: pets, available from, room for more later). E opens the D page. All TK2 icons now Material *outlined* (same stroke): square_foot_outlined, chair_outlined, group_outlined, pets_outlined, event_available_outlined, place_outlined, local_parking_outlined, currency_rupee_outlined.
```
AGENT RECORD – Change 61
id: CHG-061
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_designs.dart, apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 8/8 (all 5 pages open)
```

## Change 62 – TrustKeeper 2: no "Things in the house" step when adding a property
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
Add property in TK2 now goes name → how → address → rooms → **Save property**. Things in the house (fans, lights, AC…) will be asked later while drafting the agreement. The check page hides the empty "Things in the house" box. Main app unchanged (`BrokerPropertyScreen.askThings`, default true).
```
AGENT RECORD – Change 62
id: CHG-062
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (askThings, _lastInput; dart format), apps/flutter_app/lib/src/tk2/tk2_app.dart, apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 + broker_property_test 14/14
```

## Change 63 – TrustKeeper 2: card heading never empty; A–D icons restored
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
Bug: D and E headings were blank for properties saved before the society/area fields existed (heading used society → area only). Now `tk2CardHeading`: society → area → broker's own property name → "2 BHK property". Home is broker-only, so the broker's own name is fine there; customers still only see rooms · society. Change 61 had also switched the icons on A–D; reverted – the outlined icon family now applies to Design E only (card + its page). E fact text can wrap to 2 lines instead of "Family or bach…".
```
AGENT RECORD – Change 63
id: CHG-063
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_designs.dart (tk2Facts outlined flag, tk2CardHeading, _labelled per design), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 10/10 (new: heading fallback)
```

## Change 64 – TrustKeeper 2: earlier compact row card brought back for comparison
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
The compact row card from Change 59 (small photo left; rooms · name, rent line, sft · furnishing, rules · available; WhatsApp share) is back on home, below designs E, A–D, labelled "Earlier design · Compact row". Same look as before; only the title now uses the card heading (society / area / broker's name) so the door number rule still holds. Tapping it opens the A page. Nothing else changed.
```
AGENT RECORD – Change 64
id: CHG-064
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_widgets.dart (Tk2PropertyCard restored from c1785a0), apps/flutter_app/lib/src/tk2/tk2_designs.dart (showcase: earlier section at the end), apps/flutter_app/test/tk2/tk2_test.dart (counts), docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 10/10
```

## Change 65 – TrustKeeper 2: home shows only Designs E and B (final candidates)
Date: 2026-11-02 · Status: code complete; installed on Aman's iPhone
- Home now shows only E and B (A, C, D and the earlier compact row removed from the screen).
- E heading = society name, else the area (from the area field, else read from the address) – no longer the broker's own label (e.g. "VIVID"). Below it: the complete address without house/flat/plot numbers or floor (`tk2PublicAddress`).
- B: photo area is swipeable with 3 dots; no photos yet → the app's house illustration (welcome-home.svg) as a placeholder, no "2.5 BHK" text on it, no rent pill. Title "2.5 BHK · ₹30,000 incl. maintenance" (same style), then the same address line as E, then the facts.
```
AGENT RECORD – Change 65
id: CHG-065
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_designs.dart (tk2Designs ['e','b'], tk2CardHeading, tk2PublicAddress, _SwipePhotos, B card), apps/flutter_app/lib/src/tk2/tk2_app.dart (intro line), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 11/11 (new: address drops house numbers; heading never uses the broker's label)
```

## Change 66 – TrustKeeper 2: Add property = the main app's "Onboard property" journey
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
Add property now opens the exact main-app journey: Onboard property → Send link to owner (owner link, papers, questions, agreement, signing) or Add manually. Add manually saves into TrustKeeper 2, skips "Things in the house", then asks rent and details. Home shows the same "Continue" panel as the main app for properties being onboarded. "Go to home" lands on TK2 home; "Make rent agreement" goes home (not in TK2 yet).
Main app: the Onboard property routes moved into `brokerPropertyRoutes()` in app_router.dart (same screens, now shared); no behaviour change.
```
AGENT RECORD – Change 66
id: CHG-066
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/core/routing/app_router.dart (brokerPropertyRoutes, dart format), apps/flutter_app/lib/src/tk2/tk2_app.dart (routes, redirects /add /broker /broker/start, BrokerDraftSection with _NoAgreementDrafts), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 11/11; property_onboarding + route tests 33/33
```

## Change 67 – TrustKeeper 2: property name first, then "Send link to owner / Add manually"
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
Add property now opens on "Add new property" (type a name). After Next, the main app's "Onboard property" choice appears (same screen, same look). Send link to owner → the main app's owner-link journey; the typed name is kept as the house name until the owner's real address arrives. Add manually → continues the manual steps (no name asked again). Back on the choice returns to the name. Main app unchanged.
```
AGENT RECORD – Change 67
id: CHG-067
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (new flag askHowToAdd; _next stage 1 pushes OnboardChooseScreen), apps/flutter_app/lib/src/features/broker/presentation/onboarding_start_screens.dart (OnboardChooseScreen onLink/onManual callbacks; OnboardNewScreen label), apps/flutter_app/lib/src/features/broker/data/property_onboarding.dart (PropertyOnboarding.label – broker-only name, stored separately from address; houseName = address, else label, else 'New house'; create(label:)), apps/flutter_app/lib/src/tk2/tk2_app.dart (/add → /broker/property/manual with startNew + askHowToAdd), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: label never replaces the real address and is never shown to tenants
verification: flutter analyze clean; test/tk2 11/11
note: build env needs Flutter 3.38.4 (newer stable breaks the lockfile)
```

## Change 68 – TrustKeeper 2: Brokerage row; consistent line icons on the property page
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
- New "Brokerage" field (₹) on the Rent & details screen, under Rent / Deposit. Empty = no brokerage.
- Property page list: new "Brokerage" row (handshake icon) after Rent/Deposit – shows the amount or "No brokerage". Customers see it too: customer page price box and share message show "Brokerage ₹X" only when it is set.
- Icons: Pets now uses a line paw (own SVG, same stroke as the other icons) instead of the filled paw, in Design E's card and list. The broker-only "Complete address and details" icons (Full address, Owner, Owner phone, Keys, Note) now sit in the same small light-blue squares at 18 px as the rows above, so the line weight matches; call button uses the outlined phone.
```
AGENT RECORD – Change 68
id: CHG-068
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_store.dart (Tk2Listing.brokerage int ₹, json 'brokerage', brokerageText, shareText line), apps/flutter_app/lib/src/tk2/tk2_listing.dart (brokerage money field), apps/flutter_app/lib/src/tk2/tk2_customer.dart (price box line), apps/flutter_app/lib/src/tk2/tk2_designs.dart (_labelled Brokerage row; tk2Glyph maps Icons.pets_outlined → assets/design/tk2-paw.svg; Tk2PrivateDetails leading icon 18px in primarySoft 34px square; Icons.call_outlined), apps/flutter_app/assets/design/tk2-paw.svg (new), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: brokerage is public (customers see it); 0 is never shown to customers
verification: flutter analyze clean; test/tk2 12/12 (new: brokerage save/share)
```

## Change 69 – One header style (fixed heading with soft shadow); Back goes one step
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
- "Add new property" (all its steps) now uses the same heading as Onboard property / Owner details: back button + title + subtitle fixed at the top, soft shadow, content scrolls under it, more space. The floating call button above the title is gone (no call/progress in onboarding headers). The main app's rent agreement journey keeps its step label, progress bar and call button, now inside the same fixed header.
- TrustKeeper 2 "Rent and details" screen uses the same header (was a plain app bar + title).
- Back fix: each Back goes exactly one screen back. Add manually → "How do you want to add the details?" → Back now returns to the Send link / Add manually choice (before, it jumped to the name). Send link → Owner details → Back returns to the choice (before, the choice was replaced and skipped).
```
AGENT RECORD – Change 69
id: CHG-069
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/features/broker/presentation/onboarding_widgets.dart (new OnbHeader, OnbShadowBody – same look as OnbPage), apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (build uses OnbHeader/OnbShadowBody; _openChoice(); _back at stage 2 with askHowToAdd reopens choice; link path uses push, not pushReplacement; dart format), apps/flutter_app/lib/src/tk2/tk2_listing.dart (OnbHeader/OnbShadowBody; dart format -l 200), apps/flutter_app/test/tk2/tk2_test.dart (back-one-step check), docs/CHANGELOG-staging.md
design rule: every flow screen uses the fixed heading with soft shadow (OnbPage, or OnbHeader + OnbShadowBody)
verification: flutter analyze clean; test/tk2 12/12
```

## Change 70 – Add-property polish, Rent & details reorder, customer page, visit hours
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
- "Add manually" now opens its next screen with the same slide-in as "Send link to owner" (a new screen). Back from it returns to the choice.
- Full address is required (label no longer says "optional").
- Errors are shown where the problem is: the section turns red (light red background, red border, short message inside) – Rooms, Floor/Total floors, Furnished; fields (Property name, Full address, Size) get a red border and message. All missing parts are marked at once. No more error line above the buttons for these.
- Rent and details, new order: Society, Area → Rent + Maintenance (Included / Extra) side by side; Extra opens the maintenance amount → Security deposit (renamed) → Brokerage → Who can rent → Pets → Available from → Visit times (From / To) → Visit fee → Photos → green "Confidential · only for you" card (never shared) with Flat/door, Owner name, Owner phone, Keys, Note. Missing society/area, rent or maintenance are all marked in red at once.
- Save button now sits after the last field and scrolls with the page (the keyboard can't hide it). Same for "Pay and book" on Book a visit.
- Customer page: under the photos, the same layout the broker sees (ticket card + facts list with icons). New booking notice: refund if broker/owner is not available; we wait 15 minutes; late by more than 15 minutes or cancelled by the customer = no refund.
- Book a visit: hourly slots 7 am – 11 pm. Times outside the broker's "Visit times" are greyed out. Other bookings never block a slot (many people can book the same hour).
```
AGENT RECORD – Change 70
id: CHG-070
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (firstStage/initialName; onManual pushes a new BrokerPropertyScreen(firstStage: 2); Back on firstStage pops; Set<String> bad + _Attention section wrapper; address required (<5 chars = missing)), apps/flutter_app/lib/src/tk2/tk2_listing.dart (reordered form, maintenance dropdown, Security deposit, visit times, confidential card, button in scroll, missing set + red borders), apps/flutter_app/lib/src/tk2/tk2_store.dart (Tk2Listing.visitFrom/visitTo, visitHours 7..23, slotOpen), apps/flutter_app/lib/src/tk2/tk2_customer.dart (customer page uses Tk2DesignCard 'e' + Tk2FactsGroup; tk2VisitNotice; book slots = visitHours, closed outside broker hours; button in scroll), apps/flutter_app/lib/src/tk2/tk2_designs.dart (public tk2FactRows + Tk2FactsGroup), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: same-hour bookings allowed (slots never close because of other bookings); confidential fields never reach customer views
open: Visits tab still refunds on "didn't come"/cancel – not yet matched to the new no-show rule (needs Aman's call)
verification: flutter analyze clean; test/tk2 13/13 (new: visit hours); broker_property_test 5/5
```

## Change 71 – TrustKeeper 2: "Rent and details" split into 4 steps (NoBroker-style), follow-up questions, what happens next
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
After the house details, the broker now goes through 4 short steps (one topic per screen, slide-in between steps, "Step N of 4" under the title, Back goes one step):
1. Rent details – Society, Area · Rent + Maintenance (Included/Extra → amount) · Security deposit · Brokerage (No brokerage / 15 days rent / 1 month rent → shows the ₹ amount / Fixed amount → amount box) · Who can rent (tick boxes: Anyone, Family, Bachelor male, Bachelor female, Companies; Anyone ticked by default and ticks/unticks all) · Pets · Available (Now / From a date → date).
2. Visits – Days (Every day / Mon–Fri / Sat, Sun), Times From/To, Visit fee.
3. Photos – with "Skip for now".
4. Only for you – green confidential card (door, owner, phone, keys, note) → Save property.
Follow-up fields appear only for the answer that needs them (maintenance amount, brokerage amount, date). Missing answers turn red in place.
Customers: Book a visit greys out days outside the broker's visit days. Customer page shows "What happens next": visit → token amount blocks the house → agreement drafted → agreement signed → payments and keys together.
Display: "Anyone" now reads "Anyone can rent" (companies included).
```
AGENT RECORD – Change 71
id: CHG-071
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_listing.dart (Tk2ListingForm: step 0..3, _check(step), _next/_back, PopScope, AnimatedSwitcher slide, _rentStep/_visitStep/_photoStep/_privateStep, _box, _pick), apps/flutter_app/lib/src/tk2/tk2_store.dart (Tk2Listing.brokerageDays, brokerageFor, visitDays, dayOpen, tenantTypes, tenantSet, toggleTenant, tenantText; tenants saved as 'Anyone' or comma list; old 'Bachelors' → both bachelor types), apps/flutter_app/lib/src/tk2/tk2_customer.dart (Tk2NextSteps; _slotGone uses dayOpen), apps/flutter_app/lib/src/tk2/tk2_designs.dart (text), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: brokerage for days = rent × days ÷ 30, rounded; "Anyone" = all 4 types
open: Send-link-to-owner path – owner answers papers in the main-app flow; rent/visits/photos for such houses still need a TK2 step for the broker (cards for link-added houses not shown yet)
verification: flutter analyze clean; test/tk2 15/15 (new: who-can-rent ticks, brokerage from rent, visit days)
```

## Change 72 – Tenant + owner web app (prototype, live link), new visit-fee rules, journeys document
Date: 2026-11-02 · Status: prototype live; app code synced to the Mac, not yet built
- New tenant/owner web app (HTML prototype to agree the flow; to be rebuilt in Flutter web). Live: https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt. Tenant: property page (no login) → book day/hour → sign up (name, phone, OTP) → pay → booked (code, Google Calendar link, reminder-call note, 5-minute cancel) → I want it → token ₹15,000 → details → owner details → agreement (broker-only edits, approve) → e-sign → deposit + first rent + brokerage → keys. Owner: invite → sign up (phone or email + OTP) → 15 questions one per screen (no brokerage) → done. OTP, payments, e-sign, calls are demo.
- Broker app share link now opens this web app; the public details travel inside the link (#p-…, base32). Private details never included.
- Visit-fee rules: tenant can cancel only within 5 minutes (2% kept); no-show → broker gets half; broker cancels → full refund. Visits tab, pills and notice texts updated.
- New human-readable doc: docs/TRUSTKEEPER2-JOURNEYS.md (all three journeys, money and privacy rules, developer to-do).
```
AGENT RECORD – Change 72
id: CHG-072
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_link.dart (new: tk2WebApp, tk2PublicPayload, tk2PropertyLink, tk2OwnerLink, tk2Base32), apps/flutter_app/lib/src/tk2/tk2_store.dart (Tk2Visit.brokerShare/customerRefund/customerCanCancel/refundAfterFee, VisitStatus.customerCancelled, Tk2Store.customerCancel, releasedTotal = sum brokerShare, share text uses tk2PropertyLink), apps/flutter_app/lib/src/tk2/tk2_visits.dart, apps/flutter_app/lib/src/tk2/tk2_listing.dart (visit row pills), apps/flutter_app/lib/src/tk2/tk2_customer.dart (notice), apps/flutter_app/test/tk2/tk2_test.dart, docs/prototypes/tk2-web/index.html (web prototype source), docs/TRUSTKEEPER2-JOURNEYS.md, docs/CHANGELOG-staging.md
rules: link payload = public fields only (tested); visit money table in TRUSTKEEPER2-JOURNEYS.md
verification: flutter analyze clean; test/tk2 17/17; web prototype: tenant and owner journeys run end to end in headless Chromium with no page errors
```

## Change 73 – Address asked in parts when adding a property; removed from Rent details
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
- "Tell us about the property" now asks the address in parts: Flat / house number (required, with a green "Only you see the flat number" note) · Society / building name (if any) · Area / locality (required) · City (required, starts as Hyderabad). Each missing part turns red in place.
- The saved address is the parts joined ("Flat 402, Sri Sai Residency, Madhapur, Hyderabad"). Older properties with one address line keep it as is.
- TrustKeeper 2: the parts fill the listing automatically – flat → private door number, society → card heading, area + city → public area. So "Rent details" no longer asks Society/Area, and "Only for you" no longer asks Flat/door number.
- Main app uses the same screen and gets the same split address.
```
AGENT RECORD – Change 73
id: CHG-073
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/features/broker/data/broker_property_repository.dart (BrokerProperty.flat/society/area/city, compose(), toMap/fromMap keys – additive), apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (_part fields with keys property-flat/-society/-area/-city; validation flat/area/city; legacy one-line address kept), apps/flutter_app/lib/src/tk2/tk2_store.dart (saveProperty maps parts → door/society/locality), apps/flutter_app/lib/src/tk2/tk2_listing.dart (removed society/area and door fields), apps/flutter_app/test/broker_property_test.dart, apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: flat number is private (never in share text or link payload) – tested
verification: flutter analyze clean; test/tk2 18/18; broker_property_test passes
```

## Change 74 – Brokerage in "Only for you" (main-app flow), available-from calendar, visit fee page, photo grid with cover, watermark
Date: 2026-11-02 · Status: code complete; synced to the Mac, not yet built
- Steps are now 5: Rent details → Visit times → Visit fee (own page) → Photos → Only for you.
- Rent details: brokerage removed from here. "Property available from" is one row; tapping opens the calendar with today already picked (today = available now).
- Only for you: brokerage asked here with the main TrustKeyper app's flow – who pays you: Owner / Tenant / Both / None → "From owner" and/or "From tenant" amounts with ½ month rent / 1 month rent shortcuts (any other amount can be typed) → "You will get ₹X". Only the tenant's part is shown to customers; the owner's part stays private.
- Photos: 3 per row (3·3·3·1, up to 10). First photo = cover (blue border + "Cover"). Tap ★ on any photo to make it the cover – it slides to the first place. Long-press and drag to reorder. ✕ removes.
- Every uploaded photo shows a light, slanted "TrustKeeper" watermark (on screen everywhere photos show; the real file gets it burned in when the backend uploads it).
```
AGENT RECORD – Change 74
id: CHG-074
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/tk2_listing.dart (5 steps; _feeStep; payer/ownerFee; _feePresets; Tk2PhotoGrid with AnimatedPositioned + LongPressDraggable/DragTarget; date row), apps/flutter_app/lib/src/tk2/tk2_store.dart (Tk2Listing.brokeragePayer, ownerBrokerage (private), daysFor; old saves → payer Tenant if brokerage > 0), apps/flutter_app/lib/src/tk2/tk2_widgets.dart (Tk2Photo watermark overlay, cacheWidth 900), apps/flutter_app/test/tk2/tk2_test.dart, docs/CHANGELOG-staging.md
rules: owner's brokerage never in share text or link payload (tested); watermark must be burned into stored images by the backend (see TRUSTKEEPER2-JOURNEYS.md)
verification: flutter analyze clean; test/tk2 19/19
```

## Change 75 – Tenant/owner web app rebuilt in Flutter; sign-up fixes; Design B + Send
Date: 2026-11-02 · Status: web app live (same link); broker app code synced to the Mac, not yet built
Web app (tenants and owners, opened from WhatsApp links) – rebuilt in Flutter web on the apps' own screens and design system; replaces the HTML prototype (removed). Live: https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt
- Correct name (TrustKeyper) and logo; TK house-mark favicon; branded loading screen; same slide-in for every screen; phone-width column centred on computers.
- Sign-up = the main app's login screen (logo hero, "Log in or sign up", name, Phone/Email switch) → the app's 6-box OTP (demo code 123456, resend timer). Tenants: phone; owners: phone or email.
- Tenant: property page (customer page without the "preview" strip) → Book a visit (standard header; Day/Time turn red in place if missing) → sign up → Pay and book → Your visit (code, Add to Google Calendar, reminder-call note, 5-minute cancel with timer) → Block (₹15,000) → Your details (red in place; Aadhaar upload) → Owner details → Rent agreement → Sign → Pay to move in → Get your keys → Welcome home. Back goes one step; done steps show "Done".
- Owner: invite → sign up → "How many owners?" + "Are you the owner?" → the broker's own house steps ("Your house": address in parts, size, facing, parking, rooms, floors, furnishing) → Rent details, Visit times, Photos (owner mode: no visit fee, no brokerage) → Papers (Aadhaar per owner, old agreement, bank, keys; missing ones red) → All done.
Shared sign-up widgets (main app too): Phone/Email switch – only the white thumb slides, fields below fade, nothing else moves. Phone field takes any country code (flag + code; search or type a code); India keeps 10-digit check, others 6–14.
Broker app: Design B card shows everything Design E shows (heading, address, size, furnishing, who can rent, pets, available) + a "Send" button bottom-right → Send to (tenants added before / new number) → WhatsApp / Text message / Both → "Sent!". Who can rent never says "only"; male + female = "Bachelor". Booking screen in the app uses the standard header.
```
AGENT RECORD – Change 75
id: CHG-075
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/main_tk2_web.dart (new entry; reads #fragment, setUrlStrategy(null)), apps/flutter_app/lib/src/tkweb/{tkweb_app,tkweb_session,tkweb_auth,tkweb_tenant,tkweb_owner}.dart (new), apps/flutter_app/lib/src/features/auth/presentation/approved_auth_widgets.dart (AuthMethodSelector sliding thumb, AuthFieldSwitcher, ApprovedPhoneField dialCode + country sheet, PhoneCountry), apps/flutter_app/lib/src/features/auth/presentation/auth_screens.dart (LoginScreen uses dial code + switcher), apps/flutter_app/lib/src/features/broker/presentation/broker_property_screen.dart (heading param), apps/flutter_app/lib/src/tk2/tk2_app.dart (Tk2Login dial code), apps/flutter_app/lib/src/tk2/tk2_customer.dart (preview/onBook/bookLabel, Tk2BookVisit onPicked + OnbHeader + red sections, Tk2NextSteps done, TrustKeyper name), apps/flutter_app/lib/src/tk2/tk2_listing.dart (ownerMode, onDone, step keys), apps/flutter_app/lib/src/tk2/tk2_link.dart (tk2ListingFromPublic, tk2Base32Decode), apps/flutter_app/lib/src/tk2/tk2_store.dart (putListing, listing() prefers saved, tenantLabel, contacts, sendListing), apps/flutter_app/lib/src/tk2/tk2_designs.dart (Design B facts + Send), apps/flutter_app/lib/src/tk2/tk2_send.dart (new), apps/flutter_app/lib/src/tk2/tk2_widgets.dart (web photos, watermark TrustKeyper), apps/flutter_app/pubspec.yaml + pubspec.lock (flutter_web_plugins sdk), apps/flutter_app/tool/build_tkweb.sh (new), apps/flutter_app/web/tkweb_favicon.png (new), apps/flutter_app/test/{tk2/tk2_test.dart,widget_test.dart}, docs/TRUSTKEEPER2-JOURNEYS.md, docs/prototypes (removed), docs/CHANGELOG-staging.md
hosting notes: Claude links need --no-web-resources-cdn, no .bin/NOTICES files, relative base href, and a hashchange reload (the host passes #… after start) – all in tool/build_tkweb.sh
verification: flutter analyze clean; test/tk2 22/22; email_auth_test 22/22; widget_test 17/17; broker_property_test passes; web app clicked through (tenant to "Your details", owner to "Your house") in headless Chromium and checked live in Chrome; broker home Design B + Send sheet checked in a web build
open: broker's "Send link to owner" still uses the main-app flow (does not send the web owner invite yet); WhatsApp/SMS/OTP/payments are demo
```

## Change 76 – Visit days chips; owner Keys step; customer page copy
Date: 2026-11-02 · Status: web app live (same link); broker app code synced to the Mac, not yet built
- Visit times (broker + owner): "Days for visits" = chips Every day, Mon … Sun. Pick any number; all seven ticks Every day and vice versa; none = red "Pick at least one day". Old saves (weekdays/weekends) still read.
- Owner web: "Papers" step replaced by **Keys**: Me (bottom sheet "How do we get the keys?"), Another property broker (name + number), Security (name + number + note), Someone else (name + number + note). Papers asked later, when a tenant blocks.
- Customer page: "In the house" list removed. Visit-fee notice rewritten (held by TrustKeyper; full refund if broker/owner doesn't turn up; cancel within 5 min = refund minus 2% platform fee; after 5 min or 15+ min late = no refund). "What happens next" now: Book a visit → Visit → Pay token (house hidden from others) → Agreement made → Sign → Pay (security deposit, brokerage if any, 1 month rent) and collect keys.
```
AGENT RECORD – Change 76
id: CHG-076
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/{tk2_store,tk2_listing,tk2_customer}.dart, apps/flutter_app/lib/src/tkweb/{tkweb_owner,tkweb_tenant}.dart, apps/flutter_app/test/tk2/tk2_test.dart, docs/TRUSTKEEPER2-JOURNEYS.md, docs/CHANGELOG-staging.md
verification: flutter analyze clean; test/tk2 23/23; web app clicked through in headless Chromium (visit-day chips, Keys + Me sheet + Security fields, customer page notice and steps)
open: broker's "Send link to owner" still uses the main-app flow; WhatsApp/SMS/OTP/payments demo
```

## Change 77 – Your visit screen; liked / not liked; gate pass; code valid ±24 h
Date: 2026-11-02 · Status: web app live (same link); broker app code synced to the Mac, not yet built
- Tenant "Your visit" rebuilt with a clear order: Visit booked pill → When (full date + time + "Tomorrow", Add to Google Calendar) → Where (public address, Open in Google Maps; flat number stays hidden) → Your broker (name, number, Call) → visit code → Good to know (reminder call, gate pass on WhatsApp, 15-minute wait) → Cancel visit.
- Cancel visit is always there until the visit is done. Within 5 min: refund minus 2%. After: no refund; broker gets half (new status `customerCancelledLate`, same money as a no-show). The pay screen rules say the same.
- Primary button "I visited the place" → "Did you like it?" Yes → Block this house (existing journey). No → "We told <broker>… he will send you more houses. Call him now or wait" with Call button.
- Visit code works from 24 h before to 24 h after the visit time (`Tk2Visit.codeWorks`); `confirmVisit` returns null / 'wrong' / 'window' and the broker sees the right message.
- Gate pass: broker's visit sheet has "Add gate pass" (upload) → "Gate pass sent on WhatsApp" (demo; backend sends it). Visit rows show "add gate pass" until added. Saved on the visit as `gatePass`.
- Property link now carries the broker's number (`bp`) so the tenant can call. Example property uses a demo broker (Suresh Kumar).
```
AGENT RECORD – Change 77
id: CHG-077
date: 2026-11-02
branch: staging (never main)
files: apps/flutter_app/lib/src/tk2/{tk2_store,tk2_link,tk2_visits,tk2_listing}.dart, apps/flutter_app/lib/src/tkweb/{tkweb_tenant,tkweb_app}.dart, apps/flutter_app/test/tk2/tk2_test.dart, docs/TRUSTKEEPER2-JOURNEYS.md, docs/CHANGELOG-staging.md
backend: reminder call 1 h before also reminds the broker about the gate pass + app push; on gatePass upload send it to the tenant on WhatsApp; on "not liked" notify the broker
verification: flutter analyze clean; test/tk2 24/24; web app clicked through in headless Chromium (book → Your visit → liked → Block; not liked → We told broker). Broker gate-pass sheet not yet seen on a device.
open: tenant browsing the broker's other houses (later); money rule for late cancel (broker half) needs Aman's sign-off
```
