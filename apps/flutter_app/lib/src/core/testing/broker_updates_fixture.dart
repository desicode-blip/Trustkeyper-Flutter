import 'dart:async';
import '../../features/broker/data/agreement_draft.dart';
import '../../features/broker/data/agreement_draft_repository.dart';
import '../../features/broker/data/agreement_progress_repository.dart';
import '../../features/broker/data/broker_updates_repository.dart';
import '../../features/document_requests/data/document_request_repository.dart';
import '../../features/broker/data/private_documents.dart';

class OfflineBrokerProgress implements AgreementProgressRepository {
  OfflineBrokerProgress() {
    saved = AgreementProgress(
      draft: draft,
      stage: 'tenantPapers',
      person: 0,
      version: 1,
    );
  }
  static final draft = AgreementDraft(
    id: 'offline-saved-flow',
    propertyAddress: 'OFFLINE TEST · Phoenix Towers 402',
    owners: const [
      AgreementParty(
        id: 'owner-1',
        name: 'TEST Rajesh',
        phone: '+919000000001',
      ),
    ],
    tenants: const [
      AgreementParty(
        id: 'tenant-1',
        name: 'TEST Priya',
        phone: '+919000000002',
      ),
    ],
    monthlyRentPaise: 2200000,
    maintenancePaise: 0,
    depositPaise: 4400000,
    startDate: DateTime(2026, 10, 1),
    endDate: DateTime(2027, 8, 31),
    ownerBrokeragePaise: 0,
    tenantBrokeragePaise: 0,
  );
  AgreementProgress? saved;
  final changes = StreamController<List<AgreementProgress>>.broadcast();
  @override
  Stream<List<AgreementProgress>> watch() async* {
    yield saved == null ? [] : [saved!];
    yield* changes.stream;
  }

  @override
  Future<AgreementProgress> load(String id) async {
    if (saved?.draft.id != id) throw const DraftProgressMissing();
    return saved!;
  }

  @override
  Future<int> save(AgreementProgress progress) async {
    if (progress.version != (saved?.version ?? 0)) {
      throw const DraftFailure('Version changed.');
    }
    saved = AgreementProgress(
      draft: progress.draft,
      stage: progress.stage,
      person: progress.person,
      version: progress.version + 1,
      inputs: progress.inputs,
    );
    changes.add([saved!]);
    return saved!.version;
  }

  @override
  Future<void> remove(String id, int version) async {
    if (saved?.draft.id != id || saved?.version != version) {
      throw const DraftFailure('Version changed.');
    }
    saved = null;
    changes.add([]);
  }
}

class OfflineBrokerUpdates implements BrokerUpdatesRepository {
  final items = [
    BrokerUpdate('a' * 64, {
      'title': 'TEST Rajesh added documents',
      'address': 'Phoenix Towers 402',
      'requestId': 'c' * 64,
      'atMs': DateTime(2026, 10, 11, 18, 40).millisecondsSinceEpoch,
      'readAt': null,
      'brokerUid': 'offline-broker',
      'role': 'owner',
      'partyId': 'owner-1',
    }),
    BrokerUpdate('b' * 64, {
      'title': 'TEST Priya added her PAN card',
      'address': 'Phoenix Towers 402',
      'requestId': 'd' * 64,
      'atMs': DateTime(2026, 10, 10, 16, 20).millisecondsSinceEpoch,
      'readAt': 1,
      'brokerUid': 'offline-broker',
      'role': 'tenant',
      'partyId': 'tenant-1',
    }),
  ];
  final changes = StreamController<List<BrokerUpdate>>.broadcast();
  bool failRead = false;
  String? opened;
  @override
  Stream<List<BrokerUpdate>> watch() async* {
    yield List.of(items);
    yield* changes.stream;
  }

  @override
  Future<void> markRead(BrokerUpdate update) async {
    if (failRead) throw const DocumentFailure('Offline retry fixture.');
    final index = items.indexWhere((value) => value.id == update.id);
    items[index] = BrokerUpdate(update.id, {...update.data, 'readAt': 1});
    changes.add(List.of(items));
  }

  @override
  Future<DocumentRequestInfo> request(String id) async =>
      throw const DocumentFailure(
        'Offline UI Test: no live document is accessed.',
      );
}
