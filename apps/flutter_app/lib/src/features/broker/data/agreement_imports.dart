import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../agreement_copies/agreement_copies.dart';
import 'private_documents.dart';

String importOperationId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

class AgreementPageFile extends DocumentFile {
  AgreementPageFile({required super.name, required super.bytes});
  String get digest => sha256.convert(bytes).toString();
  Map<String, dynamic> get payload => {
    'sha256': digest,
    'size': bytes.length,
    'contentType': contentType,
  };
  @override
  void validate() {
    if (bytes.isEmpty || bytes.length > AgreementCopyFile.maximumCopyBytes) {
      throw const DocumentFailure(
        'Choose readable pages up to 20 MB in total.',
      );
    }
    contentType;
  }
}

class AgreementSigner {
  const AgreementSigner({
    required this.name,
    required this.phone,
    required this.role,
  });
  final String name;
  final String phone;
  final String role;
  Map<String, dynamic> get payload => {
    'name': name.trim(),
    'phone': phone,
    'role': role,
  };
}

void validateSigningRequest(
  List<AgreementPageFile> files,
  List<AgreementSigner> signers,
) {
  if (files.isEmpty ||
      files.length > 40 ||
      files.fold<int>(0, (total, file) => total + file.bytes.length) >
          AgreementCopyFile.maximumCopyBytes ||
      files.any((file) => file.contentType == 'application/pdf') &&
          files.length != 1) {
    throw const DocumentFailure(
      'Add one PDF or up to 40 photos, with a 20 MB total limit.',
    );
  }
  for (final file in files) {
    file.validate();
  }
  if (files.map((file) => file.digest).toSet().length != files.length) {
    throw const DocumentFailure(
      'The same page was added twice. Remove the duplicate.',
    );
  }
  if (signers.length < 2 ||
      signers.length > 40 ||
      !signers.any((person) => person.role == 'owner') ||
      !signers.any((person) => person.role == 'tenant') ||
      signers.map((person) => person.phone).toSet().length != signers.length ||
      signers.any(
        (person) =>
            person.name.trim().length < 2 ||
            person.name.trim().length > 100 ||
            !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(person.phone) ||
            !['owner', 'tenant', 'witness'].contains(person.role),
      )) {
    throw const DocumentFailure(
      'Give every signer a name, role and different mobile number. Include an owner and a tenant.',
    );
  }
}

class SigningRequest {
  SigningRequest(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get status => data['status'] as String;
  int get revision => data['revision'] as int;
  int get pageCount => data['pageCount'] as int? ?? 0;
  List<AgreementSigner> get signers => (data['signers'] as List)
      .map(
        (value) => AgreementSigner(
          name: value['name'] as String,
          phone: value['phone'] as String,
          role: value['role'] as String,
        ),
      )
      .toList();
  String get stageLabel => switch (status) {
    'received' => 'Agreement received',
    'stamp_preparing' => 'Buying stamp paper',
    'ready_to_sign' => 'Ready for signing',
    'signing' => 'Sent to everyone to sign',
    'completed' => 'Agreement signed',
    _ => 'Upload in progress',
  };
  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(data['updatedAtMs'] as int);
}

abstract interface class AgreementImportGateway {
  Future<String> send(
    List<AgreementPageFile> files,
    List<AgreementSigner> signers,
    String operationId,
  );
  Future<List<SigningRequest>> list();
  Future<AgreementPageFile> read(String id, {bool signed = false});
  Future<void> record(
    SigningRequest request,
    String status,
    String reference,
    String note,
  );
  Future<void> publish(
    SigningRequest request,
    AgreementPageFile file,
    String operationId,
  );
}

class FirebaseAgreementImportGateway implements AgreementImportGateway {
  FirebaseAgreementImportGateway({
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
    Map<String, dynamic> input,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const DocumentFailure('Log in again.');
    try {
      final result = await functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
          )
          .call(input);
      if (uid != auth.currentUser?.uid) {
        throw const DocumentFailure(
          'Your session changed. Reopen the agreement.',
        );
      }
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw DocumentFailure(
        error.message ?? 'The server could not confirm this request. Retry.',
      );
    }
  }

