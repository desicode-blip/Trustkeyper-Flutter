import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../broker/data/agreement_draft.dart';
import '../../broker/data/private_documents.dart';
import '../../document_requests/data/recipient_document_gateway.dart';
import '../../agreement_copies/agreement_copies.dart';

class ApprovalLink {
  ApprovalLink(Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get id => data['invitationId'] as String;
  String get partyId => data['partyId'] as String;
  String get name => data['partyName'] as String;
  String get role => data['role'] as String;
  String get phone => data['phone'] as String;
  String get status => data['status'] as String;
  bool get expired =>
      (data['expiresAtMs'] as num).toInt() <=
      DateTime.now().millisecondsSinceEpoch;
  Uri get url => Uri(
    scheme: 'https',
    host: 'trustkeyper.web.app',
    path: '/',
    fragment:
        '/agreement/reply?token=${Uri.encodeComponent(data['token'] as String)}',
  );
}

class ApprovalInfo {
  ApprovalInfo(Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  bool get verified => data['verified'] == true;
  String get status => data['status'] as String? ?? 'not_opened';
  String get role => data['role'] as String;
  String get name => data['partyName'] as String? ?? '';
  String get phoneMasked => data['phoneMasked'] as String;
  String get broker => data['brokerName'] as String;
  int get revision => (data['revision'] as num).toInt();
  String get digest => data['digest'] as String;
  List<Map<String, dynamic>> get people => (data['people'] as List? ?? [])
      .map((person) => Map<String, dynamic>.from(person as Map))
      .toList();
  List<String> get changed =>
      (data['changedFields'] as List? ?? []).cast<String>();
  AgreementDraft get draft {
    if (!verified || data['demoOnly'] != true || data['signable'] != false) {
      throw const DocumentFailure('This approval version is unavailable.');
    }
    final draft = AgreementDraft.fromMap(data['agreementId'] as String, {
      ...Map<String, dynamic>.from(data['snapshot'] as Map),
      'revision': revision,
    });
    if (draft.validationError != null) {
      throw const DocumentFailure(
        'This agreement could not be read. Ask the broker to check it.',
      );
    }
    return draft;
  }
}

abstract interface class AgreementApprovals {
  Stream<List<Map<String, dynamic>>> watch(String agreementId, int revision);
  Future<List<ApprovalLink>> prepare(
    String agreementId,
    int revision, {
    String? refreshPartyId,
  });
}

class FirebaseAgreementApprovals implements AgreementApprovals {
  @override
  Stream<List<Map<String, dynamic>>> watch(String agreementId, int revision) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.error(const DocumentFailure('Log in again.'));
    }
    return FirebaseFirestore.instance
        .collection('agreementInvitations')
        .where('brokerUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          if (FirebaseAuth.instance.currentUser?.uid != uid) {
            throw const DocumentFailure(
              'Your login changed. Reopen the agreement.',
            );
          }
          return snapshot.docs
              .map((doc) => doc.data())
              .where(
                (data) =>
                    data['agreementId'] == agreementId &&
                    data['revision'] == revision,
              )
              .toList();
        });
  }

  @override
  Future<List<ApprovalLink>> prepare(
    String agreementId,
    int revision, {
    String? refreshPartyId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Log in again.');
    final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('prepareAgreementApproval')
        .call({
          'agreementId': agreementId,
          'revision': revision,
          'operationId': FirebaseFirestore.instance
              .collection('agreementInvitations')
              .doc()
              .id,
          'refreshPartyId': ?refreshPartyId,
        });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw const DocumentFailure('Your login changed. Reopen the agreement.');
    }
    return ((result.data as Map)['links'] as List)
        .map((item) => ApprovalLink(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}

abstract interface class AgreementRecipientGateway {
  Future<AgreementCopyFile> readCopy(String agreementId, int revision);
  Future<ApprovalInfo> read(String token);
  Future<bool> requestOtp(String phone);
  Future<void> verifyOtp(String code);
  Future<void> signOut();
  String operationId();
  Future<ApprovalInfo> reply(
    String token,
    ApprovalInfo info,
    Map<String, dynamic> reply,
  );
}

class FirebaseAgreementRecipientGateway implements AgreementRecipientGateway {
  FirebaseAgreementRecipientGateway(this.phone);
  final FirebaseRecipientDocumentGateway phone;
  @override
  Future<AgreementCopyFile> readCopy(String agreementId, int revision) =>
      FirebaseAgreementCopyGateway(
        auth: phone.auth,
        functions: phone.functions,
      ).read(agreementId, revision);
  static Future<AgreementRecipientGateway> create() async =>
      FirebaseAgreementRecipientGateway(
        await FirebaseRecipientDocumentGateway.create(),
      );
  Future<ApprovalInfo> _call(String name, Map<String, dynamic> data) async {
    final uid = phone.auth.currentUser?.uid;
    final result = await phone.functions.httpsCallable(name).call(data);
    if (phone.auth.currentUser?.uid != uid) {
      throw const DocumentFailure(
        'Your verification changed. Reopen this link.',
      );
    }
    return ApprovalInfo(Map<String, dynamic>.from(result.data as Map));
  }

  @override
  Future<ApprovalInfo> read(String token) =>
      _call('readAgreementApproval', {'token': token});
  @override
  Future<bool> requestOtp(String number) => phone.requestOtp(number);
  @override
  Future<void> verifyOtp(String code) => phone.verifyOtp(code);
  @override
  Future<void> signOut() => phone.signOut();
  @override
  String operationId() =>
      FirebaseFirestore.instance.collection('agreementInvitations').doc().id;
  @override
  Future<ApprovalInfo> reply(
    String token,
    ApprovalInfo info,
    Map<String, dynamic> reply,
  ) => _call('replyToAgreementApproval', {
    'token': token,
    'revision': info.revision,
    'digest': info.digest,
    ...reply,
  });
}

String approvalStatus(String value) => switch (value) {
  'agreed' => 'Said yes',
  'seen' => 'Opened, not replied yet',
  'change_requested' => 'Asked for a change',
  _ => 'Not opened yet',
};
