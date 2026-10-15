import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/owner_property_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/owner/data/owner_properties.dart';
import 'package:trustkeyper/src/features/owner/presentation/owner_lifecycle_screen.dart';
import 'owner_lifecycle_test.dart' as fixture;

void main() {
  testWidgets(
    'render actual owner fee, listing and tenant decision screens with approved fonts',
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
      final fallback = FontLoader('GeneralSans');
      for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
        fallback.addFont(
          rootBundle.load('assets/fonts/GeneralSans-$weight.otf'),
        );
      }
      await fallback.load();
      final boundary = GlobalKey();
      Future<void> open(OwnerPropertyRecord property) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: OwnerLifecycleScreen(
                key: ValueKey(property.status),
                property: property,
                gateway: fixture.TestOwnerLifecycleGateway(),
                proof: fixture.TestOwnerPhoneProof(),
                properties: OfflineOwnerPropertyGateway(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/trustkeyper-logo-approved.png'),
            boundary.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await renderer.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../../output/ui-audit/build31-ui-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      await open(fixture.testOwnerLifecycleProperty());
      await capture('owner-fee');
      await open(fixture.testOwnerLifecycleProperty(status: 'plan_active'));
      await tester.tap(find.text('Find a tenant').last);
      await tester.pumpAndSettle();
      await capture('owner-listing');
      final live = fixture.testOwnerLifecycleProperty(status: 'listing_live');
      await open(
        OwnerPropertyRecord({
          ...live.data,
          'candidates': {
            'e' * 64: {
              'name': 'TEST Priya',
              'status': 'interested',
              'household': 3,
              'work': 'TEST workplace',
              'moveIn': '2026-11-01',
              'identityCheck': {'checked': true},
            },
          },
        }),
      );
      await tester.tap(find.text('See interested tenants'));
      await tester.pumpAndSettle();
      await capture('owner-tenants');
      await tester.tap(find.text('TEST Priya'));
      await tester.pumpAndSettle();
      await capture('owner-tenant-choice');
    },
  );
}
