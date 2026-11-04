import 'package:flutter/foundation.dart';

/// Not on the web: Flutter already knows the keyboard height.
final ValueNotifier<double> tkwKeyboard = ValueNotifier(0);
void tkwWatchKeyboard() {}
