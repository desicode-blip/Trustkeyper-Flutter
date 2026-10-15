import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/participant_fixture.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';
import 'package:trustkeyper/src/features/participants/presentation/participant_workspace_screen.dart';

class PrivateRouteFixture {
  String? uid = OfflineParticipantFixture.owner.uid;
  List<ParticipantRecord> records = [OfflineParticipantFixture.agreement];
  final users = StreamController<void>.broadcast();
  final updates = StreamController<void>.broadcast();
  late final repository = SessionParticipantRepository(
    identities: Stream.multi((controller) {
      controller.add(uid);
      final subscription = users.stream.listen(
        (_) => controller.add(uid),
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    }),
    query: (collection, uid) => Stream.multi((controller) {
      controller.add(collection == 'agreements' ? List.of(records) : []);
      final subscription = updates.stream.listen(
        (_) =>
            controller.add(collection == 'agreements' ? List.of(records) : []),
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    }),
  );
  Future<void> dispose() async {
    await users.close();
    await updates.close();
  }
}

Future<void> openPrivateProperty(
  WidgetTester tester,
  PrivateRouteFixture fixture,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ParticipantWorkspaceScreen(
        repository: fixture.repository,
        role: 'owner',
        identity: OfflineParticipantFixture.owner,
        initialTab: 1,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(OfflineParticipantFixture.agreement.text('propertyAddress')),
  );
  await tester.pumpAndSettle();
  expect(find.text('Record reference: offline-home'), findsOneWidget);
}

Future<void> openPrivateChildren(WidgetTester tester) async {
  final context = tester.element(find.text('Record reference: offline-home'));
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            const Scaffold(body: Text('Private child document')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(
    showDialog<void>(
      context: tester.element(find.text('Private child document')),
      builder: (context) =>
          const AlertDialog(content: Text('Private modal contents')),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Private modal contents'), findsOneWidget);
}

void main() {
  for (final uid in [null, 'another-account']) {
    testWidgets('an open private route hides records on account change $uid', (
      tester,
    ) async {
      final fixture = PrivateRouteFixture();
      await openPrivateProperty(tester, fixture);
      await openPrivateChildren(tester);
      fixture.uid = uid;
      fixture.users.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Record reference: offline-home'), findsNothing);
      expect(find.text('Private child document'), findsNothing);
      expect(find.text('Private modal contents'), findsNothing);
      expect(
        find.text('Your session ended. Log in to reopen your private records.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await fixture.dispose();
    });
  }
  for (final denied in [false, true]) {
    testWidgets(
      'private route refreshes live data and hides revoked access $denied',
      (tester) async {
        final fixture = PrivateRouteFixture();
        await openPrivateProperty(tester, fixture);
        fixture.records = [
          ParticipantRecord(OfflineParticipantFixture.agreement.id, {
            ...OfflineParticipantFixture.agreement.data,
            'propertyAddress': 'Updated private address',
          }),
        ];
        fixture.updates.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Updated private address'), findsOneWidget);
        await openPrivateChildren(tester);
        if (denied) {
          fixture.updates.addError(StateError('Permission denied'));
        } else {
          fixture.records = [];
          fixture.updates.add(null);
        }
        await tester.pumpAndSettle();
        expect(find.text('Updated private address'), findsNothing);
        expect(find.text('Record reference: offline-home'), findsNothing);
        expect(find.text('Private child document'), findsNothing);
        expect(find.text('Private modal contents'), findsNothing);
        expect(
          find.text(
            'This private record is no longer available. Reopen your account to check access.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
      },
    );
  }
}
