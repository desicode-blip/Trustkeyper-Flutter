import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/broker_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_shell.dart';

void main() {
  test('only an approved, unpaused profile can create agreements', () {
    expect(profile('approved').canCreateAgreements, isTrue);
    expect(profile('pending').canCreateAgreements, isFalse);
    expect(profile('rejected').canCreateAgreements, isFalse);
    expect(profile('approved', paused: true).canCreateAgreements, isFalse);
    expect(
      BrokerProfile.fromMap({
        'approvalStatus': 'approved',
        'paused': true,
      }).canCreateAgreements,
      isFalse,
    );
    expect(BrokerProfile.fromMap({}).canCreateAgreements, isFalse);
  });

  testWidgets('live approval overrides a stale pending route flag', (
    tester,
  ) async {
    final repository = ApprovalRepository(Stream.value(profile('approved')));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerShell(approvalPending: true, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.text('Make rent agreement'),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale approved route cannot unlock a pending account', (
    tester,
  ) async {
    final repository = ApprovalRepository(Stream.value(profile('pending')));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerShell(approvalPending: false, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.text('Waiting for approval'),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
  });

  testWidgets(
    'approval, revocation and pause update without restarting subscriptions',
    (tester) async {
      final controller = StreamController<BrokerProfile>();
      addTearDown(controller.close);
      final repository = ApprovalRepository(controller.stream);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerShell(approvalPending: true, repository: repository),
        ),
      );
      controller.add(profile('pending'));
      await tester.pumpAndSettle();
      controller.add(profile('approved'));
      await tester.pumpAndSettle();
      expect(find.text('Make rent agreement'), findsOneWidget);
      await tester.tap(find.text('Agreements'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Make new agreement'),
            )
            .onPressed,
        isNotNull,
      );
      controller.add(profile('rejected'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Make new agreement'),
            )
            .onPressed,
        isNull,
      );
      controller.add(profile('approved', paused: true));
      await tester.pumpAndSettle();
      expect(find.text('Your account is paused'), findsOneWidget);
      expect(find.text('Make new agreement'), findsNothing);
      expect(repository.profileSubscriptions, 1);
      expect(repository.agreementSubscriptions, 1);
      expect(repository.paymentSubscriptions, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a profile-stream error fails closed after approval', (
    tester,
  ) async {
    final controller = StreamController<BrokerProfile>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerShell(
          approvalPending: false,
          repository: ApprovalRepository(controller.stream),
        ),
      ),
    );
    controller.add(profile('approved'));
    await tester.pumpAndSettle();
    controller.addError(StateError('Profile unavailable'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(
              of: find.text('Waiting for approval'),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

BrokerProfile profile(String approvalStatus, {bool paused = false}) =>
    BrokerProfile(
      displayName: 'Ajay Bhatnagar',
      email: 'ajay@example.com',
      phone: '+919999999999',
      approvalStatus: approvalStatus,
      paused: paused,
    );

class ApprovalRepository implements BrokerRepository {
  ApprovalRepository(this.profiles);
  final Stream<BrokerProfile> profiles;
  int profileSubscriptions = 0;
  int agreementSubscriptions = 0;
  int paymentSubscriptions = 0;

  @override
  Stream<BrokerProfile> watchProfile() {
    profileSubscriptions++;
    return profiles;
  }

  @override
  Stream<List<BrokerAgreementSummary>> watchAgreements() {
    agreementSubscriptions++;
    return Stream.value(const []);
  }

  @override
  Stream<List<BrokerPaymentSummary>> watchPayments() {
    paymentSubscriptions++;
    return Stream.value(const []);
  }
}
