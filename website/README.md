# TrustKeyper Website (trustkeyper.com)

Everything for the public marketing website lives in this folder. It is separate from the Flutter app (`apps/flutter_app`) and does not change it.

| Folder | What it is |
| --- | --- |
| `site/` | The website: page sources, styles, scripts, images and the build script |
| `api/` | The website's backend (Dart, runs on Google Cloud Run): OTP verification and enquiries |
| `docs/DEVELOPER_GUIDE.md` | **Start here.** What has been built, what the developer still has to do, and every consideration |

## Quick start

```bash
# Website: build the deployable files into site/dist/
cd site && python3 build.py

# Preview locally
python3 -m http.server 8080 --directory dist

# Backend: run tests and a local server (codes are printed, not sent)
cd ../api && dart pub get && dart test
TK_SECRET=$(openssl rand -hex 32) dart run bin/server.dart
```

Pages: Home (homeowners) `/`, Property Agents `/for-property-agents` (English, Hindi, Telugu), Builders `/for-builders`, Contact `/contact-us`, About, FAQs, Privacy, Terms, Delete account.

Read `docs/DEVELOPER_GUIDE.md` before deploying anything.
