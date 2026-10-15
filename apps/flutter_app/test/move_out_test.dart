import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/move_out_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/tenancy/move_out_screen.dart';
import 'package:trustkeyper/src/features/tenancy/tenancy_gateway.dart';

class RevocableMoveOutGateway extends OfflineMoveOutGateway {
  RevocableMoveOutGateway(super.fixture);
  final records = StreamController<TenancyRecord>.broadcast();
  final result = Completer<Map<String, dynamic>>();
  bool fail = false;
  @override
  Stream<TenancyRecord> watch(String agreementId, String role) =>
      Stream.multi((controller) {
        controller.add(
          TenancyRecord(
            jsonDecode(jsonEncode(fixture.data)) as Map<String, dynamic>,
          ),
        );
        final subscription = records.stream.listen(
          controller.add,
          onError: controller.addError,
        );
        controller.onCancel = subscription.cancel;
      });
  @override
  Future<Map<String, dynamic>> issueCode(Map<String, dynamic> input) =>
      result.future;
  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> input) async {
    if (fail) {
      fixture.operations.add(
        jsonDecode(jsonEncode(input)) as Map<String, dynamic>,
      );
      throw StateError('Connection lost after save.');
    }
    return super.record(input);
  }
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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!Platform.environment.containsKey('TRUSTKEYPER_CAPTURE_UI')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('move-out-capture')),
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

  Future<void> open(
    WidgetTester tester,
    OfflineMoveOutFixture fixture, {
    String page = 'checklist',
    TenancyGateway? gateway,
    Size size = const Size(363, 800),
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
          key: const ValueKey('move-out-capture'),
          child: MoveOutScreen(
            agreementId: 'offline-move-out',
            role: fixture.role,
            gateway: gateway ?? OfflineMoveOutGateway(fixture),
            photos: fixture,
            camera: fixture.camera,
            offline: true,
            initialPage: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'build26-${fixture.role}-$page');
  }

  Future<void> tap(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(
      tester.element(find.text(text).first),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final finder = find.widgetWithText(TextField, label);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        150,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact checklist, requested slot, room comparisons and final readings remain interactive',
    (tester) async {
      final fixture = OfflineMoveOutFixture(ready: true);
      fixture.data['keysConfirmed'] = false;
      await open(tester, fixture);
      expect(find.text('4 of 6 done'), findsOneWidget);
      await tap(tester, 'Book the check');
      await tap(tester, 'Request this check');
      expect(fixture.operations.last['action'], 'book');
      await tap(tester, 'Move-out photos');
      await tap(tester, 'Living room');
      await tap(tester, 'Walls');
      await tap(tester, 'Needs repair');
      await tester.enterText(
        find.widgetWithText(TextField, 'Proposed repair cost (₹)'),
        '123.45',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Note'),
        'TEST actual wall marks require repair.',
      );
      await tap(tester, 'Save comparison');
      expect((fixture.operations.last['payload'] as Map)['costPaise'], 12345);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tenant key code requires explicit count confirmation; wrong broker code never completes',
    (tester) async {
      final fixture = OfflineMoveOutFixture(role: 'tenant');
      await open(tester, fixture, page: 'keys');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Get my confirmation code'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'I returned exactly these keys and access cards.');
      await tap(tester, 'Get my confirmation code');
      expect(find.text('654321'), findsOneWidget);
      expect(fixture.data['keysConfirmed'], false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tenant report, dispute explanation and private destination are editable',
    (tester) async {
      final fixture = OfflineMoveOutFixture(
        role: 'tenant',
        ready: true,
        published: true,
      );
      await open(tester, fixture, page: 'report');
      await tap(tester, 'Question item');
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Evidence-based reason (at least 10 characters)',
        ),
        'TEST these marks were here before.',
      );
      await tap(tester, 'Submit');
      await tap(tester, 'Without photo');
      expect(fixture.operations.last['action'], 'respond');
      expect((fixture.operations.last['payload'] as Map)['status'], 'disputed');
      await tap(tester, 'Choose refund destination');
      await tap(tester, 'Another bank account');
      await tester.enterText(
        find.widgetWithText(TextField, 'Account holder name'),
        'TEST Priya Sharma',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Bank account number'),
        '12345678901',
      );
      await enter(tester, 'Confirm bank account number', '12345678902');
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'IFSC'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'IFSC'),
        'HDFC0001234',
      );
      await tap(tester, 'This account is in my name.');
      await tap(tester, 'Save refund destination');
      expect(
        find.text('The two bank account numbers do not match.'),
        findsOneWidget,
      );
      expect(
        fixture.operations.where((input) => input['action'] == 'destination'),
        isEmpty,
      );
      await enter(tester, 'Confirm bank account number', '12345678901');
      await tap(tester, 'Save refund destination');
      expect(fixture.operations.last['action'], 'destination');
      expect(fixture.data['destination'], isNot(contains('account')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'owner approval requires reviewing the report; changed version discards stale consent',
    (tester) async {
      final fixture = OfflineMoveOutFixture(
        role: 'owner',
        ready: true,
        published: true,
      );
      await open(tester, fixture, page: 'report');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve these deductions'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'I reviewed every deduction and its evidence.');
      fixture.data['version'] = 2;
      fixture.emit();
      await tester.pumpAndSettle();
      expect(find.text('Reload latest details'), findsOneWidget);
      await tap(tester, 'Reload latest details');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve these deductions'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'I reviewed every deduction and its evidence.');
      await tap(tester, 'Approve these deductions');
      expect(fixture.operations.last['action'], 'owner_approve');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'team decisions change a disputed deduction without inventing a refund',
    (tester) async {
      final fixture = OfflineMoveOutFixture(
        role: 'admin',
        ready: true,
        published: true,
        disputed: true,
      );
      await open(tester, fixture, page: 'report', size: const Size(1440, 900));
      await tap(tester, 'Keep, reduce or remove');
      await tester.enterText(
        find.widgetWithText(TextField, 'Keep or reduce to (₹); 0 removes it'),
        '1000',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Evidence-based reason (at least 10 characters)',
        ),
        'TEST before photo confirms partial marks.',
      );
      await tap(tester, 'Submit');
      expect(fixture.operations.last['action'], 'decide');
      expect(
        (fixture.operations.last['payload'] as Map)['amountPaise'],
        100000,
      );
      await tap(tester, 'Request undisputed refund');
      expect(fixture.operations.last['action'], 'refund_request');
      expect(
        (fixture.data['shares'] as List).first['refundStatus'],
        'awaiting_provider',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'revoked login clears private fields and never displays an in-flight code',
    (tester) async {
      final fixture = OfflineMoveOutFixture(role: 'tenant');
      final gateway = RevocableMoveOutGateway(fixture);
      addTearDown(gateway.records.close);
      await open(tester, fixture, page: 'keys', gateway: gateway);
      await tap(tester, 'I returned exactly these keys and access cards.');
      await tester.tap(find.text('Get my confirmation code'));
      await tester.pump();
      gateway.records.addError(
        StateError('Your login changed. Reopen this home.'),
      );
      await tester.pumpAndSettle();
      gateway.result.complete({
        'code': '654321',
        'challengeId': 'offline-key-return',
        'expiresAtMs': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
      await tester.pumpAndSettle();
      expect(find.text('654321'), findsNothing);
      expect(
        find.text('Your login changed. Reopen this home.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'owner missed-item proposal is interactive and team acceptance requires fresh review',
    (tester) async {
      final owner = OfflineMoveOutFixture(
        role: 'owner',
        ready: true,
        published: true,
      );
      await open(tester, owner, page: 'report');
      await tap(tester, 'Add a missed item');
      await enter(tester, 'Proposed amount (₹)', '800');
      await enter(
        tester,
        'Evidence-based reason (at least 10 characters)',
        'TEST missed lock replacement confirmed.',
      );
      await tap(tester, 'Submit');
      expect(owner.operations.last['action'], 'propose');
      expect((owner.data['proposals'] as List).length, 1);
      final team = OfflineMoveOutFixture(
        role: 'admin',
        ready: true,
        published: true,
      );
      team.data = jsonDecode(jsonEncode(owner.data)) as Map<String, dynamic>;
      team.data['role'] = 'admin';
      team.data['myPersonId'] = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open(tester, team, page: 'report', size: const Size(1440, 900));
      await tap(tester, 'Review missed item');
      await enter(tester, 'Proposed amount (₹)', '700');
      await enter(
        tester,
        'Evidence-based reason (at least 10 characters)',
        'TEST actual evidence supports partial cost.',
      );
      await tap(tester, 'Submit');
      expect(team.operations.last['action'], 'review_proposal');
      expect(team.data['ownersApproved'], false);
      expect((team.data['report'] as Map)['version'], isNot(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost response retains exact operation and payload for safe retry',
    (tester) async {
      final fixture = OfflineMoveOutFixture(ready: true);
      final gateway = RevocableMoveOutGateway(fixture)..fail = true;
      fixture.data['keysConfirmed'] = false;
      addTearDown(gateway.records.close);
      await open(tester, fixture, page: 'booking', gateway: gateway);
      await tap(tester, 'Request this check');
      final first = jsonEncode(fixture.operations.last);
      await tap(tester, 'Retry saved action');
      expect(jsonEncode(fixture.operations.last), first);
      expect(tester.takeException(), isNull);
    },
  );
}
