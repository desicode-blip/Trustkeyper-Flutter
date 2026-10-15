import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/core/testing/tenant_setup_fixture.dart';
import 'package:trustkeyper/src/features/tenant/presentation/tenant_setup_screen.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_web_entry_screen.dart';
import 'support/approved_fonts.dart';

void main() {
  setUpAll(() async {
    await loadApprovedFonts();
  });
  for (final stage in [0, 1, 2]) {
    testWidgets('tenant setup stage $stage matches reviewed native layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: const ValueKey('screen'),
            child: TenantSetupScreen(
              agreementId: 'offline-home',
              gateway: OfflineTenantSetupGateway(step: stage),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/trustkeyper-logo-approved.png'),
          tester.element(find.byKey(const ValueKey('screen'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile('goldens/build44/tenant-setup-$stage.png'),
      );
    });
  }
  for (final size in [const Size(440, 956), const Size(1440, 900)]) {
    testWidgets('broker web handoff at ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: const ValueKey('screen'),
            child: BrokerWebEntryScreen(
              phone: '+91 98480 11223',
              openLink: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/trustkeyper-logo-approved.png'),
          tester.element(find.byKey(const ValueKey('screen'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('screen')),
        matchesGoldenFile(
          'goldens/build44/broker-handoff-${size.width.toInt()}.png',
        ),
      );
    });
  }
}