  Future<String> _upload(
    String callable,
    Map<String, dynamic> payload,
    List<AgreementPageFile> files,
  ) async {
    final uid = auth.currentUser?.uid;
    final grant = await _call(callable, payload);
    final uploadId = grant['uploadId'];
    final paths = grant['paths'];
    if (uploadId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(uploadId) ||
        paths is! List ||
        paths.length != files.length ||
        List.generate(
          files.length,
          (index) =>
              paths[index] == 'agreementImportUploads/$uid/$uploadId/$index',
        ).contains(false)) {
      throw const DocumentFailure('The private upload could not be confirmed.');
    }
    if (grant['completed'] != true) {
      for (var index = 0; index < files.length; index++) {
        if (auth.currentUser?.uid != uid) {
          throw const DocumentFailure('Your session changed. Log in again.');
        }
        await storage
            .ref(paths[index] as String)
            .putData(
              files[index].bytes,
              SettableMetadata(
                contentType: files[index].contentType,
                cacheControl: 'private, no-store',
              ),
            );
      }
    }
    final result = await _call('completeAgreementImport', {
      'uploadId': uploadId,
    });
    final requestId = result['requestId'];
    if (result['ready'] != true ||
        requestId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(requestId)) {
      throw const DocumentFailure(
        'The server did not confirm your pages. Retry the same send.',
      );
    }
    return requestId;
  }

  @override
  Future<String> send(
    List<AgreementPageFile> files,
    List<AgreementSigner> signers,
    String operationId,
  ) async {
    validateSigningRequest(files, signers);
    return _upload('beginAgreementImport', {
      'operationId': operationId,
      'pagesReviewed': true,
      'files': files.map((file) => file.payload).toList(),
      'signers': signers.map((person) => person.payload).toList(),
    }, files);
  }

  @override
  Future<List<SigningRequest>> list() async {
    final result = await _call('listAgreementImports', {});
    return (result['requests'] as List)
        .map((value) => SigningRequest(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  @override
  Future<AgreementPageFile> read(String id, {bool signed = false}) async {
    final result = await _call('readAgreementImport', {
      'requestId': id,
      'signed': signed,
    });
    if (result['requestId'] != id ||
        result['signed'] != signed ||
        result['size'] is! int ||
        result['size'] <= 0 ||
        result['size'] > AgreementCopyFile.maximumCopyBytes ||
        result['base64'] is! String ||
        (result['base64'] as String).length >
            ((result['size'] as int) + 2) ~/ 3 * 4) {
      throw const DocumentFailure('This private copy could not be confirmed.');
    }
    final file = AgreementPageFile(
      name: signed ? 'Signed agreement.pdf' : 'Agreement pages.pdf',
      bytes: Uint8List.fromList(base64Decode(result['base64'] as String)),
    );
    file.validate();
    if (file.bytes.length != result['size'] ||
        file.digest != result['sha256']) {
      throw const DocumentFailure(
        'The copy failed its integrity check. Retry.',
      );
    }
    return file;
  }

  @override
  Future<void> record(
    SigningRequest request,
    String status,
    String reference,
    String note,
  ) async {
    await _call('recordAgreementImport', {
      'requestId': request.id,
      'revision': request.revision,
      'status': status,
      'reference': reference,
      'note': note,
    });
  }

  @override
  Future<void> publish(
    SigningRequest request,
    AgreementPageFile file,
    String operationId,
  ) async {
    await _upload(
      'beginSignedAgreementImport',
      {
        'requestId': request.id,
        'revision': request.revision,
        'operationId': operationId,
        'file': file.payload,
        'allPartiesSigned': true,
        'originalChecked': true,
      },
      [file],
    );
  }
}
