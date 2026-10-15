import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/participants/data/participant_repository.dart';
import 'package:trustkeyper/src/features/participants/presentation/participant_records_screen.dart';
import 'package:trustkeyper/src/features/owner/presentation/owner_shell.dart';
import 'package:trustkeyper/src/features/tenant/presentation/tenant_shell.dart';
import 'agreement_draft_test.dart' show sampleDraft;

class RecordsFake implements ParticipantRepository {
  RecordsFake(Stream<List<ParticipantRecord>> stream)
    : records = stream.asBroadcastStream();
  final Stream<List<ParticipantRecord>> records;
  @override
  Stream<List<ParticipantRecord>> watch(String collection) =>
      records.map((items) => items);
}

void main() {
  testWidgets('linked validated terms open only a non-signable demo', (
    tester,
  ) async {
    final draft = sampleDraft();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParticipantRecordsScreen(
            repository: RecordsFake(
              Stream.value([
                ParticipantRecord(draft.id, {
                  ...draft.toMap(),
                  'participantUids': ['tenant-test'],
                  'status': 'draft',
                }),
              ]),
            ),
            role: 'Tenant',
            collection: 'agreements',
            title: 'Your agreements',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Read demo terms · Not for signing'),
      100,
    );
    await tester.ensureVisible(find.text('Read demo terms · Not for signing'));
    await tester.tap(find.text('Read demo terms · Not for signing'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO ONLY'), findsOneWidget);
    expect(find.text('Sign agreement'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('records reject malformed and guessed financial amounts', () {
    final record = ParticipantRecord('id', {
      'negative': -1,
      'float': 1.5,
      'text': '10000',
      'zero': 0,
      'amountPaise': 10001,
    });
    expect(record.amount('missing'), isNull);
    expect(record.amount('negative'), isNull);
    expect(record.amount('float'), isNull);
    expect(record.amount('text'), isNull);
    expect(record.amount('zero'), 0);
    expect(record.amount('amountPaise'), 10001);
  });
  test(
    'session switching clears data and filters unauthorized records',
    () async {
      final identities = StreamController<String?>();
      final first = StreamController<List<ParticipantRecord>>();
      final second = StreamController<List<ParticipantRecord>>();
      final repository = SessionParticipantRepository(
        identities: identities.stream,
        query: (_, uid) => uid == 'first' ? first.stream : second.stream,
      );
      final values = <List<ParticipantRecord>>[];
      final subscription = repository.watch('agreements').listen(values.add);
      identities.add('first');
      await Future<void>.delayed(Duration.zero);
      first.add([
        ParticipantRecord('allowed', {
          'participantUids': ['first'],
        }),
        ParticipantRecord('forbidden', {
          'participantUids': ['other'],
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(values.last.single.id, 'allowed');
      identities.add('second');
      await Future<void>.delayed(Duration.zero);
      expect(values.last, isEmpty);
      first.add([
        ParticipantRecord('stale', {
          'participantUids': ['first'],
        }),
      ]);
      second.add([
        ParticipantRecord('new', {
          'participantUids': ['second'],
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(values.last.single.id, 'new');
      identities.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(values.last, isEmpty);
      await subscription.cancel();
      await identities.close();
      await first.close();
      await second.close();
    },
  );
  test('unknown collection never performs a query', () {
    final repository = SessionParticipantRepository(
      identities: const Stream.empty(),
      query: (_, _) => throw StateError('must not query'),
    );
    expect(() => repository.watch('users'), throwsArgumentError);
  });
  testWidgets(
    'owner and tenant first login contain no fictional contacts or money',
    (tester) async {
      for (final screen in [
        OwnerShell(repository: RecordsFake(Stream.value(const []))),
        TenantShell(repository: RecordsFake(Stream.value(const []))),
      ]) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        expect(find.textContaining('No linked records yet'), findsOneWidget);
        expect(find.textContaining('Rajesh'), findsNothing);
        expect(find.textContaining('Priya'), findsNothing);
        expect(find.textContaining('Phoenix'), findsNothing);
        expect(find.textContaining('₹11,000'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets('stream error hides old data and retry recovers', (tester) async {
    final stream = StreamController<List<ParticipantRecord>>.broadcast();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParticipantRecordsScreen(
            repository: RecordsFake(stream.stream),
            role: 'Tenant',
            collection: 'payments',
            title: 'Your payments',
          ),
        ),
      ),
    );
    await tester.pump();
    stream.add([
      ParticipantRecord('payment-test', {
        'propertyAddress': 'Test Flat',
        'amountPaise': 10001,
        'status': 'pending',
      }),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Recorded amount: ₹100.01'), findsOneWidget);
    stream.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Test Flat'), findsNothing);
    expect(find.textContaining('Could not load your records'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Retry'), 100);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    stream.add([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('No linked records yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await stream.close();
  });
}
