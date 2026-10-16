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
