#!/bin/bash
# Builds the TrustKeyper tenant/owner web app (lib/main_tk2_web.dart) into build/tkweb,
# ready for static hosting (trustkeyper.com or any CDN). Run from apps/flutter_app.
#   - no CDN for CanvasKit (works on strict hosts), no service worker
#   - relative paths, so it can live under any folder
#   - restarts once if the host passes the link (#p-… / #owner-…) after start
set -e
flutter build web -t lib/main_tk2_web.dart --no-web-resources-cdn --pwa-strategy=none --release
OUT=build/tkweb
rm -rf "$OUT"; cp -r build/web "$OUT"; cd "$OUT"
find . -name '*.symbols' -delete
rm -rf canvaskit/skwasm* assets/packages/pdfrx firebase-startup.js version.json flutter_service_worker.js .last_build_id assets/NOTICES assets/AssetManifest.bin assets/assets/agreements assets/shaders
sed -i 's#<base href="/">#<base href="./">#; s#<script src="firebase-startup.js"></script>##; s#TrustKeyper Flutter application for brokers, owners, tenants, and administrators.#TrustKeyper – see the house, book a visit, rent safely.#; s#Loading your secure workspace…#Loading…#; s#Opening TrustKeyper</p>#TrustKeyper</p>#' index.html
sed -i 's#<link rel="icon" type="image/png" href="favicon.png"/>#<link rel="icon" type="image/png" sizes="64x64" href="favicon.png"/><link rel="icon" type="image/png" sizes="192x192" href="icons/Icon-192.png"/>#' index.html
sed -i 's#<script src="flutter_bootstrap.js" async></script>#<script>window.addEventListener("hashchange", function () { location.reload(); });</script><script src="flutter_bootstrap.js" async></script>#' index.html
mv tkweb_favicon.png favicon.png
echo "Built $OUT"
