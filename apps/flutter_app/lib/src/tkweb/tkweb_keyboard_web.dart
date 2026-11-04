import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/foundation.dart';

extension type _Viewport(JSObject _) implements JSObject {
  external double get height;
  external double get offsetTop;
  external void addEventListener(String type, JSFunction listener);
}

@JS('window.visualViewport')
external _Viewport? get _viewport;

@JS('window.innerHeight')
external double get _innerHeight;

@JS('window.scrollTo')
external void _scrollTo(double x, double y);

/// Keyboard height in logical pixels (0 when closed).
final ValueNotifier<double> tkwKeyboard = ValueNotifier(0);

bool _watching = false;

/// Start listening once; the page then lifts its button above the keyboard.
void tkwWatchKeyboard() {
  final v = _viewport;
  if (_watching || v == null) return;
  _watching = true;
  void update() {
    // iOS also slides the page up to show the field; put it back, since the
    // app itself now moves things above the keyboard.
    if (v.offsetTop > 0) _scrollTo(0, 0);
    final covered = _innerHeight - v.height;
    // Small changes are browser bars, not the keyboard.
    tkwKeyboard.value = covered > 80 ? max(0, covered) : 0;
  }

  final listener = ((JSAny _) => update()).toJS;
  v.addEventListener('resize', listener);
  v.addEventListener('scroll', listener);
  update();
}
