import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'agreement_draft.dart';

abstract interface class AgreementDraftRepository {
  String newId();
  Future<AgreementDraft> load(String id);
  Future<void> save(AgreementDraft draft);
}

class DraftFailure implements Exception {
  const DraftFailure(this.message);
  final String message;
}

class DraftMissing extends DraftFailure {
  const DraftMissing() : super('This complete draft has not been saved yet.');
}

abstract interface class DraftPersistence {
  String newId();
  Future<Map<String, dynamic>?> read(String id);
  Future<void> transact(
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  );
}

class FirebaseDraftPersistence implements DraftPersistence {
  FirebaseDraftPersistence(this.firestore);
  final FirebaseFirestore firestore;
  @override
  String newId() => firestore.collection('agreements').doc().id;
  @override
  Future<Map<String, dynamic>?> read(String id) async =>
      (await firestore.collection('agreements').doc(id).get()).data();
  @override
  Future<void> transact(
    String id,
    Map<String, dynamic> Function(Map<String, dynamic>?) update,
  ) async {
    final reference = firestore.collection('agreements').doc(id);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      transaction.set(
        reference,
        update(existing.data()),
        SetOptions(merge: true),
      );
    });
  }
}

class FirebaseAgreementDraftRepository implements AgreementDraftRepository {
  FirebaseAgreementDraftRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DraftPersistence? persistence,
    String? Function()? currentUid,
  }) : currentUid =
           currentUid ??
           (() => (auth ?? FirebaseAuth.instance).currentUser?.uid),
       persistence =
           persistence ??
           FirebaseDraftPersistence(firestore ?? FirebaseFirestore.instance);

  final String? Function() currentUid;
  final DraftPersistence persistence;

  @override
  String newId() => persistence.newId();

  @override
  Future<AgreementDraft> load(String id) async {
    final uid = currentUid();
    if (uid == null) {
      throw const DraftFailure('Log in again to open this draft.');
    }
    final data = await persistence.read(id);
    if (currentUid() != uid) {
      throw const DraftFailure('Your login changed. Log in again.');
    }
    if (data == null) {
      throw const DraftMissing();
    }
    if (data['brokerUid'] != uid || data['status'] != 'draft') {
      throw const DraftFailure(
        'This draft is unavailable or has already been sent.',
      );
    }
    final normalized = Map<String, dynamic>.from(data);
    if (normalized['startDateISO'] == null &&
        data['effectiveDate'] is Timestamp) {
      normalized['startDateISO'] = (data['effectiveDate'] as Timestamp)
          .toDate()
          .toIso8601String();
    }
    if (normalized['endDateISO'] == null && data['endDate'] is Timestamp) {
      normalized['endDateISO'] = (data['endDate'] as Timestamp)
          .toDate()
          .toIso8601String();
    }
    return AgreementDraft.fromMap(id, normalized);
  }

  @override
  Future<void> save(AgreementDraft draft) async {
    if (draft.validationError != null) {
      throw DraftFailure(draft.validationError!);
    }
    final uid = currentUid();
    if (uid == null) {
      throw const DraftFailure('Your session expired. Log in again.');
    }
    await persistence.transact(draft.id, (existing) {
      if (currentUid() != uid) {
        throw const DraftFailure('Your login changed. Log in again.');
      }
      if (existing != null &&
          (existing['brokerUid'] != uid || existing['status'] != 'draft')) {
        throw const DraftFailure(
          'This agreement cannot be edited as a private draft.',
        );
      }
      final participants = existing?['participantUids'];
      if (participants != null &&
          (participants is! List ||
              participants.length != 1 ||
              participants.single != uid)) {
        throw const DraftFailure(
          'This draft already has linked participants. Contact support before editing it.',
        );
      }
      final revision = (existing?['revision'] as num?)?.toInt() ?? 0;
      if (revision != draft.revision) {
        throw const DraftFailure(
          'This draft changed on another device. Reopen it before editing.',
        );
      }
      final renewal = existing?['renewalSourceId'] != null;
      if (renewal &&
          (existing!['effectiveDate'] is! Timestamp ||
              draft.renewalSourceId != existing['renewalSourceId'] ||
              draft.propertyId != existing['propertyId'] ||
              draft.startDate?.toIso8601String() != existing['startDateISO'])) {
        throw const DraftFailure(
          'A renewal must keep its original home and next-day start. Reopen the current draft.',
        );
      }
      return {
        ...draft.toMap(),
        'brokerUid': uid,
        'participantUids': [uid],
        'status': 'draft',
        'revision': revision + 1,
        'effectiveDate': renewal
            ? existing!['effectiveDate']
            : Timestamp.fromDate(draft.startDate!),
        'endDate': Timestamp.fromDate(draft.endDate!),
        if (existing == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
    });
  }
}
