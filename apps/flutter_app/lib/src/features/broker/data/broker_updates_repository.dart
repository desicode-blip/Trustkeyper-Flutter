import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../document_requests/data/document_request_repository.dart';
import 'private_documents.dart';

class BrokerUpdate {
  BrokerUpdate(this.id, Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final String id;
  final Map<String, dynamic> data;
  String get title => data['title'] as String;
  String get address => data['address'] as String;
  String get requestId => data['requestId'] as String;
  DateTime get at =>
      DateTime.fromMillisecondsSinceEpoch((data['atMs'] as num).toInt());
  bool get unread => data['readAt'] == null;
}

abstract interface class BrokerUpdatesRepository {
  Stream<List<BrokerUpdate>> watch();
  Future<void> markRead(BrokerUpdate update);
  Future<DocumentRequestInfo> request(String id);
}

class FirebaseBrokerUpdatesRepository implements BrokerUpdatesRepository {
  FirebaseBrokerUpdatesRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  String _uid() =>
      auth.currentUser?.uid ??
      (throw const DocumentFailure('Log in again to see your updates.'));
  void _session(String uid) {
    if (auth.currentUser?.uid != uid) {
      throw const DocumentFailure('Your login changed. Reopen your updates.');
    }
  }

  @override
  Stream<List<BrokerUpdate>> watch() {
    final uid = _uid();
    return firestore
        .collection('users/$uid/updates')
        .orderBy('atMs', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          _session(uid);
          return snapshot.docs
              .where((document) => document.data()['brokerUid'] == uid)
              .map((document) => BrokerUpdate(document.id, document.data()))
              .toList();
        });
  }

  @override
  Future<void> markRead(BrokerUpdate update) async {
    final uid = _uid();
    if (update.data['brokerUid'] != uid ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(update.id)) {
      throw const DocumentFailure('This update belongs to another account.');
    }
    await firestore.doc('users/$uid/updates/${update.id}').update({
      'readAt': FieldValue.serverTimestamp(),
    });
    _session(uid);
  }

  @override
  Future<DocumentRequestInfo> request(String id) async {
    final uid = _uid();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const DocumentFailure('Invalid document request.');
    }
    final document = await firestore
        .doc('brokerDocumentRequests/$id')
        .get(const GetOptions(source: Source.server));
    _session(uid);
    final data = document.data();
    if (data == null || data['brokerUid'] != uid) {
      throw const DocumentFailure('This document request is unavailable.');
    }
    return DocumentRequestInfo({...data, 'requestId': id, 'verified': true});
  }

  Future<String> registerDevice(String token, String platform) async {
    final uid = _uid();
    final id = sha256.convert(utf8.encode(token)).toString();
    await firestore.doc('users/$uid/pushDevices/$id').set({
      'token': token,
      'platform': platform,
      'enabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (auth.currentUser?.uid != uid) {
      await firestore.doc('users/$uid/pushDevices/$id').delete();
      throw const DocumentFailure('Your login changed.');
    }
    return id;
  }

  Future<void> removeDevice(String uid, String id) =>
      firestore.doc('users/$uid/pushDevices/$id').delete();
}
