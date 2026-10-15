import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/tenancy_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/tenancy/move_in_screen.dart';
import 'package:trustkeyper/src/features/tenancy/tenancy_gateway.dart';

class RevocableTenancyGateway extends OfflineTenancyGateway {
  RevocableTenancyGateway(super.fixture);
  final records = StreamController<TenancyRecord>.broadcast();
  final codeResult = Completer<Map<String, dynamic>>();
  @override
  Stream<TenancyRecord> watch(String agreementId, String role) =>
      Stream.multi((controller) {
        controller.add(TenancyRecord(fixture.data));
        final subscription = records.stream.listen(
          controller.add,
          onError: controller.addError,
        );
        controller.onCancel = subscription.cancel;
      });
  @override
  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) =>
      codeResult.future;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final fallback = FontLoader('GeneralSans');
    for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
      fallback.addFont(rootBundle.load('assets/fonts/GeneralSans-$weight.otf'));
    }
    await fallback.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> open(
    WidgetTester tester,
    OfflineTenancyFixture fixture, {
    String page = 'checklist',
    TenancyGateway? gateway,
    Future<DocumentFile?> Function()? camera,
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(fixture.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('tenancy-capture'),
          child: MoveInScreen(
            agreementId: 'offline-home',
            role: fixture.role,
            gateway: gateway ?? OfflineTenancyGateway(fixture),
            photos: fixture,
            camera: camera ?? fixture.camera,
            offline: true,
            initialPage: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!Platform.environment.containsKey('TRUSTKEYPER_CAPTURE_UI')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('tenancy-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../output/ui-audit/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'five-step move-in uses actual state and never labels unpaid money as received',
    (tester) async {
      final fixture = OfflineTenancyFixture();
      await open(tester, fixture);
      expect(find.text('1 of 5 done'), findsOneWidget);
      expect(find.text('0 of 2 tenants paid'), findsOneWidget);
      expect(find.text('0 of 64 items recorded'), findsOneWidget);
      await capture(tester, 'build25-move-in-checklist');
      await tester.tap(find.text('Deposit and first rent'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Only server-verified LIVE captures'),
        findsOneWidget,
      );
      expect(fixture.operations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'approved room counts and camera controls remain usable on small phones',
    (tester) async {
      final fixture = OfflineTenancyFixture();
      await open(tester, fixture, page: 'rooms', size: const Size(360, 720));
      expect(find.text('0 of 64 items recorded'), findsOneWidget);
      await capture(tester, 'build25-move-in-rooms');
      await tester.tap(find.text('Kitchen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Take photo of Kitchen overview'), findsOneWidget);
      expect(fixture.captured, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'meter fields are editable and saving never invents a missing photo',
    (tester) async {
      final fixture = OfflineTenancyFixture();
      await open(tester, fixture, page: 'meters');
      await tester.enterText(find.byType(TextField).first, '14582');
      await tester.enterText(find.byType(TextField).at(1), '3210');
      await tester.tap(find.text('No gas meter here'));
      await tester.pumpAndSettle();
      await capture(tester, 'build25-move-in-meters');
      await tester.tap(find.text('Save readings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add meter photos and readings before saving.'),
        findsOneWidget,
      );
      expect(fixture.data['meterComplete'], false);
      expect(find.text('Retry saved action'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unpaid key handover is disabled; no OTP sent or fake successful tenancy is shown',
    (tester) async {
      final fixture = OfflineTenancyFixture();
      await open(tester, fixture, page: 'keys');
      expect(find.text('Prepare tenant confirmation'), findsNothing);
      expect(find.textContaining('No SMS has been sent'), findsOneWidget);
      expect(fixture.data['phase'], 'preparing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'broker edits key counts and wrong code cannot finish even the isolated offline fixture',
    (tester) async {
      final fixture = OfflineTenancyFixture(ready: true);
      await open(tester, fixture, page: 'keys');
      await tester.tap(find.byIcon(Icons.add_circle).first);
      await tester.pumpAndSettle();
      await capture(tester, 'build25-move-in-keys');
      await tester.tap(find.text('Prepare tenant confirmation'));
      await tester.pumpAndSettle();
      expect(find.text('1 keys'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '000000');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(fixture.data['phase'], 'preparing');
      expect(find.text('That TEST code is not correct.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '654321');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(fixture.data['phase'], 'active');
      expect(find.text('Moved in!'), findsOneWidget);
      expect(find.textContaining('does not claim a transfer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant must confirm the actual count before requesting a private code',
    (tester) async {
      final fixture = OfflineTenancyFixture(role: 'tenant', ready: true);
      await open(tester, fixture, page: 'confirm');
      final button = find.widgetWithText(
        FilledButton,
        'Get my confirmation code',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('654321'), findsOneWidget);
      expect(fixture.operations, isEmpty);
      await capture(tester, 'build25-tenant-key-code');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a code arriving after access revocation cannot reopen confidential confirmation after recovery',
    (tester) async {
      final fixture = OfflineTenancyFixture(role: 'tenant', ready: true);
      final gateway = RevocableTenancyGateway(fixture);
      addTearDown(gateway.records.close);
      await open(tester, fixture, page: 'confirm', gateway: gateway);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get my confirmation code'));
      await tester.pump();
      gateway.records.addError(StateError('This home is no longer linked.'));
      await tester.pump();
      gateway.records.add(TenancyRecord(fixture.data));
      await tester.pump();
      gateway.codeResult.complete({
        'code': '999999',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      await tester.pumpAndSettle();
      expect(find.text('999999'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'move-out date, selected tenant and optional reason persist as a notice, not a refund',
    (tester) async {
      final fixture = OfflineTenancyFixture(
        role: 'tenant',
        ready: true,
        active: true,
      );
      await open(tester, fixture, page: 'notice');
      await tester.enterText(find.byType(TextField), 'Moving for work.');
      await tester.ensureVisible(
        find.text('I understand the lock-in warning.'),
      );
      await tester.tap(find.text('I understand the lock-in warning.'));
      await tester.pumpAndSettle();
      await capture(tester, 'build25-move-out-notice');
      await tester.tap(find.text('Send notice'));
      await tester.pumpAndSettle();
      final saved = fixture.data['notice'] as Map;
      expect(saved['date'], '2026-11-10');
      expect(saved['personIds'], ['priya']);
      expect(saved['reason'], 'Moving for work.');
      expect(fixture.data['phase'], 'active');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a replaced key challenge cannot display a late code from the old counts',
    (tester) async {
      final fixture = OfflineTenancyFixture(role: 'tenant', ready: true);
      final gateway = RevocableTenancyGateway(fixture);
      addTearDown(gateway.records.close);
      await open(tester, fixture, page: 'confirm', gateway: gateway);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get my confirmation code'));
      await tester.pump();
      fixture.data['challenge'] = {'id': 'new-challenge', 'personId': 'priya'};
      fixture.data['keys'] = {'mainDoor': 1};
      gateway.records.add(TenancyRecord(fixture.data));
      await tester.pump();
      gateway.codeResult.complete({
        'code': '999999',
        'challengeId': 'offline-challenge',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      await tester.pumpAndSettle();
      expect(find.text('999999'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> chooseRentDate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Pick payment date'));
    await tester.tap(find.text('Pick payment date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('13').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'remote meter edits block overwriting with an automatically refreshed version',
    (tester) async {
      final fixture = OfflineTenancyFixture(ready: true);
      final gateway = RevocableTenancyGateway(fixture);
      addTearDown(gateway.records.close);
      await open(tester, fixture, page: 'meters', gateway: gateway);
      await tester.enterText(find.byType(TextField).first, '100');
      final changed = Map<String, dynamic>.from(fixture.data);
      changed['version'] = 1;
      changed['meters'] = {
        'noGas': true,
        'electricity': {'reading': '999', 'checkId': 'new-photo'},
        'water': {'reading': '50', 'checkId': 'water-photo'},
      };
      gateway.records.add(TenancyRecord(changed));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save readings');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(fixture.operations, isEmpty);
      await tester.tap(find.text('Reload latest details'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '999',
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'broker follow-up needs a conversation and saves notes without recording money',
    (tester) async {
      final fixture = OfflineTenancyFixture(ready: true, active: true);
      fixture.data['today'] = '2026-11-08';
      await open(tester, fixture, page: 'rent');
      final save = find.widgetWithText(FilledButton, 'Save call notes');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(find.text('I spoke to the tenant'));
      await tester.tap(find.text('I spoke to the tenant'));
      await tester.enterText(
        find.byType(TextField),
        'Salary is delayed until Friday.',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.operations.single['action'], 'rent_call');
      expect((fixture.data['rent'] as List).first['status'], 'unpaid');
      expect(find.textContaining('Follow-up call notes saved'), findsOneWidget);
      await capture(tester, 'build25-rent-broker');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'broker extension requires owner informed and owner screen remains calm',
    (tester) async {
      final fixture = OfflineTenancyFixture(ready: true, active: true);
      fixture.data['today'] = '2026-11-08';
      await open(tester, fixture, page: 'rent', size: const Size(360, 720));
      await tester.ensureVisible(find.text('More time'));
      await tester.tap(find.text('More time'));
      await tester.pumpAndSettle();
      await chooseRentDate(tester);
      await tester.enterText(
        find.byType(TextField),
        'Owner agreed to the new date.',
      );
      final save = find.widgetWithText(FilledButton, 'Give more time');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(find.text('The owner is informed'));
      await tester.tap(find.text('The owner is informed'));
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.operations.single['payload']['date'], '2026-11-13');
      expect((fixture.data['rent'] as List).first['status'], 'unpaid');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'owner grants a saved date without a late-fee or late-red warning',
    (tester) async {
      final fixture = OfflineTenancyFixture(
        role: 'owner',
        ready: true,
        active: true,
      );
      fixture.data['today'] = '2026-11-08';
      await open(tester, fixture, page: 'rent');
      expect(find.textContaining('Rent yet to be paid'), findsWidgets);
      expect(find.textContaining('days late'), findsNothing);
      expect(find.text('The owner is informed'), findsNothing);
      await capture(tester, 'build25-rent-owner');
      await chooseRentDate(tester);
      await tester.enterText(
        find.byType(TextField),
        'Salary delay; more time approved.',
      );
      await tester.tap(find.text('Give more time'));
      await tester.pumpAndSettle();
      expect(fixture.operations.single['action'], 'rent_extension');
      expect(fixture.operations.single['payload']['date'], '2026-11-13');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant promise targets their own share and never changes the payment deadline',
    (tester) async {
      final fixture = OfflineTenancyFixture(
        role: 'tenant',
        ready: true,
        active: true,
      );
      fixture.data['today'] = '2026-11-08';
      await open(tester, fixture, page: 'rent');
      expect(find.text('Tenant'), findsNothing);
      await chooseRentDate(tester);
      await tester.enterText(
        find.byType(TextField),
        'My salary arrives next Friday.',
      );
      await tester.tap(find.text('Save my payment promise'));
      await tester.pumpAndSettle();
      expect(fixture.operations.single['payload']['personId'], 'priya');
      expect((fixture.data['rent'] as List).first['deadline'], '2026-11-05');
      expect((fixture.data['rent'] as List).first['status'], 'unpaid');
      await capture(tester, 'build25-rent-tenant');
      expect(tester.takeException(), isNull);
    },
  );
}
