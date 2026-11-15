// Browser-only helpers for the desk (download a file, open published leads).
// Elsewhere (the phone build) they do nothing, so the app still builds.
export 'tkdesk_web_stub.dart' if (dart.library.js_interop) 'tkdesk_web_web.dart';
