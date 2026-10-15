import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../broker/data/private_documents.dart';

enum RequestedPaper {
  aadhaar('Aadhaar card', [
    DocumentKind.aadhaarFront,
    DocumentKind.aadhaarBack,
  ]),
  pan('PAN card', [DocumentKind.pan]),
  bank('Bank account', [DocumentKind.bankProof]),
  linkedin('LinkedIn profile', []),
  all('documents', [
    DocumentKind.aadhaarFront,
    DocumentKind.aadhaarBack,
    DocumentKind.pan,
    DocumentKind.bankProof,
  ]);

  const RequestedPaper(this.label, this.slots);
  final String label;
  final List<DocumentKind> slots;
  static const individual = [aadhaar, pan, bank];
  List<RequestedPaper> get papers => this == all ? individual : [this];
}

class DocumentRequestInfo {
  DocumentRequestInfo(Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get id => data['requestId'] as String;
  RequestedPaper get paper =>
      RequestedPaper.values.byName(data['type'] as String);
  String get status => data['status'] as String;
  String get phone => data['phone'] as String;
  String get name => data['partyName'] as String;
  String get broker => data['brokerName'] as String;
  String get address => data['address'] as String;
  String get role => data['role'] as String;
  String get reason => data['reason'] as String? ?? '';
  bool get verified => data['verified'] == true;
  int get version => data['version'] as int;
  int get sharedAtMs => (data['sharedAtMs'] as num?)?.toInt() ?? 0;
  int get issuedAtMs =>
      (data['issuedAtMs'] as num?)?.toInt() ??
      (data['createdAtMs'] as num?)?.toInt() ??
      0;
  String? get channel => data['channel'] as String?;
  Map<String, dynamic> get closedPapers =>
      Map<String, dynamic>.from(data['closedPapers'] as Map? ?? {});
  List<DocumentKind> get slots => data['slots'] is List
      ? (data['slots'] as List)
            .map((kind) => DocumentKind.values.byName(kind as String))
            .toList()
      : paper.slots
            .where(
              (kind) => !closedPapers.keys.any(
                (name) =>
                    RequestedPaper.values.byName(name).slots.contains(kind),
              ),
            )
            .toList();
  List<RequestedPaper> get papers =>
      paper.papers.where((item) => item.slots.every(slots.contains)).toList();
  bool get expired =>
      (data['expiresAtMs'] as num).toInt() <=
      DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic>? get submission => data['submission'] == null
      ? null
      : Map<String, dynamic>.from(data['submission'] as Map);
}

class IssuedDocumentLink {
  IssuedDocumentLink(this.token, this.info);
  final String token;
  final DocumentRequestInfo info;
  Uri get url => Uri(
    scheme: 'https',
    host: 'trustkeyper.web.app',
    path: '/',
    fragment: '/documents/request?token=${Uri.encodeComponent(token)}',
  );
}

abstract interface class DocumentRequests {
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision);
  Future<IssuedDocumentLink> create({
    required String draftId,
    required int revision,
    required String partyId,
    required RequestedPaper paper,
    bool remind = false,
  });
  Future<void> record(
    DocumentRequestInfo info,
    String action, {
    String? reason,
    String? channel,
    RequestedPaper? paper,
    Map<String, dynamic>? linkedInDetails,
  });
  Future<DocumentFile> readFile(Map<String, dynamic> file);
}

class FirebaseDocumentRequests implements DocumentRequests {
  FirebaseDocumentRequests();
  FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final response = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.error(const DocumentFailure('Log in again.'));
    }
    return FirebaseFirestore.instance
        .collection('brokerDocumentRequests')
        .where('brokerUid', isEqualTo: uid)
        .where('draftId', isEqualTo: draftId)
        .where('revision', isEqualTo: revision)
        .snapshots()
        .map((snapshot) {
          if (FirebaseAuth.instance.currentUser?.uid != uid) {
            throw const DocumentFailure(
              'Your login changed. Reopen this draft.',
            );
          }
          return snapshot.docs
              .map(
                (doc) => DocumentRequestInfo({
                  ...doc.data(),
                  'requestId': doc.id,
                  'verified': true,
                }),
              )
              .toList();
        });
  }

  @override
  Future<IssuedDocumentLink> create({
    required String draftId,
    required int revision,
    required String partyId,
    required RequestedPaper paper,
    bool remind = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Log in again.');
    final operationId = FirebaseFirestore.instance
        .collection('brokerDocumentRequests')
        .doc()
        .id;
    final result = await _call('createDocumentRequest', {
      'draftId': draftId,
      'revision': revision,
      'partyId': partyId,
      'type': paper.name,
      'remind': remind,
      'operationId': operationId,
    });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw const DocumentFailure('Your login changed. Reopen this draft.');
    }
    return IssuedDocumentLink(
      result['token'] as String,
      DocumentRequestInfo(result),
    );
  }

  @override
  Future<void> record(
    DocumentRequestInfo info,
    String action, {
    String? reason,
    String? channel,
    RequestedPaper? paper,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    await _call('recordDocumentRequest', {
      'requestId': info.id,
      'version': info.version,
      'action': action,
      'reason': ?reason,
      'channel': ?channel,
      'paper': ?paper?.name,
      'linkedInDetails': ?linkedInDetails,
    });
  }

  @override
  Future<DocumentFile> readFile(Map<String, dynamic> file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Log in again.');
    final bytes = await FirebaseStorage.instance
        .ref(file['path'] as String)
        .getData(DocumentFile.maximumBytes);
    if (FirebaseAuth.instance.currentUser?.uid != uid || bytes == null) {
      throw const DocumentFailure('Reopen this document after logging in.');
    }
    return DocumentFile(
      name: file['name'] as String,
      bytes: Uint8List.fromList(bytes),
    );
  }
}
