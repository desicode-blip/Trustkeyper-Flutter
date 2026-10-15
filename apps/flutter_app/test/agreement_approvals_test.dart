import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/approval_fixture.dart';
import 'package:trustkeyper/src/features/agreement_approvals/data/agreement_approvals.dart';
import 'package:trustkeyper/src/features/agreement_approvals/presentation/recipient_approval_screen.dart';
import 'package:trustkeyper/src/features/agreement_approvals/presentation/broker_approval_screen.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';

const token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class TestRecipient extends OfflineApprovalFixture {
  TestRecipient({super.role, super.changed});
  final calls = <Map<String, dynamic>>[];
  bool failReply = false;
  bool mismatch = false;
  Completer<ApprovalInfo>? delayedRead;
  @override
  Future<ApprovalInfo> read(String token) =>
      delayedRead?.future ?? super.read(token);
  @override
  Future<ApprovalInfo> reply(
    String token,
    ApprovalInfo info,
    Map<String, dynamic> reply,
  ) async {
    calls.add(Map.from(reply));
    if (failReply) throw const DocumentFailure('Test network interrupted.');
    final result = await super.reply(token, info, reply);
    return mismatch
        ? ApprovalInfo({...result.data, 'digest': 'wrong-version'})
        : result;
  }
}

class TestBrokerApprovals implements AgreementApprovals {
  final controller = StreamController<List<Map<String, dynamic>>>();
  int calls = 0;
  @override
  Stream<List<Map<String, dynamic>>> watch(String agreementId, int revision) =>
      controller.stream;
  @override
  Future<List<ApprovalLink>> prepare(
    String agreementId,
    int revision, {
    String? refreshPartyId,
  }) async {
    calls++;
    return [];
  }
}

