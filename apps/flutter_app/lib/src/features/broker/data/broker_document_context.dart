import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../document_requests/data/document_request_repository.dart';
import 'agreement_draft.dart';
import 'agreement_draft_repository.dart';
import 'agreement_progress_repository.dart';
import 'private_documents.dart';

class BrokerDocumentContext {
  const BrokerDocumentContext(this.draft, this.request, this.progress);
  final AgreementDraft draft;
  final DocumentRequestInfo request;
  final AgreementProgress? progress;
  String get resumePath => Uri(
    path: '/broker/${progress == null ? 'draft' : 'progress'}/${draft.id}',
    queryParameters: {
      'role': request.role,
      'partyId': request.data['partyId'] as String,
    },
  ).toString();
}

BrokerDocumentContext resolveBrokerDocumentContext(
  DocumentRequestInfo request, {
  AgreementProgress? progress,
  AgreementDraft? completed,
}) {
  final revision = request.data['revision'] as int;
  AgreementDraft? draft;
  AgreementProgress? activeProgress;
  if (completed?.revision == revision) {
    draft = completed;
  } else if (progress != null &&
      progress.draft.revision + 1 == revision &&
      (completed == null || completed.revision == progress.draft.revision)) {
    draft = AgreementDraft.fromMap(progress.draft.id, {
      ...progress.draft.toMap(),
      'revision': revision,
    });
    activeProgress = progress;
  }
  if (draft == null ||
      draft.id != request.data['draftId'] ||
      request.status == 'revoked') {
    throw const DocumentFailure(
      'This update is from an older or deleted draft. Open your current agreement instead.',
    );
  }
  final parties = request.role == 'owner'
      ? draft.owners
      : request.role == 'tenant'
      ? draft.tenants
      : <AgreementParty>[];
  final matches = parties.where(
    (party) =>
        party.id == request.data['partyId'] &&
        party.name.trim() == request.name.trim() &&
        party.phone == request.phone &&
        party.email.trim().toLowerCase() ==
            (request.data['email'] as String? ?? '').trim().toLowerCase(),
  );
  if (matches.length != 1) {
    throw const DocumentFailure(
      'The person on this agreement changed. Open the current owner or tenant details.',
    );
  }
  if (completed != null && progress?.draft.revision == completed.revision) {
    final pending = request.role == 'owner'
        ? progress!.draft.owners
        : progress!.draft.tenants;
    final person = matches.single;
    if (!pending.any(
      (party) =>
          party.id == person.id &&
          party.name.trim() == person.name.trim() &&
          party.phone == person.phone &&
          party.email.trim().toLowerCase() == person.email.trim().toLowerCase(),
    )) {
      throw const DocumentFailure(
        'The person was edited in an unfinished draft. Reopen the current saved agreement.',
      );
    }
  }
  return BrokerDocumentContext(draft, request, activeProgress);
}

Future<AgreementDraft?> loadBrokerCompletedDocumentDraft(String id) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    throw const DocumentFailure('Log in again to see your documents.');
  }
  final snapshot = await FirebaseFirestore.instance
      .doc('agreements/$id')
      .get(const GetOptions(source: Source.server));
  if (FirebaseAuth.instance.currentUser?.uid != uid) {
    throw const DocumentFailure('Your login changed.');
  }
  final data = snapshot.data();
  if (data == null) return null;
  if (data['brokerUid'] != uid) {
    throw const DocumentFailure('This agreement belongs to another broker.');
  }
  if (![
    'draft',
    'review_requested',
    'request_received',
    'reviewed',
  ].contains(data['status'])) {
    throw const DocumentFailure(
      'This agreement has moved past document collection. Open the current agreement from Agreements.',
    );
  }
  return AgreementDraft.fromMap(id, data);
}

Future<BrokerDocumentContext> loadBrokerDocumentContext({
  required DocumentRequestInfo request,
  required AgreementProgressRepository progressRepository,
  required Future<AgreementDraft?> Function(String) loadCompleted,
}) async {
  final id = request.data['draftId'] as String;
  final completed = await loadCompleted(id);
  AgreementProgress? progress;
  try {
    progress = await progressRepository.load(id);
  } on DraftProgressMissing {
    if (completed == null) {
      throw const DraftFailure('This unfinished draft was deleted.');
    }
  }
  return resolveBrokerDocumentContext(
    request,
    progress: progress,
    completed: completed,
  );
}
