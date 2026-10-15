import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft_repository.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'agreement_draft_test.dart' show sampleDraft;

class DraftStoreFake implements DraftPersistence {
  Map<String, dynamic>? record;
  int writes = 0;
  void Function()? beforeCommit;
  final references = <String>[];
  @override
  String newId() => 'generated-id';
  @override
  Future<Map<String, dynamic>?> read(String id) async {
    references.add(id);
    return record;
  }

  @override
  Future<void> transact(
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  ) async {
    references.add(id);
    beforeCommit?.call();
    record = {...?record, ...update(record)};
    writes++;
  }
}

void main() {
  test(
    'renewal saves preserve the backend date timestamp across client timezones',
    () async {
      final frozenStart = Timestamp.fromDate(DateTime.utc(2026, 10, 1, 9, 17));
      final store = DraftStoreFake()
        ..record = {
          ...sampleDraft().toMap(),
          'propertyId': 'home',
          'renewalSourceId': 'source',
          'effectiveDate': frozenStart,
          'brokerUid': 'broker',
          'participantUids': ['broker'],
          'status': 'draft',
          'revision': 1,
        };
      final repository = FirebaseAgreementDraftRepository(
        currentUid: () => 'broker',
        persistence: store,
      );
      final loaded = await repository.load('test-draft');
      await repository.save(loaded);
      expect(store.record!['effectiveDate'], frozenStart);
      expect(store.record!['startDateISO'], '2026-10-01T00:00:00.000');
      expect(store.record!['renewalSourceId'], 'source');
      expect(store.record!['revision'], 2);
    },
  );
  test(
    'renewal saves reject a changed start, home or missing frozen timestamp before writing',
    () async {
      for (final change in [
        {'startDateISO': '2026-10-02T00:00:00.000'},
        {'propertyId': 'another-home'},
        {'renewalSourceId': 'another-source'},
      ]) {
        final store = DraftStoreFake()
          ..record = {
            ...sampleDraft().toMap(),
            'propertyId': 'home',
            'renewalSourceId': 'source',
            'effectiveDate': Timestamp.fromDate(DateTime.utc(2026, 10, 1)),
            'brokerUid': 'broker',
            'participantUids': ['broker'],
            'status': 'draft',
            'revision': 1,
          };
        final repository = FirebaseAgreementDraftRepository(
          currentUid: () => 'broker',
          persistence: store,
        );
        final loaded = await repository.load('test-draft');
        final changed = AgreementDraft.fromMap(loaded.id, {
          ...loaded.toMap(),
          'revision': 1,
          ...change,
        });
        await expectLater(
          repository.save(changed),
          throwsA(isA<DraftFailure>()),
        );
        expect(store.writes, 0);
      }
      final store = DraftStoreFake()
        ..record = {
          ...sampleDraft().toMap(),
          'renewalSourceId': 'source',
          'brokerUid': 'broker',
          'participantUids': ['broker'],
          'status': 'draft',
          'revision': 1,
        };
      final repository = FirebaseAgreementDraftRepository(
        currentUid: () => 'broker',
        persistence: store,
      );
      await expectLater(
        repository.save(await repository.load('test-draft')),
        throwsA(isA<DraftFailure>()),
      );
      expect(store.writes, 0);
    },
  );
  test(
    'saves a stable private draft with all parties and exact money',
    () async {
      final store = DraftStoreFake();
      final repository = FirebaseAgreementDraftRepository(
        currentUid: () => 'broker',
        persistence: store,
      );
      await repository.save(sampleDraft());
      expect(store.record!['participantUids'], ['broker']);
      expect(store.record!['brokerUid'], 'broker');
      expect(store.record!['status'], 'draft');
      expect(store.record!['revision'], 1);
      expect(store.record!['brokerageFeePaise'], 3300000);
      expect((store.record!['owners'] as List).length, 2);
      expect((store.record!['tenants'] as List).length, 2);
      expect(
        store.record!['effectiveDate'],
        Timestamp.fromDate(DateTime(2026, 10, 1)),
      );
      final loaded = await repository.load('test-draft');
      expect(loaded.revision, 1);
      expect(loaded.validationError, isNull);
      await repository.save(loaded);
      expect(store.record!['revision'], 2);
      expect(store.references, everyElement('test-draft'));
    },
  );
  test('concurrent draft revision cannot be overwritten', () async {
    final store = DraftStoreFake()
      ..record = {
        ...sampleDraft().toMap(),
        'brokerUid': 'broker',
        'status': 'draft',
        'participantUids': ['broker'],
        'revision': 2,
      };
    final repository = FirebaseAgreementDraftRepository(
      currentUid: () => 'broker',
      persistence: store,
    );
    await expectLater(
      repository.save(sampleDraft()),
      throwsA(isA<DraftFailure>()),
    );
    expect(store.writes, 0);
  });
  test('draft edits cannot remove already linked participant access', () async {
    final store = DraftStoreFake()
      ..record = {
        ...sampleDraft().toMap(),
        'brokerUid': 'broker',
        'status': 'draft',
        'participantUids': ['broker', 'owner-user'],
      };
    final repository = FirebaseAgreementDraftRepository(
      currentUid: () => 'broker',
      persistence: store,
    );
    await expectLater(
      repository.save(sampleDraft()),
      throwsA(isA<DraftFailure>()),
    );
    expect(store.writes, 0);
    expect(store.record!['participantUids'], ['broker', 'owner-user']);
  });
  test(
    'sent agreements and another brokers records cannot be edited or loaded',
    () async {
      for (final record in [
        {...sampleDraft().toMap(), 'brokerUid': 'broker', 'status': 'signed'},
        {
          ...sampleDraft().toMap(),
          'brokerUid': 'different-broker',
          'status': 'draft',
        },
      ]) {
        final store = DraftStoreFake()..record = record;
        final repository = FirebaseAgreementDraftRepository(
          currentUid: () => 'broker',
          persistence: store,
        );
        await expectLater(
          repository.load('test-draft'),
          throwsA(isA<DraftFailure>()),
        );
        await expectLater(
          repository.save(sampleDraft()),
          throwsA(isA<DraftFailure>()),
        );
        expect(store.writes, 0);
      }
    },
  );
  test('logout, changed session and invalid shares produce no write', () async {
    final store = DraftStoreFake();
    String? uid;
    final repository = FirebaseAgreementDraftRepository(
      currentUid: () => uid,
      persistence: store,
    );
    await expectLater(
      repository.save(sampleDraft()),
      throwsA(isA<DraftFailure>()),
    );
    uid = 'broker';
    await expectLater(
      repository.save(sampleDraft(rentShare: 1)),
      throwsA(isA<DraftFailure>()),
    );
    store.beforeCommit = () {
      uid = 'another-user';
    };
    await expectLater(
      repository.save(sampleDraft()),
      throwsA(isA<DraftFailure>()),
    );
    expect(store.writes, 0);
  });
  test('legacy party dates load without inventing split brokerage', () async {
    final store = DraftStoreFake()
      ..record = {
        'brokerUid': 'broker',
        'status': 'draft',
        'owner': {'name': 'Owner', 'phone': '+919000000001'},
        'tenant': {'name': 'Tenant', 'phone': '+919000000002'},
        'effectiveDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'endDate': Timestamp.fromDate(DateTime(2027, 8, 31)),
        'brokeragePayer': 'split',
        'brokerageFeePaise': 3300000,
      };
    final loaded = await FirebaseAgreementDraftRepository(
      currentUid: () => 'broker',
      persistence: store,
    ).load('legacy');
    expect(loaded.owners.length, 1);
    expect(loaded.tenants.length, 1);
    expect(loaded.startDate, DateTime(2026, 10, 1));
    expect(loaded.endDate, DateTime(2027, 8, 31));
    expect(loaded.brokeragePaise, 0);
    expect(loaded.validationError, isNotNull);
  });
}
