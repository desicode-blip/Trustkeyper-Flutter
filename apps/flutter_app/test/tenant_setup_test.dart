import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/tenant_setup_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/tenant/data/tenant_setup.dart';
import 'package:trustkeyper/src/features/tenant/presentation/tenant_setup_screen.dart';

Future<void> open(
  WidgetTester tester,
  TenantSetupGateway gateway, {
  String id = 'test',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: TenantSetupScreen(agreementId: id, gateway: gateway),
    ),
  );
  await tester.pumpAndSettle();
}

class DelayedTenantGateway extends OfflineTenantSetupGateway {
  final pendingRead = Completer<TenantSetupData>();
  @override
  Future<TenantSetupData> read(String agreementId) => pendingRead.future;
}

void main() {
  test('share input is exact integer paise, not floating-point currency', () {
    expect(tenantSharePaise('12,000.01'), 1200001);
    expect(tenantSharePaise('0.5'), 50);
    expect(tenantSharePaise('1,23,456.78'), 12345678);
    for (final input in [
      '-1',
      '1.234',
      'NaN',
      '',
      '1e6',
      '1000000000',
      '1,2',
      '12,34',
    ]) {
      expect(tenantSharePaise(input), isNull);
    }
  });
  testWidgets(
    'tenant confirms linked home, actual flatmates and actual shares before all-set',
    (tester) async {
      final gateway = OfflineTenantSetupGateway();
      await open(tester, gateway);
      expect(find.text('Is this your home?'), findsOneWidget);
      await tester.tap(find.text('Yes, this is my home'));
      await tester.pumpAndSettle();
      expect(gateway.values['homeConfirmed'], true);
      expect(find.text('Priya Sharma (you)'), findsOneWidget);
      await tester.tap(find.text('Yes, that is right'));
      await tester.pumpAndSettle();
      expect(find.text('Your rent share'), findsOneWidget);
      expect(find.text('₹11,000'), findsOneWidget);
      await tester.tap(find.text('Looks good'));
      await tester.pumpAndSettle();
      expect(find.text('You are all set!'), findsOneWidget);
      expect(gateway.values['complete'], true);
    },
  );
  testWidgets(
    'invalid requested share stays inline and never sends; valid request preserves current share',
    (tester) async {
      final gateway = OfflineTenantSetupGateway(step: 2);
      await open(tester, gateway);
      await tester.tap(find.text('Change my share'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '22001');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your share cannot exceed the total rent.'),
        findsOneWidget,
      );
      expect(gateway.values['request'], isNull);
      await tester.enterText(find.byType(TextField).first, '12000.01');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect(find.text('Sent for OK'), findsOneWidget);
      expect(gateway.values['rentSharePaise'], 1100000);
      expect((gateway.values['request'] as Map)['rentSharePaise'], 1200001);
    },
  );
  testWidgets(
    'pending request survives reopening without being marked all-set',
    (tester) async {
      final gateway = OfflineTenantSetupGateway();
      await gateway.record('test', 1, 'request', kind: 'home');
      await open(tester, gateway);
      expect(find.text('Sent for OK'), findsOneWidget);
      expect(find.text('You are all set!'), findsNothing);
    },
  );
  testWidgets('timed-out read releases busy state and offers retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TenantSetupScreen(
          agreementId: 'test',
          gateway: DelayedTenantGateway(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 46));
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('taking too long'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets(
    'replacement home cannot be overwritten by the old pending read',
    (tester) async {
      final oldGateway = DelayedTenantGateway();
      final replacement = OfflineTenantSetupGateway();
      replacement.values['property'] = 'TEST replacement home';
      await tester.pumpWidget(
        MaterialApp(
          home: TenantSetupScreen(agreementId: 'old', gateway: oldGateway),
        ),
      );
      await open(tester, replacement, id: 'new');
      oldGateway.pendingRead.complete(TenantSetupData(oldGateway.values));
      await tester.pumpAndSettle();
      expect(find.text('TEST replacement home'), findsOneWidget);
      expect(find.text('Flat 402, Phoenix Towers'), findsNothing);
    },
  );
  testWidgets(
    'narrow phone and enlarged text stay scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(363, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(363, 800),
              textScaler: TextScaler.linear(1.4),
            ),
            child: TenantSetupScreen(
              agreementId: 'test',
              gateway: OfflineTenantSetupGateway(step: 2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Looks good'), findsOneWidget);
    },
  );
}
