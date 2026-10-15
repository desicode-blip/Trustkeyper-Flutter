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
