#!/usr/bin/env bash
# TrustKeeper 2 builds. See docs/TRUSTKEEPER2-BACKEND.md.
#
#   scripts/tk2-build.sh web            owner/tenant web app, demo (no backend)
#   scripts/tk2-build.sh web staging    owner/tenant web app on the staging backend
#   scripts/tk2-build.sh broker staging broker app for a connected phone (flutter run)
#   scripts/tk2-build.sh deploy-web     upload build/tk2_web to Firebase Hosting (target tk2, staging)
#
# "staging" reads apps/flutter_app/tk2_cloud.json (copy tk2_cloud.example.json and fill it).
set -euo pipefail
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$self")/../apps/flutter_app"
what="${1:-}"; env="${2:-demo}"
defines=()
if [[ "$env" == "staging" ]]; then
  [[ -f tk2_cloud.json ]] || { echo "Missing apps/flutter_app/tk2_cloud.json (copy tk2_cloud.example.json)"; exit 1; }
  defines=(--dart-define-from-file=tk2_cloud.json)
fi
case "$what" in
  web)
    flutter build web -t lib/main_tk2_web.dart --release --no-web-resources-cdn --pwa-strategy=none "${defines[@]}" -o build/tk2_web
    echo "Built apps/flutter_app/build/tk2_web" ;;
  broker)
    flutter run -t lib/main_tk2.dart --release "${defines[@]}" ;;
  deploy-web)
    cd ../..
    firebase deploy --config firebase.tk2.json --only hosting:tk2 --project staging ;;
  *)
    sed -n '2,9p' "$self"; exit 1 ;;
esac
