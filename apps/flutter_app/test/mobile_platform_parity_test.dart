import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/ui_test_main.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final role in ['owner', 'tenant']) {
      testWidgets(
        '$platform $role uses the shared broker document flow',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = UiTestApp();
          await tester.pumpWidget(app);
          app.router.go('/ui-test/broker-documents/$role/empty');
          await tester.pumpAndSettle();
          expect(find.text('Aadhaar card'), findsOneWidget);
          expect(find.text('PAN card'), findsOneWidget);
          expect(find.text('Bank account'), findsOneWidget);
          expect(
            find.byTooltip('Send link'),
            findsNWidgets(role == 'tenant' ? 4 : 3),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          app.router.dispose();
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
