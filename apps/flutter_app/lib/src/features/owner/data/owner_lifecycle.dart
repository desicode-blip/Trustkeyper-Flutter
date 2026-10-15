import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../broker/data/agreement_imports.dart';
import '../../broker/data/private_documents.dart';
import 'owner_properties.dart';

abstract interface class OwnerLifecycleGateway {
  Future<Map<String, dynamic>> change(
    OwnerPropertyRecord property,
    String action,
    Map<String, dynamic> input,
  );
  Future<OwnerPropertyRecord> uploadContract(
    OwnerPropertyRecord property,
    AgreementPageFile file,
    String kind,
    String reference,
    String operationId, {
    required bool signaturesChecked,
  });
  Future<AgreementPageFile> readContract(
    OwnerPropertyRecord property, {
    bool signed = false,
    bool admin = false,
  });
  Future<Map<String, dynamic>> readPublic(String id);
  Future<AgreementPageFile> readPublicPhoto(String id, int index);
  Future<void> enquire(String id, Map<String, dynamic> input);
  Future<Map<String, dynamic>> receipt(String id);
}

class FirebaseOwnerLifecycleGateway implements OwnerLifecycleGateway {
  FirebaseOwnerLifecycleGateway({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : auth = auth ?? FirebaseAuth.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       storage = storage ?? FirebaseStorage.instance;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  final FirebaseStorage storage;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input, {
    bool public = false,
  }) async {
    final uid = auth.currentUser?.uid;
    if (!public && uid == null) {
      throw const DocumentFailure('Log in again.');
    }
    try {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
          )
          .call(input);
      if (!public && auth.currentUser?.uid != uid) {
        throw const DocumentFailure(
          'Your session changed. Reopen this property.',
        );
      }
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw DocumentFailure(
        error.message ?? 'The update was not confirmed. Refresh and retry.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> change(
    OwnerPropertyRecord property,
    String action,
    Map<String, dynamic> input,
  ) => _call('changeOwnerPropertyLifecycle', {
    ...input,
    'id': property.id,
    'revision': property.revision,
    'action': action,
  });
  @override
  Future<OwnerPropertyRecord> uploadContract(
    OwnerPropertyRecord property,
    AgreementPageFile file,
    String kind,
    String reference,
    String operationId, {
    required bool signaturesChecked,
  }) async {
    file.validate();
    if (file.contentType != 'application/pdf') {
      throw const DocumentFailure('Select the actual PDF contract.');
    }
    final uid = auth.currentUser?.uid;
    final grant = await _call('beginOwnerContractUpload', {
      'id': property.id,
      'revision': property.revision,
      'operationId': operationId,
      'kind': kind,
      'spec': file.payload,
      'reference': reference,
      'originalChecked': true,
      'signaturesChecked': signaturesChecked,
    });
    final uploadId = grant['uploadId'];
    if (uploadId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(uploadId) ||
        grant['path'] != 'ownerContractUploads/$uid/$uploadId/contract.pdf') {
      throw const DocumentFailure(
        'The private contract upload could not be confirmed.',
      );
    }
    if (grant['completed'] != true) {
      if (auth.currentUser?.uid != uid) {
        throw const DocumentFailure('Your session changed.');
      }
      await storage
          .ref(grant['path'] as String)
          .putData(
            file.bytes,
            SettableMetadata(
              contentType: 'application/pdf',
              cacheControl: 'private, no-store',
            ),
          );
    }
    return OwnerPropertyRecord(
      await _call('completeOwnerContractUpload', {'uploadId': uploadId}),
    );
  }

  AgreementPageFile _file(
    Map<String, dynamic> data,
    String name, {
    bool pdf = false,
  }) {
    final size = data['size'];
    final encoded = data['base64'];
    if (size is! int ||
        size < 1 ||
        size > (pdf ? 20971520 : 10485760) ||
        encoded is! String ||
        encoded.length > ((size + 2) ~/ 3) * 4) {
      throw const DocumentFailure('This file cannot be confirmed.');
    }
    final file = AgreementPageFile(
      name: name,
      bytes: Uint8List.fromList(base64Decode(encoded)),
    );
    file.validate();
    if (file.bytes.length != size ||
        file.digest != data['sha256'] ||
        file.contentType != (pdf ? 'application/pdf' : data['contentType'])) {
      throw const DocumentFailure('The file failed its integrity check.');
    }
    return file;
  }

  @override
  Future<AgreementPageFile> readContract(
    OwnerPropertyRecord property, {
    bool signed = false,
    bool admin = false,
  }) async => _file(
    await _call('readOwnerContract', {
      'id': property.id,
      'signed': signed,
      'admin': admin,
    }),
    'Owner contract.pdf',
    pdf: true,
  );
  @override
  Future<Map<String, dynamic>> readPublic(String id) =>
      _call('readPublicOwnerListing', {'id': id}, public: true);
  @override
  Future<AgreementPageFile> readPublicPhoto(String id, int index) async =>
      _file(
        await _call('readPublicOwnerListing', {
          'id': id,
          'photoIndex': index,
        }, public: true),
        'Property photo ${index + 1}',
      );
  @override
  Future<void> enquire(String id, Map<String, dynamic> input) async {
    await _call('enquireOwnerListing', {...input, 'id': id});
  }

  @override
  Future<Map<String, dynamic>> receipt(String id) =>
      _call('enquireOwnerListing', {'id': id, 'action': 'status'});
}

abstract interface class OwnerContractPhoneProof {
  String get phone;
  Future<void> sendCode();
  Future<void> confirmCode(String code);
}

class FirebaseOwnerContractPhoneProof implements OwnerContractPhoneProof {
  FirebaseOwnerContractPhoneProof({FirebaseAuth? auth})
    : auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth auth;
  String? verificationId;
  String? expectedUid;
  PhoneAuthCredential? automatic;
  @override
  String get phone => auth.currentUser?.phoneNumber ?? '';
  @override
  Future<void> sendCode() async {
    final user = auth.currentUser;
    if (user == null ||
        phone.isEmpty ||
        !user.providerData.any((value) => value.providerId == 'phone')) {
      throw const DocumentFailure(
        'Verify and link your phone in your profile first.',
      );
    }
    expectedUid = user.uid;
    verificationId = null;
    automatic = null;
    try {
      if (kIsWeb) {
        verificationId = (await auth.signInWithPhoneNumber(
          phone,
        )).verificationId;
      } else {
        final sent = Completer<void>();
        await auth.verifyPhoneNumber(
          phoneNumber: phone,
          timeout: const Duration(seconds: 45),
          verificationCompleted: (credential) {
            automatic = credential;
            if (!sent.isCompleted) sent.complete();
          },
          verificationFailed: (error) {
            if (!sent.isCompleted) {
              sent.completeError(
                DocumentFailure(error.message ?? 'The code could not be sent.'),
              );
            }
          },
          codeSent: (id, _) {
            verificationId = id;
            if (!sent.isCompleted) sent.complete();
          },
          codeAutoRetrievalTimeout: (id) {
            verificationId = id;
            if (!sent.isCompleted) sent.complete();
          },
        );
        await sent.future.timeout(const Duration(seconds: 50));
      }
      if (auth.currentUser?.uid != expectedUid) {
        throw const DocumentFailure(
          'Your session changed. Reopen the contract.',
        );
      }
    } on FirebaseAuthException catch (error) {
      throw DocumentFailure(error.message ?? 'Request a new code.');
    } on TimeoutException {
      throw const DocumentFailure('The code request timed out. Try again.');
    }
  }

  @override
  Future<void> confirmCode(String code) async {
    final user = auth.currentUser;
    if (user == null ||
        expectedUid != user.uid ||
        verificationId == null && automatic == null) {
      throw const DocumentFailure('Request a new code for this contract.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code) && automatic == null) {
      throw const DocumentFailure('Enter the six-digit code.');
    }
    try {
      final credential =
          automatic ??
          PhoneAuthProvider.credential(
            verificationId: verificationId!,
            smsCode: code,
          );
      final result = await user.reauthenticateWithCredential(credential);
      if (result.user?.uid != expectedUid ||
          auth.currentUser?.uid != expectedUid) {
        throw const DocumentFailure(
          'The verified phone does not match this account.',
        );
      }
      await auth.currentUser!.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      throw DocumentFailure(
        error.message ?? 'That code was not accepted. Request a new code.',
      );
    }
  }
}
