// Height of the phone keyboard in the browser. iPhone browsers (Safari, the
// WhatsApp in-app browser) put the keyboard over the page without telling
// Flutter, so we read it from the visual viewport ourselves.
export 'tkweb_keyboard_stub.dart' if (dart.library.js_interop) 'tkweb_keyboard_web.dart';
