import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/tk2/tk2_cloud.dart';
import 'src/tk2/tk2_store.dart';
import 'src/tk2/tk2_sync.dart';
import 'src/tkweb/tkweb_app.dart';
import 'src/tkweb/tkweb_session.dart';

/// TrustKeyper web app for tenants and house owners (opened from WhatsApp links).
/// Build: scripts/tk2-build.sh web (demo) or scripts/tk2-build.sh web staging (backend on).
Future<void> main() async {
  // Read the link (#p-… or #owner-…) before Flutter could touch the address bar,
  // then switch URL handling off: the app moves between screens on its own.
  final fragment = Uri.base.fragment;
  setUrlStrategy(null);
  WidgetsFlutterBinding.ensureInitialized();
  // Backend on only when built with tk2_cloud.json (docs/TRUSTKEEPER2-BACKEND.md).
  await Tk2Cloud.start();
  if (Tk2Cloud.on) Tk2Store.instance.sync = Tk2Sync(Tk2Store.instance);
  await Tk2Store.instance.load();
  await TkwSession.instance.load();
  // Still logged in from last time: follow own visits again.
  if (Tk2Cloud.uid != null && TkwSession.instance.signedIn) Tk2Store.instance.sync?.startTenant();
  final start = await TkwStart.fromFragment(fragment);
  runApp(TkWebApp(start: start));
}
