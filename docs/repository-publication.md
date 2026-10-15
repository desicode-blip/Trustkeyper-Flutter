# Flutter repository publication

The authorised destination is
`https://github.com/desicode-blip/Trustkeyper-Flutter.git`. It is public.
Publish a clean source snapshot, not the previous repository's Git history.
The app, assets, tests, Firebase backend, rules/indexes and platform configuration
are included. Android/iOS use the same Dart code and existing Firebase project.

Never publish provider secrets, Apple/Android signing material, Firebase CLI
credentials, service accounts, customer documents/data, local output, build
binaries or dependency caches. Firebase client configuration is intentionally
included so the correct existing app can start; it grants no administrator role.

Historical operational scripts/release notes containing configured production
test-login instructions remain local. Unit/emulator fixtures are synthetic and
are retained, not an app-side login bypass. Ask the project owner privately for
designated live testing accounts. The source-publishing utility records excluded
local files and copied-file hashes in local ignored output, never their secrets.
Current setup/testing instructions are in `ios-macos-setup.md` and `TESTING.md`.

No deployment workflow or store upload is part of this publication. Apple team,
APNs and signing configuration must be completed on the Mac/in the company's
consoles; do not commit private keys. Native iPhone acceptance is not certified
by Windows tests. The earlier document-state test-clock failures and remaining
product/financial acceptance are not concealed by publishing a new repository.
