#!/usr/bin/env bash
# TrustKeeper 2 builds. See docs/TRUSTKEEPER2-BACKEND.md.
#
#   scripts/tk2-build.sh web            owner/tenant web app, demo (no backend)
#   scripts/tk2-build.sh web staging    owner/tenant web app on the staging backend
#   scripts/tk2-build.sh broker staging broker app for a connected phone (flutter run)
#   scripts/tk2-build.sh deploy-web     upload build/tk2_staging_web to the dedicated staging site
#
# "staging" reads apps/flutter_app/tk2_cloud.json (copy tk2_cloud.example.json and fill it).
set -euo pipefail
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$self")/../apps/flutter_app"
what="${1:-}"; env="${2:-demo}"
defines=()
output=build/tk2_web
if [[ "$env" == "staging" || "$what" == "deploy-web" ]]; then
  [[ -f tk2_cloud.json ]] || { echo "Missing apps/flutter_app/tk2_cloud.json (copy tk2_cloud.example.json)"; exit 1; }
  node -e '
    const config = require("./tk2_cloud.json");
    const rc = require("node:fs").readFileSync("../../.firebaserc", "utf8");
    const project = "trustkeyper-app-staging";
    const sites = JSON.parse(rc).targets?.[project]?.hosting?.tk2;
    if (sites?.length !== 1 || sites[0] === project ||
        config.TK2_WEB_URL?.replace(/\/$/, "") !== `https://${sites[0]}.web.app` ||
        config.TK2_FIREBASE_PROJECT_ID !== project || config.TK2_EMULATOR_HOST ||
        config.TK2_FIREBASE_STORAGE_BUCKET !== `${project}.firebasestorage.app` ||
        !config.TK2_FIREBASE_API_KEY || !config.TK2_FIREBASE_APP_ID_WEB) {
      process.exitCode = 1;
      console.error("Use the dedicated TK2 staging site and Firebase project settings.");
    }
  '
  defines=(--dart-define-from-file=tk2_cloud.json)
  output=build/tk2_staging_web
elif [[ "$env" != "demo" ]]; then
  echo "Unknown build environment: $env" >&2
  exit 1
fi
case "$what" in
  web)
    flutter build web -t lib/main_tk2_web.dart --release --no-web-resources-cdn --pwa-strategy=none "${defines[@]}" -o "$output"
    echo "Built apps/flutter_app/$output" ;;
  broker)
    flutter run -t lib/main_tk2.dart --release "${defines[@]}" ;;
  deploy-web)
    [[ -f "$output/index.html" ]] || { echo "Build the TK2 staging web app first."; exit 1; }
    cd ../..
    firebase deploy --config firebase.tk2.json --only hosting:tk2 --project trustkeyper-app-staging ;;
  *)
    sed -n '2,9p' "$self"; exit 1 ;;
esac
