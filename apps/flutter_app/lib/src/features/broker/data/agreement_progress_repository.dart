import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'agreement_draft.dart';
import 'agreement_draft_repository.dart';

const agreementProgressStages = [
  'ownerCount',
  'owner',
  'ownerPapers',
  'tenantCount',
  'tenant',
  'tenantPapers',
  'money',
  'dates',
  'periods',
  'brokerage',
  'review',
];

class AgreementProgress {
  AgreementProgress({
    required this.draft,
    required this.stage,
    required this.person,
    this.version = 0,
    this.updatedAt,
    Map<String, dynamic> inputs = const {},
  }) : inputs = Map.unmodifiable(inputs);

  final AgreementDraft draft;
  final String stage;
  final int person;
  final int version;
  final DateTime? updatedAt;
  final Map<String, dynamic> inputs;

  String? get validationError {
    if (draft.owners.isEmpty || draft.owners.length > 20) {
      return 'Number of owners: choose between 1 and 20 owners.';
    }
    if (draft.tenants.isEmpty || draft.tenants.length > 20) {
      return 'Number of tenants: choose between 1 and 20 tenants.';
    }
    if (!RegExp(r'^[\w-]{1,128}$').hasMatch(draft.id) ||
        !agreementProgressStages.contains(stage) ||
        version < 0 ||
        draft.revision < 0 ||
        person < 0 ||
        person >=
            (stage.startsWith('tenant') ? draft.tenants : draft.owners)
                .length) {
      return 'Could not identify the saved step. Reopen this draft from Agreements; your saved details are unchanged.';
    }
    final ids = [
      ...draft.owners,
      ...draft.tenants,
    ].map((party) => party.id).toList();
    if (ids.toSet().length != ids.length ||
        ids.any((id) => !RegExp(r'^[\w-]{1,128}$').hasMatch(id))) {
      return 'Every person needs a separate document identity.';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'draft': {...draft.toMap(), 'revision': draft.revision},
    'stage': stage,
    'person': person,
    'inputs': inputs,
    'version': version,
  };

  factory AgreementProgress.fromMap(String id, Map<String, dynamic> data) =>
      AgreementProgress(
        draft: AgreementDraft.fromMap(
          id,
          Map<String, dynamic>.from(data['draft'] as Map),
        ),
        stage: data['stage'] as String,
        person: data['person'] as int,
        version: data['version'] as int,
        updatedAt: data['updatedAt'] is Timestamp
            ? (data['updatedAt'] as Timestamp).toDate()
            : null,
        inputs: Map<String, dynamic>.from(data['inputs'] as Map? ?? {}),
      );
}

abstract interface class AgreementProgressRepository {
  Stream<List<AgreementProgress>> watch();
  Future<AgreementProgress> load(String id);
  Future<int> save(AgreementProgress progress);
  Future<void> remove(String id, int version);
}

abstract interface class ProgressPersistence {
  Stream<List<Map<String, dynamic>>> watch(String uid);
  Future<Map<String, dynamic>?> read(String uid, String id);
  Future<int> save(
    String uid,
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  );
  Future<void> remove(String uid, String id, int version);
}

class FirebaseProgressPersistence implements ProgressPersistence {
  FirebaseProgressPersistence(this.firestore);
  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      firestore.collection('users').doc(uid).collection('draftProgress');

  @override
  Stream<List<Map<String, dynamic>>> watch(String uid) => _collection(uid)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => {...document.data(), 'id': document.id})
            .toList(),
      );

  @override
  Future<Map<String, dynamic>?> read(String uid, String id) async =>
      (await _collection(
        uid,
      ).doc(id).get(const GetOptions(source: Source.server))).data();

  @override
  Future<int> save(
    String uid,
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  ) => firestore.runTransaction((transaction) async {
    final reference = _collection(uid).doc(id);
    final previous = await transaction.get(reference);
    final values = update(previous.data());
    transaction.set(reference, {
      ...values,
      'brokerUid': uid,
      'createdAt':
          previous.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return values['version'] as int;
  });

  @override
  Future<void> remove(String uid, String id, int version) =>
      firestore.runTransaction((transaction) async {
        final reference = _collection(uid).doc(id);
        final previous = await transaction.get(reference);
        if (!previous.exists) return;
        if (previous.data()?['version'] != version) {
          throw const DraftFailure(
            'Progress changed on another device. Reopen it before deleting.',
          );
        }
        transaction.delete(reference);
      });
}

class FirebaseAgreementProgressRepository
    implements AgreementProgressRepository {
  FirebaseAgreementProgressRepository({
    ProgressPersistence? persistence,
    String? Function()? currentUid,
  }) : persistence =
           persistence ??
           FirebaseProgressPersistence(FirebaseFirestore.instance),
       currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final ProgressPersistence persistence;
  final String? Function() currentUid;

  String _uid() {
    final uid = currentUid();
    if (uid == null) {
      throw const DraftFailure('Log in again to save draft progress.');
    }
    return uid;
  }

  void _session(String uid) {
    if (currentUid() != uid) {
      throw const DraftFailure('Your login changed. Reopen the draft.');
    }
  }

  AgreementProgress _decode(String id, Map<String, dynamic> data, String uid) {
    _session(uid);
    if (data['brokerUid'] != uid) {
      throw const DraftFailure('This progress belongs to another broker.');
    }
    try {
      final progress = AgreementProgress.fromMap(id, data);
      if (progress.validationError != null) throw const FormatException();
      return progress;
    } catch (_) {
      throw const DraftFailure(
        'Could not read this draft progress. Contact support.',
      );
    }
  }

  @override
  Stream<List<AgreementProgress>> watch() {
    final uid = _uid();
    return persistence.watch(uid).map((records) {
      _session(uid);
      return records
          .map((data) => _decode(data['id'] as String, data, uid))
          .toList();
    });
  }

  @override
  Future<AgreementProgress> load(String id) async {
    if (!RegExp(r'^[\w-]{1,128}$').hasMatch(id)) {
      throw const DraftFailure('Invalid draft reference.');
    }
    final uid = _uid();
    final data = await persistence.read(uid, id);
    _session(uid);
    if (data == null) {
      throw const DraftProgressMissing();
    }
    return _decode(id, data, uid);
  }

  @override
  Future<int> save(AgreementProgress progress) async {
    if (progress.validationError != null) {
      throw DraftFailure(progress.validationError!);
    }
    final uid = _uid();
    final version = await persistence.save(uid, progress.draft.id, (previous) {
      _session(uid);
      if (previous != null && previous['brokerUid'] != uid) {
        throw const DraftFailure('This progress belongs to another broker.');
      }
      if ((previous?['version'] ?? 0) != progress.version) {
        throw const DraftFailure(
          'Progress changed on another device. Reopen it before editing.',
        );
      }
      return {...progress.toMap(), 'version': progress.version + 1};
    });
    _session(uid);
    return version;
  }

  @override
  Future<void> remove(String id, int version) async {
    if (!RegExp(r'^[\w-]{1,128}$').hasMatch(id) || version < 1) {
      throw const DraftFailure('Invalid draft progress reference.');
    }
    final uid = _uid();
    await persistence.remove(uid, id, version);
    _session(uid);
  }
}

class DraftProgressMissing extends DraftFailure {
  const DraftProgressMissing() : super('This draft progress is unavailable.');
}
