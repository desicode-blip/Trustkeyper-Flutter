import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../../firebase_options.dart';
import '../../auth/data/recipient_web_persistence.dart';
import '../../broker/data/private_documents.dart';
import 'document_request_repository.dart';

abstract interface class RecipientDocumentGateway {
  Future<DocumentRequestInfo> read(String token);
  Future<bool> requestOtp(String phone);
  Future<void> verifyOtp(String code);
  Future<void> signOut();
  Future<DocumentRequestInfo> submit(
    String token,
    Map<DocumentKind, DocumentFile> files,
    void Function(double) progress, {
    Map<String, dynamic>? bankDetails,
    Map<String, dynamic>? linkedInDetails,
  });
}

abstract interface class RecipientVerificationSession {
  String? get currentUid;
  Stream<String?> get identities;
}

class FirebaseRecipientDocumentGateway
    implements RecipientDocumentGateway, RecipientVerificationSession {
  FirebaseRecipientDocumentGateway._(this.app);
  final FirebaseApp app;
  FirebaseAuth get auth => FirebaseAuth.instanceFor(app: app);
  @override
  String? get currentUid => auth.currentUser?.uid;
  @override
  Stream<String?> get identities => auth.userChanges().map((user) => user?.uid);
  FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(app: app, region: 'asia-south1');
  ConfirmationResult? confirmation;
  String? verificationId;
  static Future<FirebaseRecipientDocumentGateway> create() async {
    const name = 'document-recipient';
    final existing = Firebase.apps.where((app) => app.name == name);
    final app = existing.isEmpty
        ? await Firebase.initializeApp(
            name: name,
            options: DefaultFirebaseOptions.currentPlatform,
          )
        : existing.first;
    final gateway = FirebaseRecipientDocumentGateway._(app);
    if (kIsWeb) await configureRecipientWebPersistence(gateway.auth);
    return gateway;
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(
            timeout: Duration(
              seconds: name == 'readDocumentRequest' ? 35 : 120,
            ),
          ),
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<DocumentRequestInfo> read(String token) async =>
      DocumentRequestInfo(await _call('readDocumentRequest', {'token': token}));
  @override
  Future<bool> requestOtp(String phone) async {
    confirmation = null;
    verificationId = null;
    if (kIsWeb) {
      confirmation = await auth.signInWithPhoneNumber(phone);
      return false;
    }
    final result = Completer<bool>();
    await auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        try {
          await auth.signInWithCredential(credential);
          if (!result.isCompleted) result.complete(true);
        } catch (error) {
          if (!result.isCompleted) result.completeError(error);
        }
      },
      verificationFailed: (error) {
        if (!result.isCompleted) result.completeError(error);
      },
      codeSent: (id, resendToken) {
        verificationId = id;
        if (!result.isCompleted) result.complete(false);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return result.future.timeout(const Duration(seconds: 45));
  }

  @override
  Future<void> verifyOtp(String code) async {
    if (kIsWeb) {
      if (confirmation == null) {
        throw const DocumentFailure('Request a new code.');
      }
      await confirmation!.confirm(code).timeout(const Duration(seconds: 45));
    } else {
      if (verificationId == null) {
        throw const DocumentFailure('Request a new code.');
      }
      await auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId!,
          smsCode: code,
        ),
      );
    }
  }

  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<DocumentRequestInfo> submit(
    String token,
    Map<DocumentKind, DocumentFile> files,
    void Function(double) progress, {
    Map<String, dynamic>? bankDetails,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Verify your phone again.');
    final grant = await _call('beginDocumentUpload', {
      'token': token,
      'bankDetails': ?bankDetails,
      'linkedInDetails': ?linkedInDetails,
    });
    final paths = Map<String, dynamic>.from(grant['paths'] as Map);
    if (paths.length != files.length ||
        paths.keys.any((key) => !files.keys.any((kind) => kind.name == key))) {
      throw const DocumentFailure('Add every requested page before sending.');
    }
    var finished = 0;
    for (final entry in files.entries) {
      entry.value.validate();
      if (auth.currentUser?.uid != uid) {
        throw const DocumentFailure(
          'Your verification changed. Reopen the link.',
        );
      }
      final upload = FirebaseStorage.instanceFor(app: app)
          .ref(paths[entry.key.name] as String)
          .putData(
            entry.value.bytes,
            SettableMetadata(
              contentType: entry.value.contentType,
              cacheControl: 'private, no-store',
              customMetadata: {'displayName': entry.value.name},
            ),
          );
      final subscription = upload.snapshotEvents.listen((snapshot) {
        progress(
          (finished +
                  (snapshot.totalBytes == 0
                      ? 0
                      : snapshot.bytesTransferred / snapshot.totalBytes)) /
              (files.length + 1),
        );
      }, onError: (Object _) {});
      try {
        await upload.timeout(
          const Duration(minutes: 2),
          onTimeout: () async {
            await upload.cancel();
            throw TimeoutException('Document upload timed out.');
          },
        );
      } finally {
        await subscription.cancel();
      }
      finished++;
    }
    if (auth.currentUser?.uid != uid) {
      throw const DocumentFailure(
        'Your verification changed. Reopen the link.',
      );
    }
    final result = await _call('completeDocumentUpload', {
      'token': token,
      'uploadId': grant['uploadId'],
    });
    if (auth.currentUser?.uid != uid || result['status'] != 'added') {
      throw const DocumentFailure(
        'The broker has not received a confirmed submission. Retry sending.',
      );
    }
    progress(1);
    return DocumentRequestInfo(result);
  }
}
