import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/tk2/tk2_store.dart';
import 'src/tkweb/tkweb_app.dart';
import 'src/tkweb/tkweb_session.dart';

/// TrustKeyper web app for tenants and house owners (opened from WhatsApp links).
/// Build: flutter build web -t lib/main_tk2_web.dart --no-web-resources-cdn --pwa-strategy=none
Future<void> main() async {
  // Read the link (#p-… or #owner-…) before Flutter could touch the address bar,
  // then switch URL handling off: the app moves between screens on its own.
  final fragment = Uri.base.fragment;
  setUrlStrategy(null);
  WidgetsFlutterBinding.ensureInitialized();
  await Tk2Store.instance.load();
  await TkwSession.instance.load();
  final start = await TkwStart.fromFragment(fragment);
  runApp(TkWebApp(start: start));
}
