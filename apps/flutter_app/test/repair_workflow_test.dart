import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/repair_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/auth/data/account_roles.dart';
import 'package:trustkeyper/src/features/auth/presentation/auth_screens.dart';
import 'package:trustkeyper/src/features/repairs/data/repair_gateway.dart';
import 'package:trustkeyper/src/features/repairs/presentation/admin_repair_editor.dart';
import 'package:trustkeyper/src/features/repairs/presentation/repair_detail_screen.dart';

Future<void> capture(WidgetTester tester, String name) async {
  if (!Platform.environment.containsKey('TRUSTKEYPER_CAPTURE_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../../output/ui-audit/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
    final generalSans = FontLoader('GeneralSans');
    for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      generalSans.addFont(
        rootBundle.load('assets/fonts/GeneralSans-$weight.otf'),
      );
    }
    await generalSans.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(key: const ValueKey('capture'), child: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'rupees parse without floating-point rounding or accepting invalid money',
    () {
      expect(repairPaise('2800'), 280000);
      expect(repairPaise('12.3'), 1230);
      expect(repairPaise('12.34'), 1234);
      for (final value in [
        '0',
        '-1',
        '0.001',
        'NaN',
        '1,200',
        '1000001',
        '1e3',
      ]) {
        expect(repairPaise(value), isNull);
      }
    },
  );
  testWidgets(
    'owner quote is actionable and approval changes the shared state',
    (tester) async {
      final fixture = OfflineRepairFixture();
      addTearDown(fixture.changes.close);
      await open(
        tester,
        RepairDetailScreen(
          issueId: 'test-repair',
          gateway: fixture,
          photoReader: fixture,
          offline: true,
        ),
      );
      expect(find.text('Repair cost (quote)'), findsOneWidget);
      expect(find.text('₹2,800'), findsOneWidget);
      await capture(tester, 'build24-owner-repair-approval');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(fixture.data['status'], 'approved');
      expect(find.text('Approve'), findsNothing);
      await capture(tester, 'build24-owner-repair-approved');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'completed repair shows private bill, before/after and reconciliation truth',
    (tester) async {
      final fixture = OfflineRepairFixture(completed: true);
      addTearDown(fixture.changes.close);
      await open(
        tester,
        RepairDetailScreen(
          issueId: 'test-repair',
          gateway: fixture,
          photoReader: fixture,
          offline: true,
        ),
      );
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Repair bill'), findsOneWidget);
      expect(find.text('Awaiting confirmation'), findsOneWidget);
      expect(find.text('7 Oct payout'), findsOneWidget);
      expect(find.textContaining('No money is moved'), findsOneWidget);
      await capture(tester, 'build24-owner-repair-completed');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tenant can confirm work and small phone layout does not overflow',
    (tester) async {
      final fixture = OfflineRepairFixture(role: 'tenant', completed: true);
      addTearDown(fixture.changes.close);
      await open(
        tester,
        RepairDetailScreen(
          issueId: 'test-repair',
          gateway: fixture,
          photoReader: fixture,
          offline: true,
        ),
        size: const Size(360, 720),
      );
      await tester.tap(find.text('Working now'));
      await tester.pumpAndSettle();
      expect(fixture.data['status'], 'closed');
      expect(find.text('Working now ✓'), findsOneWidget);
      expect(find.text('Awaiting confirmation'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'role switching uses registered roles; adding a role is separate and selectable',
    (tester) async {
      final gateway = OfflineAccountRoleGateway();
      String? selected;
      await open(
        tester,
        AccountRoleScreen(
          gateway: gateway,
          onSelected: (route) => selected = route,
        ),
      );
      expect(find.text('Welcome back, Rahul'), findsOneWidget);
      await capture(tester, 'build24-role-switch');
      await tester.tap(find.text('Property owner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue as property owner'));
      await tester.pumpAndSettle();
      expect(selected, '/ui-test/workspace/owner');
      await tester.tap(find.text('Add another role'));
      await tester.pumpAndSettle();
      expect(
        find.text('This does not link new homes or approve a broker.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tenant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add tenant'));
      await tester.pumpAndSettle();
      expect(gateway.roles, contains('tenant'));
      expect(selected, '/ui-test/workspace/tenant');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed secure stream clears stale repair rather than offering approval',
    (tester) async {
      final fixture = OfflineRepairFixture();
      final gateway = _FailureGateway(fixture);
      addTearDown(fixture.changes.close);
      await open(
        tester,
        RepairDetailScreen(
          issueId: 'test-repair',
          gateway: gateway,
          photoReader: fixture,
        ),
      );
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'admin completion shows real evidence inputs and requires a completed visit',
    (tester) async {
      final fixture = OfflineRepairFixture(role: 'admin');
      fixture.data = {
        ...fixture.data,
        'status': 'assigned',
        'photos': <Map<String, dynamic>>[],
        'visit': {
          'startsAtMs': DateTime(2026, 9, 25, 11).millisecondsSinceEpoch,
        },
      };
      addTearDown(fixture.changes.close);
      await open(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AdminRepairEditor(
                issueId: 'test-repair',
                gateway: fixture,
                photoReader: fixture,
                onBack: () {},
              ),
            ),
          ),
        ),
        size: const Size(1120, 800),
      );
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Bill & close'), findsOneWidget);
      await capture(tester, 'build24-admin-repair-completion');
      await tester.tap(find.text('Mark fixed · share with owner and tenant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add the bill, after photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FailureGateway implements RepairGateway {
  _FailureGateway(this.fixture);
  final OfflineRepairFixture fixture;
  @override
  Stream<RepairRecord> watch(String issueId) =>
      Stream.error(StateError('Access removed'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
