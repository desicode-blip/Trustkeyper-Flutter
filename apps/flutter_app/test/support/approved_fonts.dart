import 'package:flutter/services.dart';

Future<void> loadApprovedFonts() async {
  final roboto = FontLoader('Roboto');
  for (final weight in [400, 500, 600, 700]) {
    roboto.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
  }
  final fallback = FontLoader('GeneralSans');
  for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
    fallback.addFont(rootBundle.load('assets/fonts/GeneralSans-$weight.otf'));
  }
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([roboto.load(), fallback.load(), icons.load()]);
}
