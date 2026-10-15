# Working on TrustKeyper

Read `AGENTS.md` and `docs/handoff-status.md` first. Continue the existing
feature branch unless Ajay requests another. Do not merge, push, deploy or
modify production data as a side effect of local development.

Only Flutter/Firebase is supported. Application changes belong to
`apps/flutter_app`; privileged operations belong to `functions`. Use approved
designs/requirements in `output/design-reference` and
`output/requirements-reference`, not the retired application's UI.

Run focused tests before the suites in `TESTING.md`. Do not regenerate visual
baselines to conceal a mismatch. Preserve the isolated offline UI Test package
and original phone installation. Never use customer documents for fixtures or
log keys, OTPs, passwords and signing material.

Backend dependencies use `functions/package-lock.json`; Flutter dependencies
use `apps/flutter_app/pubspec.lock`. Do not reintroduce legacy packages,
deployment providers or local SQL databases. Keep releases explicit.
