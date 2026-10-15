import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../broker/data/private_documents.dart';

class AgreementCopyFile extends DocumentFile {
  AgreementCopyFile({
    required super.name,
    required super.bytes,
    this.mode,
    this.partyCount,
    this.startDate,
  });
  final String? mode;
  final int? partyCount;
  final DateTime? startDate;
  static const maximumCopyBytes = 20 * 1024 * 1024;
  String get digest => sha256.convert(bytes).toString();
  @override
  void validate() {
    if (bytes.isEmpty ||
        bytes.length > maximumCopyBytes ||
        contentType != 'application/pdf') {
      throw const DocumentFailure('Choose a readable PDF up to 20 MB.');
    }
  }
}

Future<AgreementCopyFile?> pickAgreementCopy() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file == null) return null;
  final size = await file.length();
  if (size != null && size > AgreementCopyFile.maximumCopyBytes) {
    throw const DocumentFailure('Choose a PDF up to 20 MB.');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    if (bytes.length + chunk.length > AgreementCopyFile.maximumCopyBytes) {
      throw const DocumentFailure('Choose a PDF up to 20 MB.');
    }
    bytes.add(chunk);
  }
  final result = AgreementCopyFile(name: file.name, bytes: bytes.takeBytes());
  result.validate();
  return result;
}

class AgreementCopyRequest {
  AgreementCopyRequest({
    required this.agreementId,
    required this.revision,
    required this.operationId,
    required this.file,
    required this.mode,
    this.templateName = '',
    this.approvedOriginal = false,
    this.allPartiesSigned = false,
    this.matchesReviewedTerms = false,
  });
  final String agreementId;
  final int revision;
  final String operationId;
  final AgreementCopyFile file;
  final String mode;
  final String templateName;
  final bool approvedOriginal;
  final bool allPartiesSigned;
  final bool matchesReviewedTerms;
  Map<String, dynamic> get payload => {
    'agreementId': agreementId,
    'revision': revision,
    'operationId': operationId,
    'sha256': file.digest,
    'size': file.bytes.length,
    'mode': mode,
    'templateName': templateName,
    'approvedOriginal': approvedOriginal,
    'allPartiesSigned': allPartiesSigned,
    'matchesReviewedTerms': matchesReviewedTerms,
  };
}

abstract interface class AgreementCopyGateway {
  String operationId();
  Future<void> publish(AgreementCopyRequest request);
  Future<AgreementCopyFile> read(String agreementId, int revision);
}

class FirebaseAgreementCopyGateway implements AgreementCopyGateway {
  FirebaseAgreementCopyGateway({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : auth = auth ?? FirebaseAuth.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  @override
  String operationId() =>
      FirebaseFirestore.instance.collection('agreements').doc().id;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> input,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Log in again.');
    final result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        )
        .call(input);
    if (auth.currentUser?.uid != uid) {
      throw const DocumentFailure('Your login changed. Reopen this agreement.');
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<void> publish(AgreementCopyRequest request) async {
    request.file.validate();
    final uid = auth.currentUser?.uid;
    final grant = await _call('beginAgreementCopyUpload', request.payload);
    final id = grant['uploadId'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        grant['path'] != 'agreementCopyUploads/$uid/$id/agreement.pdf') {
      throw const DocumentFailure('The private upload could not be confirmed.');
    }
    if (grant['completed'] != true) {
      await FirebaseStorage.instance
          .ref(grant['path'] as String)
          .putData(
            request.file.bytes,
            SettableMetadata(
              contentType: 'application/pdf',
              cacheControl: 'private, no-store',
            ),
          );
    }
    if (auth.currentUser?.uid != uid) {
      throw const DocumentFailure(
        'Your login changed. Retry after signing in.',
      );
    }
    final result = await _call('completeAgreementCopyUpload', {'uploadId': id});
    if (result['ready'] != true ||
        result['agreementId'] != request.agreementId ||
        result['revision'] != request.revision ||
        result['mode'] != request.mode ||
        result['sha256'] != request.file.digest ||
        result['size'] != request.file.bytes.length) {
      throw const DocumentFailure(
        'The server did not confirm this copy. Retry the same file.',
      );
    }
  }

  @override
  Future<AgreementCopyFile> read(String agreementId, int revision) async {
    final result = await _call('readAgreementCopy', {
      'agreementId': agreementId,
      'revision': revision,
    });
    return decodeAgreementCopy(result, agreementId, revision);
  }
}

AgreementCopyFile decodeAgreementCopy(
  Map<String, dynamic> data,
  String agreementId,
  int revision,
) {
  final size = data['size'];
  final encoded = data['base64'];
  if (data['ready'] != true ||
      data['agreementId'] != agreementId ||
      data['revision'] != revision ||
      !['demo', 'externally_signed'].contains(data['mode']) ||
      size is! int ||
      size <= 0 ||
      size > AgreementCopyFile.maximumCopyBytes ||
      encoded is! String ||
      encoded.length > ((size + 2) ~/ 3) * 4) {
    throw const DocumentFailure('This agreement copy could not be confirmed.');
  }
  final file = AgreementCopyFile(
    name: data['mode'] == 'demo'
        ? 'Demo agreement copy.pdf'
        : 'Signed agreement.pdf',
    bytes: base64Decode(encoded),
    mode: data['mode'] as String,
    partyCount:
        data['partyCount'] is int &&
            data['partyCount'] >= 2 &&
            data['partyCount'] <= 40
        ? data['partyCount'] as int
        : null,
    startDate: data['startDateISO'] is String
        ? DateTime.tryParse(data['startDateISO'] as String)
        : null,
  );
  file.validate();
  if (file.bytes.length != size || file.digest != data['sha256']) {
    throw const DocumentFailure(
      'This agreement copy failed its integrity check.',
    );
  }
  return file;
}
