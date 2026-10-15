import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminRecord {
  const AdminRecord({required this.id, required this.path, required this.data});

  final String id;
  final String path;
  final Map<String, dynamic> data;

  String text(List<String> keys, {String fallback = '—'}) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  int integer(List<String> keys, {int fallback = 0}) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.round();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  bool boolean(String key, {bool fallback = false}) {
    final value = data[key];
    return value is bool ? value : fallback;
  }

  DateTime? date(List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  List<String> strings(String key) =>
      (data[key] as List?)?.whereType<String>().toList(growable: false) ??
      const [];

  bool hasRole(String role) => strings('roles').contains(role);

  String get displayName => text(const [
    'displayName',
    'name',
    'fullName',
    'ownerName',
    'tenantName',
  ], fallback: 'Unnamed person');

  String get status => text(const [
    'status',
    'approvalStatus',
    'reviewStatus',
  ], fallback: 'pending').toLowerCase();

  factory AdminRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => AdminRecord(
    id: document.id,
    path: document.reference.path,
    data: Map<String, dynamic>.from(
      document.data() ?? const <String, dynamic>{},
    ),
  );
}

class AdminData {
  const AdminData({
    this.users = const [],
    this.properties = const [],
    this.agreements = const [],
    this.documents = const [],
    this.payments = const [],
    this.payouts = const [],
    this.issues = const [],
    this.photoChecks = const [],
    this.moveOuts = const [],
    this.settings = const {},
  });

  final List<AdminRecord> users;
  final List<AdminRecord> properties;
  final List<AdminRecord> agreements;
  final List<AdminRecord> documents;
  final List<AdminRecord> payments;
  List<AdminRecord> get livePayments => payments
      .where((payment) => payment.text(const ['mode'], fallback: '') != 'test')
      .toList(growable: false);
  final List<AdminRecord> payouts;
  final List<AdminRecord> issues;
  final List<AdminRecord> photoChecks;
  final List<AdminRecord> moveOuts;
  final Map<String, dynamic> settings;

  int get waitingBrokers => users
      .where(
        (user) =>
            user.hasRole('broker') &&
            user.status != 'approved' &&
            !user.boolean('paused'),
      )
      .length;

  int get agreementsNeedingAction => agreements
      .where(
        (agreement) => !const {
          'signed',
          'completed',
          'cancelled',
        }.contains(agreement.status),
      )
      .length;

  int get documentsWaiting => documents
      .where(
        (document) =>
            const {'pending', 'waiting', 'uploaded'}.contains(document.status),
      )
      .length;

  int get lateRent => livePayments
      .where(
        (payment) =>
            const {'late', 'overdue', 'failed'}.contains(payment.status),
      )
      .length;

  int get failedPayouts =>
      payouts.where((payout) => payout.status == 'failed').length;

  int get openRepairs => issues
      .where(
        (issue) =>
            !const {'closed', 'resolved', 'cancelled'}.contains(issue.status),
      )
      .length;

  int get moveOutsNeedingAction => moveOuts
      .where(
        (moveOut) => !const {'completed', 'cancelled'}.contains(moveOut.status),
      )
      .length;

  int get notificationCount =>
      waitingBrokers +
      agreementsNeedingAction +
      documentsWaiting +
      failedPayouts +
      openRepairs +
      moveOutsNeedingAction;

  AdminData copyWith({
    List<AdminRecord>? users,
    List<AdminRecord>? properties,
    List<AdminRecord>? agreements,
    List<AdminRecord>? documents,
    List<AdminRecord>? payments,
    List<AdminRecord>? payouts,
    List<AdminRecord>? issues,
    List<AdminRecord>? photoChecks,
    List<AdminRecord>? moveOuts,
    Map<String, dynamic>? settings,
  }) => AdminData(
    users: users ?? this.users,
    properties: properties ?? this.properties,
    agreements: agreements ?? this.agreements,
    documents: documents ?? this.documents,
    payments: payments ?? this.payments,
    payouts: payouts ?? this.payouts,
    issues: issues ?? this.issues,
    photoChecks: photoChecks ?? this.photoChecks,
    moveOuts: moveOuts ?? this.moveOuts,
    settings: settings ?? this.settings,
  );
}

abstract interface class AdminRepository {
  Stream<AdminData> watchData();

  Future<void> approveBroker(String userId);

  Future<void> rejectBroker(String userId, String reason, String note);

  Future<void> setUserPaused(String userId, bool paused);

  Future<void> setAgreementStep(
    String agreementId,
    String step, {
    required int revision,
  });

  Future<void> returnAgreementDraft(
    String agreementId,
    String reason, {
    required int revision,
  });

  Future<void> reviewDocument(
    String documentId,
    String status, {
    String? reason,
  });

  Future<void> recordRentFollowUp(String paymentId, String action);

  Future<void> requestPayoutAction(String payoutId, String action);

  Future<void> updateRepair(String issueId, String status, {int? billPaise});

  Future<void> reviewPhoto(String path, String status);

  Future<void> createRepairFromPhoto(AdminRecord photo);

  Future<void> updateMoveOut(String moveOutId, String status);

  Future<void> saveSettings(Map<String, dynamic> settings);
}

class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Stream<AdminData> watchData() {
    late StreamController<AdminData> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    var current = const AdminData();

    void emit() {
      if (!controller.isClosed) controller.add(current);
    }

    void listenCollection(
      String collection,
      void Function(List<AdminRecord>) assign,
    ) {
      subscriptions.add(
        _firestore.collection(collection).snapshots().listen((snapshot) {
          final records =
              snapshot.docs
                  .map(AdminRecord.fromDocument)
                  .toList(growable: false)
                ..sort(_newestFirst);
          assign(records);
          emit();
        }, onError: controller.addError),
      );
    }

    controller = StreamController<AdminData>(
      onListen: () {
        emit();
        listenCollection('users', (records) {
          current = current.copyWith(users: records);
        });
        listenCollection('properties', (records) {
          current = current.copyWith(properties: records);
        });
        listenCollection('agreements', (records) {
          current = current.copyWith(agreements: records);
        });
        listenCollection('documentRequests', (records) {
          current = current.copyWith(documents: records);
        });
        listenCollection('payments', (records) {
          current = current.copyWith(payments: records);
        });
        listenCollection('payouts', (records) {
          current = current.copyWith(payouts: records);
        });
        listenCollection('issues', (records) {
          current = current.copyWith(issues: records);
        });
        listenCollection('moveOuts', (records) {
          current = current.copyWith(moveOuts: records);
        });
        subscriptions.add(
          _firestore.collectionGroup('photoChecks').snapshots().listen((
            snapshot,
          ) {
            final records =
                snapshot.docs
                    .map(AdminRecord.fromDocument)
                    .toList(growable: false)
                  ..sort(_newestFirst);
            current = current.copyWith(photoChecks: records);
            emit();
          }, onError: controller.addError),
        );
        subscriptions.add(
          _firestore
              .collection('adminSettings')
              .doc('operations')
              .snapshots()
              .listen((snapshot) {
                current = current.copyWith(
                  settings: Map<String, dynamic>.from(
                    snapshot.data() ?? const <String, dynamic>{},
                  ),
                );
                emit();
              }, onError: controller.addError),
        );
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> approveBroker(String userId) => _updateWithAudit(
    path: 'users/$userId',
    action: 'broker.approved',
    changes: {
      'approvalStatus': 'approved',
      'paused': false,
      'approvedAt': FieldValue.serverTimestamp(),
    },
  );

  @override
  Future<void> rejectBroker(String userId, String reason, String note) async {
    await _updateWithAudit(
      path: 'users/$userId',
      action: 'broker.rejected',
      changes: {
        'approvalStatus': 'rejected',
        'adminNotes': note.trim(),
        'rejectionReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
      },
      metadata: {'reason': reason},
    );
    await _queueNotification(
      userId: userId,
      template: 'broker_rejected',
      payload: {'reason': reason, 'note': note.trim()},
    );
  }

  @override
  Future<void> setUserPaused(String userId, bool paused) => _updateWithAudit(
    path: 'users/$userId',
    action: paused ? 'user.paused' : 'user.resumed',
    changes: {'paused': paused},
  );

  @override
  Future<void> setAgreementStep(
    String agreementId,
    String step, {
    required int revision,
  }) => _recordAgreementReview(agreementId, step, revision: revision);

  @override
  Future<void> returnAgreementDraft(
    String agreementId,
    String reason, {
    required int revision,
  }) => _recordAgreementReview(
    agreementId,
    'return_to_broker',
    revision: revision,
    reason: reason,
  );

  Future<void> _recordAgreementReview(
    String agreementId,
    String step, {
    required int revision,
    String? reason,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again.');
    await FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).httpsCallable('recordAgreementReview').call<void>({
      'agreementId': agreementId,
      'revision': revision,
      'step': step,
      'reason': ?reason,
    });
    if (_auth.currentUser?.uid != uid) {
      throw StateError(
        'Your account changed. Reopen the record to check its status.',
      );
    }
  }

  @override
  Future<void> reviewDocument(
    String documentId,
    String status, {
    String? reason,
  }) async {
    await _updateWithAudit(
      path: 'documentRequests/$documentId',
      action: 'document.$status',
      changes: {
        'status': status,
        'reviewReason': reason,
        'reviewedAt': FieldValue.serverTimestamp(),
      },
      metadata: {'reason': reason},
    );
    if (status == 'asked_again') {
      final document = await _firestore
          .collection('documentRequests')
          .doc(documentId)
          .get();
      final userId = document.data()?['userId']?.toString();
      if (userId != null && userId.isNotEmpty) {
        await _queueNotification(
          userId: userId,
          template: 'document_upload_again',
          payload: {'documentId': documentId, 'reason': reason},
        );
      }
    }
  }

  @override
  Future<void> recordRentFollowUp(String paymentId, String action) =>
      _updateWithAudit(
        path: 'payments/$paymentId',
        action: 'rent.follow_up',
        changes: {
          'lastFollowUp': action,
          'lastFollowUpAt': FieldValue.serverTimestamp(),
          'followUpCount': FieldValue.increment(1),
        },
        metadata: {'followUp': action},
      );

  @override
  Future<void> requestPayoutAction(String payoutId, String action) =>
      _updateWithAudit(
        path: 'payouts/$payoutId',
        action: 'payout.action_requested',
        changes: {
          'adminActionRequested': action,
          'adminActionRequestedAt': FieldValue.serverTimestamp(),
        },
        metadata: {
          'requestedAction': action,
          'note': 'No money movement is performed by the admin client.',
        },
      );

  @override
  Future<void> updateRepair(
    String issueId,
    String status, {
    int? billPaise,
  }) async {
    throw StateError(
      'Open the repair to record its quote, owner approval, visit and evidence.',
    );
  }

  @override
  Future<void> reviewPhoto(String path, String status) async {
    throw StateError(
      'Open the private photo and use its reviewed, version-bound action.',
    );
  }

  @override
  Future<void> createRepairFromPhoto(AdminRecord photo) async {
    await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('createInspectionRepair')
        .call<void>({'photoPath': photo.path});
  }

  @override
  Future<void> updateMoveOut(String moveOutId, String status) async {
    throw StateError(
      'Move-out completion requires the authenticated inspection, key and settlement workflow. A status button cannot complete it.',
    );
  }

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) => _updateWithAudit(
    path: 'adminSettings/operations',
    action: 'settings.updated',
    changes: {...settings, 'updatedAt': FieldValue.serverTimestamp()},
    merge: true,
  );

  Future<void> _updateWithAudit({
    required String path,
    required String action,
    required Map<String, dynamic> changes,
    Map<String, dynamic>? metadata,
    bool merge = false,
  }) async {
    final target = _firestore.doc(path);
    final audit = _firestore.collection('adminAuditLogs').doc();
    final batch = _firestore.batch();
    final values = {...changes, 'updatedAt': FieldValue.serverTimestamp()};
    if (merge) {
      batch.set(target, values, SetOptions(merge: true));
    } else {
      batch.update(target, values);
    }
    batch.set(audit, _auditData(action, path, metadata));
    await batch.commit();
  }

  Future<void> _queueNotification({
    required String userId,
    required String template,
    required Map<String, dynamic> payload,
  }) async {
    await _firestore.collection('notificationRequests').add({
      'userId': userId,
      'channels': ['whatsapp', 'email'],
      'template': template,
      'payload': payload,
      'status': 'queued',
      'requestedBy': _auth.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> _auditData(
    String action,
    String targetPath,
    Map<String, dynamic>? metadata,
  ) => {
    'action': action,
    'targetPath': targetPath,
    'adminUid': _auth.currentUser?.uid,
    'adminEmail': _auth.currentUser?.email,
    'metadata': metadata ?? const <String, dynamic>{},
    'createdAt': FieldValue.serverTimestamp(),
  };
}

int _newestFirst(AdminRecord left, AdminRecord right) {
  final leftDate = left.date(const ['updatedAt', 'createdAt', 'uploadedAt']);
  final rightDate = right.date(const ['updatedAt', 'createdAt', 'uploadedAt']);
  return (rightDate ?? DateTime(1970)).compareTo(leftDate ?? DateTime(1970));
}
