import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../broker/data/private_documents.dart';

class RepairRecord {
  RepairRecord(this.id, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final String id;
  final Map<String, dynamic> data;
  String text(String key, [String fallback = '']) =>
      data[key] is String ? data[key] as String : fallback;
  Map<String, dynamic> object(String key) =>
      data[key] is Map ? Map<String, dynamic>.from(data[key] as Map) : {};
  int get version =>
      data['workflowVersion'] is int ? data['workflowVersion'] as int : 0;
  String get status => text('status', 'open');
  String get role => text('actorRole');
  Map<String, dynamic> get quote => object('quote');
  Map<String, dynamic> get completion => object('completion');
  Map<String, dynamic> get visit => object('visit');
  int get quotePaise => quote['amountPaise'] as int? ?? 0;
  bool get canApprove => data['canApprove'] == true;
  bool get canConfirm => data['canConfirm'] == true;
  String get tenantUpdate {
    final replies = object('tenantConfirmations').values.whereType<Map>();
    if (replies.any((reply) => reply['outcome'] == 'not_working')) {
      return 'Still not working';
    }
    if (replies.any((reply) => reply['outcome'] == 'working')) {
      return 'Working now ✓';
    }
    return 'Awaiting confirmation';
  }

  String get statusLabel => switch (status) {
    'waiting_owner' => 'Waiting for owner approval',
    'approved' => 'Owner approved',
    'assigned' || 'in_progress' => 'Visit scheduled',
    'resolved' => 'Fixed · bill added',
    'closed' => 'Working now ✓',
    'needs_attention' => 'Still needs attention',
    _ => 'Being handled',
  };
}

abstract interface class RepairGateway {
  Stream<RepairRecord> watch(String issueId);
  Future<void> command(String action, Map<String, dynamic> input);
  Future<void> complete(
    Map<String, dynamic> input,
    Map<String, DocumentFile> files,
  );
  Future<DocumentFile> evidence(String issueId, String slot);
}

class FirebaseRepairGateway implements RepairGateway {
  FirebaseRepairGateway({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       storage = storage ?? FirebaseStorage.instance;
  final FirebaseFunctions functions;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  @override
  Stream<RepairRecord> watch(String issueId) {
    late StreamController<RepairRecord> controller;
    StreamSubscription<User?>? identities;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? issues;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profiles;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? agreements;
    String? agreementId;
    String? activeUid;
    var generation = 0;
    Future<void> refresh() async {
      final active = ++generation;
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        controller.addError(StateError('Log in again to open this repair.'));
        return;
      }
      try {
        final result = await functions.httpsCallable('readRepair').call({
          'issueId': issueId,
        });
        if (!controller.isClosed &&
            generation == active &&
            uid == auth.currentUser?.uid) {
          final data = Map<String, dynamic>.from(result.data as Map);
          final linkedAgreement = data['agreementId'] as String?;
          if (linkedAgreement != null && agreementId != linkedAgreement) {
            agreementId = linkedAgreement;
            agreements?.cancel();
            agreements = firestore
                .collection('agreements')
                .doc(linkedAgreement)
                .snapshots()
                .listen(
                  (_) => refresh(),
                  onError: (Object error) {
                    ++generation;
                    if (!controller.isClosed) controller.addError(error);
                  },
                );
          }
          controller.add(RepairRecord(issueId, data));
        }
      } catch (error, stack) {
        if (!controller.isClosed && generation == active) {
          controller.addError(error, stack);
        }
      }
    }

    controller = StreamController<RepairRecord>(
      onListen: () {
        identities = auth.authStateChanges().listen(
          (user) {
            ++generation;
            issues?.cancel();
            profiles?.cancel();
            agreements?.cancel();
            agreementId = null;
            if (user == null || activeUid != null && activeUid != user.uid) {
              controller.addError(
                StateError('Your login changed. Reopen this repair.'),
              );
            }
            activeUid = user?.uid;
            if (user == null) return;
            issues = firestore
                .collection('issues')
                .doc(issueId)
                .snapshots()
                .listen(
                  (_) => refresh(),
                  onError: (Object error) {
                    ++generation;
                    controller.addError(error);
                  },
                );
            profiles = firestore
                .collection('users')
                .doc(user.uid)
                .snapshots()
                .listen(
                  (_) => refresh(),
                  onError: (Object error) {
                    ++generation;
                    controller.addError(error);
                  },
                );
          },
          onError: (Object error) {
            ++generation;
            controller.addError(error);
          },
        );
      },
      onCancel: () async {
        ++generation;
        await identities?.cancel();
        await issues?.cancel();
        await profiles?.cancel();
        await agreements?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> command(String action, Map<String, dynamic> input) async {
    const functionsByAction = {
      'quote': 'recordRepairQuote',
      'approve': 'approveRepairQuote',
      'schedule': 'scheduleRepairVisit',
      'confirm': 'confirmRepairOutcome',
    };
    final name = functionsByAction[action];
    if (name == null) throw ArgumentError('Unknown repair action');
    await functions.httpsCallable(name).call(input);
  }

  @override
  Future<void> complete(
    Map<String, dynamic> input,
    Map<String, DocumentFile> files,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again before uploading.');
    final begun = await functions
        .httpsCallable('beginRepairCompletion')
        .call(input);
    final result = Map<String, dynamic>.from(begun.data as Map);
    if (result['completed'] != true) {
      for (final slot in files.keys) {
        if (auth.currentUser?.uid != uid) {
          throw StateError('Your login changed. Reopen this repair.');
        }
        final file = files[slot]!;
        file.validate();
        await storage
            .ref('${result['path']}/$slot')
            .putData(
              file.bytes,
              SettableMetadata(
                contentType: file.contentType,
                cacheControl: 'private, no-store',
              ),
            );
      }
    }
    if (auth.currentUser?.uid != uid) {
      throw StateError('Your login changed. Reopen this repair.');
    }
    await functions.httpsCallable('completeRepair').call({
      'uploadId': result['uploadId'],
    });
  }

  @override
  Future<DocumentFile> evidence(String issueId, String slot) async {
    final uid = auth.currentUser?.uid;
    final result = await functions.httpsCallable('readRepairEvidence').call({
      'issueId': issueId,
      'slot': slot,
    });
    if (uid == null || uid != auth.currentUser?.uid) {
      throw StateError('Your login changed.');
    }
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['size'] is! int ||
        data['size'] <= 0 ||
        data['size'] > DocumentFile.maximumBytes ||
        data['base64'] is! String ||
        (data['base64'] as String).length >
            ((DocumentFile.maximumBytes + 2) ~/ 3) * 4) {
      throw StateError('This private file is too large or unavailable.');
    }
    final extension = data['contentType'] == 'application/pdf'
        ? 'pdf'
        : data['contentType'] == 'image/png'
        ? 'png'
        : 'jpg';
    final file = DocumentFile(
      name: 'Repair $slot.$extension',
      bytes: base64Decode(data['base64'] as String),
    );
    file.validate();
    if (file.contentType != data['contentType'] ||
        file.bytes.length != data['size']) {
      throw StateError('This private file could not be verified.');
    }
    return file;
  }
}
