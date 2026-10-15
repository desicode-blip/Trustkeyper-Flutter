# Local legacy-stack retirement — 15 October 2026

Ajay requested that only Flutter/Firebase remain. The primary checkout is now
`D:\Trustkeyper\Project`; the existing migration worktree also retains only
this stack. No branch was changed, commit made or Git history rewritten.

## Removed from the active trees

- Expo/React Native `apps/mobile` and React `artifacts` applications.
- Express/Vercel `api`, TypeScript `lib`, Supabase SQL/configuration,
  attached legacy assets and local prototype data.
- pnpm workspace/lockfile, old root dependencies/node_modules, TypeScript and
  Vitest API setup, Docker/Postgres and Vercel/Replit configuration.
- Old seed/backfill/migration scripts, Supabase project skills, obsolete CI,
  editor launches and legacy setup documentation.

Root npm commands now operate only on Flutter/Firebase. Node.js is still
required for Cloud Functions and must not be removed as old technology.
The new app's Razorpay test/Route code remains; final provider work is deferred.

## Preserved

Flutter sources, fonts/images, approved artboards, requirements, Firebase
configuration/rules/indexes, backend/tests, release tooling and evidence are
preserved. Non-generated app source is checked against the build-46 snapshot
before and after transfer/testing. Its 40 historical generated test-difference
images are excluded from future source snapshots; original signed-release
evidence and golden baselines are not rewritten. The original native build-46
AAB/APK outputs match their recorded release hashes and are retained in the
primary project's `output/releases/build46`; their Downloads paths were no
longer present at the final audit. Housekeeping does not require
a new app version or imply full product acceptance.

Upload signing was copied and hash-checked into `$HOME\.trustkeyper\signing`.
Release tooling uses `android-upload.json` there or the
`TRUSTKEYPER_SIGNING_CREDENTIALS_FILE` override. The original key and Google Play
certificate identity are retained. Do not share its contents.

## Recovery and boundaries

Backup: `D:\Trustkeyper\LegacyBackup-2026-10-15`, restricted to the current
Windows user and SYSTEM. `moves.jsonl` records original and backup paths,
including previously modified legacy files. It is outside the active project
and not a build dependency. Do not restore it over the new app or commit its
environment files. Keep until acceptance; permanent erasure is separate.
Disposable installed dependency caches are discarded rather than backed up;
the former manifests, lockfile, source edits and local data remain recoverable.

Other existing Git worktrees are not recursively deleted. Git history, remote
GitHub/Vercel/Supabase resources, Firebase projects/data/secrets, billing, DNS
and installed phone apps are unchanged. No remote purge is part of cleanup.

`output/maintenance` records copy/cleanup verification. Ignored output/build
caches are local material, not automatically restored by Git. Product status
remains governed by `docs/product-requirements-coverage.md`.