Future<void> show(
  WidgetTester tester,
  TestRecipient gateway, {
  String link = token,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RecipientApprovalScreen(token: link, gateway: gateway),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      350,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  if (find.text('Say yes to these demo details?').evaluate().isNotEmpty) {
    await tapVisible(tester, find.text('Go back'));
  }
  await tapVisible(tester, find.text('Read full demo agreement'));
  expect(find.text('Demo agreement · Not for signing'), findsOneWidget);
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tapVisible(tester, find.text('Yes, I agree · demo only'));
  await tapVisible(tester, find.text('I have read the full demo agreement'));
  await tapVisible(
    tester,
    find.text('I agree to these demo rent, deposit and terms'),
  );
}

void main() {
  testWidgets(
    'reply actions stay visible and confirmation uses the bottom sheet',
    (tester) async {
      tester.view.physicalSize = const Size(363, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = TestRecipient();
      await show(tester, gateway);
      final button = find.text('Yes, I agree · demo only');
      expect(tester.getRect(button).bottom, lessThan(800));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == const Color(0x80172231),
        ),
        findsOneWidget,
      );
      expect(find.text('Say yes to these demo details?'), findsOneWidget);
      expect(gateway.calls, isEmpty);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == const Color(0x80172231),
        ),
        findsNothing,
      );
      expect(find.text('Something is wrong'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation stays scrollable with enlarged accessibility text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: RecipientApprovalScreen(token: token, gateway: TestRecipient()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, I agree · demo only'));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'owner approval uses real terms; two checks and full read gate the reply',
    (tester) async {
      final gateway = TestRecipient();
      await show(tester, gateway);
      expect(find.text('Check the agreement'), findsOneWidget);
      await tapVisible(tester, find.text('Yes, I agree · demo only'));
      expect(gateway.calls, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Yes, I agree · demo only'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Yes, I agree · demo only'),
      );
      expect(button.onPressed, isNull);
      await confirm(tester);
      await tapVisible(tester, find.text('Yes, I agree · demo only'));
      expect(gateway.calls.single['readAll'], true);
      expect(gateway.calls.single['agreeTerms'], true);
      expect(find.text('You said yes'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Not a legal contract'),
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Not a legal contract'), findsOneWidget);
    },
  );
  testWidgets(
    'tenant sees their own exact shares, not contract totals as personal money',
    (tester) async {
      await show(tester, TestRecipient(role: 'tenant'));
      expect(find.text('Your rent share'), findsOneWidget);
      expect(find.text('₹22,000 of ₹22,000'), findsOneWidget);
      expect(find.text('Your deposit share'), findsOneWidget);
      expect(find.text('₹44,000 of ₹44,000'), findsOneWidget);
    },
  );
  testWidgets(
    'change request is editable, validated and confirmed by the gateway',
    (tester) async {
      final gateway = TestRecipient();
      await show(tester, gateway);
      await tapVisible(tester, find.text('Something is wrong'));
      await tapVisible(tester, find.text('Send change request'));
      expect(gateway.calls, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'Please change the start date.',
      );
      await tapVisible(tester, find.text('Dates'));
      await tapVisible(tester, find.text('Send change request'));
      expect(gateway.calls.single['category'], 'Dates');
      expect(gateway.calls.single['note'], 'Please change the start date.');
      expect(find.text('Change request sent'), findsOneWidget);
    },
  );
  testWidgets(
    'interrupted reply locks editing and retries exactly the same operation',
    (tester) async {
      final gateway = TestRecipient()..failReply = true;
      await show(tester, gateway);
      await confirm(tester);
      await tapVisible(tester, find.text('Yes, I agree · demo only'));
      expect(gateway.calls.length, 1);
      expect(find.text('You said yes'), findsNothing);
      gateway.failReply = false;
      await tapVisible(tester, find.text('Retry same reply'));
      expect(gateway.calls.length, 2);
      expect(gateway.calls.first, gateway.calls.last);
      expect(find.text('You said yes'), findsOneWidget);
    },
  );
  testWidgets(
    'wrong version returned by server never displays confirmed agreement',
    (tester) async {
      final gateway = TestRecipient()..mismatch = true;
      await show(tester, gateway);
      await confirm(tester);
      await tapVisible(tester, find.text('Yes, I agree · demo only'));
      expect(find.text('You said yes'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('server did not confirm'),
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('server did not confirm'), findsOneWidget);
    },
  );
  testWidgets(
    'new token discards delayed old private response and form state',
    (tester) async {
      final old = TestRecipient()..delayedRead = Completer<ApprovalInfo>();
      await tester.pumpWidget(
        MaterialApp(
          home: RecipientApprovalScreen(token: token, gateway: old),
        ),
      );
      final next = TestRecipient(role: 'tenant')..verified = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RecipientApprovalScreen(
            token: token.replaceAll('a', 'c'),
            gateway: next,
          ),
        ),
      );
      old.delayedRead!.complete(await OfflineApprovalFixture().read(token));
      await tester.pumpAndSettle();
      expect(find.text('Check the agreement'), findsNothing);
      expect(find.textContaining('Verify the number ending'), findsOneWidget);
      expect(find.textContaining('Flat 402'), findsNothing);
    },
  );
  testWidgets(
    'bad and expired links show recoverable states without private terms',
    (tester) async {
      await show(tester, TestRecipient(), link: '../../wrong');
      expect(find.text('Agreement unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Check the agreement'), findsNothing);
    },
  );
  testWidgets(
    'changed-version flow works on narrow screens and marks server-reported changes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester, TestRecipient(changed: true));
      await tapVisible(tester, find.text('Rent paid by · Changed'));
      expect(find.text('10 of each month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'broker status list reflects actual replies and keeps incomplete review blocked',
    (tester) async {
      final repository = TestBrokerApprovals();
      addTearDown(repository.controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerApprovalScreen(
            draft: OfflineApprovalFixture().draft,
            repository: repository,
          ),
        ),
      );
      repository.controller.add([
        {'partyId': 'owner-test', 'status': 'agreed'},
        {
          'partyId': 'tenant-test',
          'status': 'change_requested',
          'reply': {'note': 'Please change the deposit.'},
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Saved version 1 · 1 of 2 said yes'), findsOneWidget);
      expect(find.text('Asked for a change'), findsOneWidget);
      await tapVisible(tester, find.text('Please change the deposit.'));
      expect(repository.calls, 0);
    },
  );
}
