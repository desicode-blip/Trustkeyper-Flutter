import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/owner_property_fixture.dart';
import 'package:trustkeyper/src/core/testing/signing_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/presentation/sign_only_screen.dart';
import 'package:trustkeyper/src/features/owner/data/owner_properties.dart';
import 'package:trustkeyper/src/features/owner/presentation/owner_property_setup_screen.dart';

void main() {
  testWidgets(
    'renders owner and signing entry at approved artboard size with real bundled fonts',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fonts/Roboto-400.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-500.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-600.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-700.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final owner = OfflineOwnerPropertyGateway();
      owner.records['visual'] = OwnerPropertyRecord({
        'id': 'visual',
        'revision': 1,
        'nextStep': 0,
        'status': 'draft',
        'details': {
          'address': 'TEST ONLY Flat 1, Example Road, Hyderabad',
          'name': 'TEST home',
          'homeType': 'Apartment',
        },
        'photos': [],
      });
      final boundary = GlobalKey();
      Future<void> save(String name) async {
        await tester.pumpAndSettle();
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final destination = File(
            '../../output/ui-audit/build30-ui-$name.png',
          );
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: OwnerPropertySetupScreen(gateway: owner),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEST home'));
      await save('owner-step1');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: SignOnlyScreen(gateway: OfflineSigningGateway()),
          ),
        ),
      );
      await save('signing-entry');
    },
  );
}
