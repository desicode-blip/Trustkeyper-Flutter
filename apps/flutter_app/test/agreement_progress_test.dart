import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft_repository.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_progress_repository.dart';

import 'agreement_draft_test.dart' show sampleDraft;

class MemoryProgressPersistence implements ProgressPersistence {
  final records = <String, Map<String, dynamic>>{};
  String? lastUid;
  void Function()? beforeWrite;
  bool failWrite = false;

  @override
  Stream<List<Map<String, dynamic>>> watch(String uid) => Stream.value(
    records.entries.map((entry) => {...entry.value, 'id': entry.key}).toList(),
  );

  @override
  Future<Map<String, dynamic>?> read(String uid, String id) async {
    lastUid = uid;
    return records[id];
  }

  @override
  Future<int> save(
    String uid,
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  ) async {
    lastUid = uid;
    beforeWrite?.call();
    if (failWrite) throw StateError('Offline');
    final values = update(records[id]);
    records[id] = {...values, 'brokerUid': uid};
    return values['version'] as int;
  }

  @override
  Future<void> remove(String uid, String id, int version) async {
    if (records[id] == null) return;
    if (records[id]?['version'] != version) {
      throw const DraftFailure('Version changed');
    }
    records.remove(id);
  }
}

AgreementProgress checkpoint({
  int version = 0,
  String stage = 'ownerPapers',
  int person = 0,
}) => AgreementProgress(
  draft: sampleDraft(),
  stage: stage,
  person: person,
  version: version,
  inputs: const {'rent': '', 'payer': 'Both'},
);

void main() {
  late MemoryProgressPersistence persistence;
  late FirebaseAgreementProgressRepository repository;
  String? uid;
  setUp(() {
    uid = 'broker';
    persistence = MemoryProgressPersistence();
    repository = FirebaseAgreementProgressRepository(
      persistence: persistence,
      currentUid: () => uid,
    );
  });

  test(
    'checkpoint restores the stage, party, identity and raw incomplete inputs',
    () async {
      expect(await repository.save(checkpoint()), 1);
      final loaded = await repository.load('test-draft');
      expect(loaded.stage, 'ownerPapers');
      expect(loaded.draft.owners.first.id, 'owner-1');
      expect(loaded.inputs['rent'], '');
      expect(loaded.version, 1);
      expect(persistence.lastUid, 'broker');
      expect((await repository.watch().first).single.version, 1);
      expect(await repository.save(checkpoint(version: 1)), 2);
      await repository.remove('test-draft', 2);
      expect(persistence.records, isEmpty);
    },
  );

  test('stale saves and deletion cannot overwrite another device', () async {
    await repository.save(checkpoint());
    await expectLater(
      repository.save(checkpoint()),
      throwsA(isA<DraftFailure>()),
    );
    await expectLater(
      repository.remove('test-draft', 0),
      throwsA(isA<DraftFailure>()),
    );
    expect(persistence.records['test-draft']?['version'], 1);
  });

  test(
    'changed sessions cannot save or read another broker progress',
    () async {
      persistence.beforeWrite = () => uid = 'another-broker';
      await expectLater(
        repository.save(checkpoint()),
        throwsA(isA<DraftFailure>()),
      );
      expect(persistence.records, isEmpty);
      persistence.beforeWrite = null;
      uid = 'broker';
      await repository.save(checkpoint());
      uid = 'another-broker';
      await expectLater(
        repository.load('test-draft'),
        throwsA(isA<DraftFailure>()),
      );
      await expectLater(repository.watch().first, throwsA(isA<DraftFailure>()));
    },
  );

  test(
    'missing sessions, unsafe ids and malformed stages produce no write',
    () async {
      uid = null;
      await expectLater(
        repository.save(checkpoint()),
        throwsA(isA<DraftFailure>()),
      );
      uid = 'broker';
      await expectLater(
        repository.save(checkpoint(stage: 'signed')),
        throwsA(isA<DraftFailure>()),
      );
      await expectLater(
        repository.save(checkpoint(person: 99)),
        throwsA(isA<DraftFailure>()),
      );
      await expectLater(
        repository.load('../another'),
        throwsA(isA<DraftFailure>()),
      );
      expect(persistence.records, isEmpty);
    },
  );

  test(
    'failure never creates saved progress or clears previous values',
    () async {
      await repository.save(checkpoint());
      persistence.failWrite = true;
      await expectLater(
        repository.save(checkpoint(version: 1)),
        throwsStateError,
      );
      expect(persistence.records['test-draft']?['version'], 1);
      expect((await repository.load('test-draft')).inputs['rent'], '');
    },
  );
}
