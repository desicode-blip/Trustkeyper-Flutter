#!/bin/bash
# Builds the TrustKeyper web app for all three (broker with the lead desk,
# tenant and owner from their links) into build/tkdesk.
# See docs/TRUSTKEEPER2-DESK.md.
# Run from apps/flutter_app. Optional: TK2_WEB_APP=<url> to point links at this site.
set -e
flutter build web -t lib/main_tk2_desk.dart --pwa-strategy=none --release --no-wasm-dry-run \
  ${TK2_WEB_APP:+--dart-define=TK2_WEB_APP=$TK2_WEB_APP}
OUT=build/tkdesk
rm -rf "$OUT"; cp -r build/web "$OUT"; cd "$OUT"
find . -name '*.symbols' -delete
rm -rf assets/packages/pdfrx firebase-startup.js flutter_service_worker.js .last_build_id assets/NOTICES
cp ../../tool/tkdesk/tkleads.js .
sed -i 's#<base href="/">#<base href="./">#; s#<script src="firebase-startup.js"></script>##; s#<script src="flutter_bootstrap.js" async></script>#<script src="tkleads.js"></script><script src="flutter_bootstrap.js" async></script>#; s#<title>[^<]*</title>#<title>TrustKeyper</title>#' index.html
echo "Built $OUT"
