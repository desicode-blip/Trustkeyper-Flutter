import 'dart:js_interop';

@JS('window.close')
external void _close();

/// Browsers close only tabs a script opened; otherwise this is ignored.
void tkwCloseTab() => _close();
