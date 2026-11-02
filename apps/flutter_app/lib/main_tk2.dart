import 'package:flutter/material.dart';

import 'src/tk2/tk2_app.dart';

/// TrustKeeper 2 – broker MVP (properties, one-tap share, paid visits).
/// Runs on its own; data stays on the phone in this build.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrustKeeper2App());
}
