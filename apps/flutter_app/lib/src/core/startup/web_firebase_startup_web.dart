import 'dart:js_interop';

@JS('trustkeyperPrepareFirebase')
external JSPromise<JSAny?> _prepareFirebase();

Future<void> prepareWebFirebase() async {
  await _prepareFirebase().toDart.timeout(const Duration(seconds: 120));
}

@JS('trustkeyperReloadStartupPage')
external void _reloadStartupPage();

void reloadStartupPage() => _reloadStartupPage();

@JS('trustkeyperUsesTemporaryStorage')
external JSBoolean _usesTemporaryStorage();

bool hasTransientBrowserStorage() => _usesTemporaryStorage().toDart;
