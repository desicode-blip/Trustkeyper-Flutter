# TrustKeeper 2 – lead desk (Change 97)

Live: **https://app.trustkeyper.com** (Cloudflare Pages project `trustkeyper-app` in Aman's Cloudflare account; DNS: CNAME `app` → `trustkeyper-app.pages.dev` at GoDaddy). desk.trustkeyper.com and the TK2 staging site are untouched.

## What it is
The TK2 broker app with a lead layer in front of it. One web build serves all three people:
- broker: the TK2 broker app; on a laptop (≥ 960 px) a sidebar adds Today, Tenants, Homes, Import leads, AI helpers next to Home, Visits, Payments, Profile; on a phone a "Leads" button on Home;
- tenant and owner: their links (`#p-`, `#l-`, `#owner-`, `#i-`, `#deal-`, `#d-`) open the existing tkweb screens (`lib/main_tk2_desk.dart`).

## Code
| File | What |
| --- | --- |
| `lib/main_tk2_desk.dart` | One entry: customer links → tkweb, else broker app |
| `lib/src/tkdesk/tkdesk_lead.dart` | Lead model; fields from the sheets' top rows; must-haves |
| `lib/src/tkdesk/tkdesk_match.dart` | Matching rules (tested) |
| `lib/src/tkdesk/tkdesk_import.dart` | TK Lead Format v1 / sheet CSV import |
| `lib/src/tkdesk/tkdesk_store.dart` | Saving: device first, then team storage (`/api/leads`) or Firestore `tk2Leads` (backend build) |
| `lib/src/tkdesk/tkdesk_screens.dart` | Desk screens |
| `lib/src/tkdesk/tkdesk_helpers.dart` | AI helper jobs and triggers |
| `tool/build_tkdesk.sh` | Web build (`TK2_WEB_APP=https://app.trustkeyper.com/ ./tool/build_tkdesk.sh`) |
| `tool/tkdesk/_worker.js` | Cloudflare storage worker (D1 `trustkeyper-desk`, binding `DB`) |
| `tool/tkdesk/tkleads.js` | Opens encrypted lead batches published under `leads/` |
| `test/tk2/tkdesk_match_test.dart` | Matching and import tests |

Changes to existing files: `tk2_app.dart` (shell: sidebar on wide screens, Leads button on phones), `tk2_link.dart` (`tk2WebApp` can be set with `--dart-define=TK2_WEB_APP`, default unchanged), `pubspec.yaml` (`web` package as a dependency).

## Rules
- Tenant needs BHK to be matched; home needs BHK + rent and must be Active.
- BHK within 0.5; budget up to the max fits, up to 10% over is "slightly over", more is out; no budget = not checked.
- Must-have on either side is a hard rule; unknown on the other side = "Ask on call".
- Fewer than 3 matches: closest misses (one block) are added.
- Homes: Active / Not active (3 questions: why, free again when, note) / Cancelled permanently (reason). Nothing is ever deleted.
- "Send homes" is "Coming soon" in v1; presses are logged.

## Storage (nothing lost)
- Every lead is saved on the device, then to the team storage. The worker keeps the newest version of each lead and appends every save to a `log` table that is never changed.
- Every edit is in the lead's `history` (field, old, new, who, when). Download everything / Restore on the Import screen.
- Team password unlocks storage and published lead batches. The worker checks its SHA-256 (placeholder `__HASH__` in the repo copy; the deployed copy has the real hash). To change it, set the secret `TEAM_PASS_SHA256` in the Pages project.

## For Ajay
- Nothing to deploy for the live desk. When the Firestore backend should hold leads too: add a `tk2Leads/{id}` rule (owner `brokerUid` only, no delete) and build with `tk2_cloud.json`.
- Later: the broker phone layout of the welcome slides on a laptop; real per-person logins instead of demo OTP on the web desk.
