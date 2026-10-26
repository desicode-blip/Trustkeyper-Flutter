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
