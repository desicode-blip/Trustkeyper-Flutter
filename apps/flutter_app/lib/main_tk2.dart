import 'package:flutter/material.dart';

import 'src/tk2/tk2_app.dart';
import 'src/tk2/tk2_cloud.dart';
import 'src/tk2/tk2_store.dart';
import 'src/tk2/tk2_sync.dart';

/// TrustKeeper 2 – broker app (properties, one-tap share, paid visits).
/// Demo build: data stays on the phone. Built with tk2_cloud.json the backend
/// is on (docs/TRUSTKEEPER2-BACKEND.md).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Tk2Cloud.start();
  if (Tk2Cloud.on) Tk2Store.instance.sync = Tk2Sync(Tk2Store.instance);
  runApp(const TrustKeeper2App());
}
