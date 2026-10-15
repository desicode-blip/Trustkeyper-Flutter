import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/owner_property_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/core/widgets/session_bound_screen.dart';
import 'package:trustkeyper/src/features/owner/data/owner_properties.dart';
import 'package:trustkeyper/src/features/owner/presentation/owner_property_setup_screen.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    OfflineOwnerPropertyGateway gateway, {
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OwnerPropertySetupScreen(gateway: gateway, offline: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final target = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  testWidgets('owner property text can be all blank or a name only', (
    tester,
  ) async {
    for (final name in ['', 'rjh']) {
      final gateway = OfflineOwnerPropertyGateway();
      await open(tester, gateway);
      await tap(tester, 'Add your property');
      await tap(tester, 'Rent it out');
      if (name.isNotEmpty) await fill(tester, 'Name for this home', name);
      await tap(tester, 'Next');
      expect(gateway.attempts, 1);
      expect(find.text('Complete this field'), findsNothing);
      expect(find.text('Address (optional)'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'owner saves five editable steps, survives retry and requests a real plan without fake activation',
    (tester) async {
      final gateway = OfflineOwnerPropertyGateway();
      await open(tester, gateway);
      await tap(tester, 'Add your property');
      await tap(tester, 'Rent it out');
      expect(gateway.attempts, 0);
      expect(find.text('Complete this field'), findsNothing);
      await fill(
        tester,
        'Address (optional)',
        'TEST ONLY Flat 1, Example Road, Hyderabad',
      );
      await fill(tester, 'Name for this home', 'TEST saved home');
      gateway.failNext = true;
      await tap(tester, 'Next');
      expect(find.text('OFFLINE TEST · retry the saved step.'), findsOneWidget);
      await tap(tester, 'Next');
      expect(gateway.records.values.single.nextStep, 1);
      for (final entry in {
        'Bathrooms': '2',
        'Balconies': '1',
        'Floor': '2',
        'Total floors': '5',
        'Size · sq ft': '1000',
      }.entries) {
        await fill(tester, entry.key, entry.value);
      }
      await tap(tester, 'Next');
      await tap(tester, 'AC');
      await tap(tester, 'Next');
      await fill(tester, 'Rent every month * · ₹', '20000');
      await fill(tester, 'Deposit * · ₹', '40000');
      await tap(tester, 'Next');
      await tap(tester, 'Save property');
      expect(
        find.text('Add 1 to 5 clear photos, or request our team to take them.'),
        findsOneWidget,
      );
      final team = find.byType(CheckboxListTile).last;
      await tester.ensureVisible(team);
      await tester.tap(team);
      await tester.pumpAndSettle();
      await tap(tester, 'Save property');
      expect(gateway.records.values.single.status, 'property_added');
      await tap(tester, 'Next: Pick a plan');
      await tap(tester, 'We do it all');
      await tap(tester, 'Next: Free check');
      await tap(tester, 'Request check');
      expect(gateway.records.values.single.status, 'check_requested');
      expect(gateway.records.values.single.data['plan'], 'full_service');
      expect(find.text('Check requested'), findsOneWidget);
      expect(
        find.text('Contract: not signed yet\nListing: not live yet'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'owner resumes a saved step with real editable fields on a new screen instance',
    (tester) async {
      final gateway = OfflineOwnerPropertyGateway();
      gateway.records['saved'] = OwnerPropertyRecord({
        'id': 'saved',
        'revision': 2,
        'nextStep': 1,
        'status': 'draft',
        'details': {
          'address': 'TEST saved address',
          'name': 'TEST saved home',
          'bathrooms': 2,
          'floor': 1,
          'totalFloors': 4,
          'sizeSqFt': 850,
        },
        'photos': [],
      });
      await open(tester, gateway);
      await tap(tester, 'TEST saved home');
      await fill(tester, 'Bathrooms', '3');
      expect(find.widgetWithText(TextFormField, '3'), findsOneWidget);
      expect(gateway.records['saved']!.revision, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'owner entry and choices fit a narrow phone without loading Firebase',
    (tester) async {
      await open(
        tester,
        OfflineOwnerPropertyGateway(),
        size: const Size(320, 680),
      );
      await tap(tester, 'Add your property');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Rent it out');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'private screen removes old form state when account changes and hides it after sign-out',
    (tester) async {
      final users = StreamController<String?>();
      addTearDown(users.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionBoundScreen(
            users: users.stream,
            initialUid: 'first',
            child: const Scaffold(body: TextField()),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'PRIVATE old account');
      users.add('second');
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE old account'), findsNothing);
      users.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Log in again'), findsOneWidget);
    },
  );
}
