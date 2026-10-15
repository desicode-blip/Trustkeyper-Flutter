import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../broker/data/agreement_imports.dart';
import '../../broker/data/private_documents.dart';

const ownerPropertyFeatures = [
  'AC',
  'Geyser',
  'Fridge',
  'Washing machine',
  'Cupboard',
  'Chimney',
  'Sofa',
  'Bed',
  'Lift',
  'Car parking',
  'Power backup',
  'Security',
  'Gym',
  'Pool',
  'Garden',
  'Gas line',
];

class OwnerPropertyRecord {
  OwnerPropertyRecord(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  int get revision => data['revision'] as int;
  int get nextStep => data['nextStep'] as int;
  String get status => data['status'] as String;
  Map<String, dynamic> get details =>
      Map<String, dynamic>.from(data['details'] as Map);
  List<Map<String, dynamic>> get photos => (data['photos'] as List? ?? [])
      .map((value) => Map<String, dynamic>.from(value as Map))
      .toList();
  String get name =>
      details['name'] is String && (details['name'] as String).isNotEmpty
      ? details['name'] as String
      : details['address'] is String &&
            (details['address'] as String).trim().isNotEmpty
      ? details['address'] as String
      : 'Unnamed property';
}

abstract interface class OwnerPropertyGateway {
  Future<List<OwnerPropertyRecord>> list({bool admin = false});
  Future<OwnerPropertyRecord> save(
    OwnerPropertyRecord? property,
    int step,
    Map<String, dynamic> input,
    String operationId,
  );
  Future<OwnerPropertyRecord> uploadPhotos(
    OwnerPropertyRecord property,
    List<AgreementPageFile> photos,
    String operationId, {
    bool admin = false,
  });
  Future<AgreementPageFile> readPhoto(
    OwnerPropertyRecord property,
    int index, {
    bool admin = false,
  });
  Future<OwnerPropertyRecord> requestPlan(
    OwnerPropertyRecord property,
    String plan,
    String method,
    String day,
    String slot,
  );
  Future<OwnerPropertyRecord> recordCheck(
    OwnerPropertyRecord property,
    Map<String, dynamic> details,
  );
}

class FirebaseOwnerPropertyGateway implements OwnerPropertyGateway {
  FirebaseOwnerPropertyGateway({
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
  @override
  Future<OwnerPropertyRecord> recordCheck(
    OwnerPropertyRecord property,
    Map<String, dynamic> details,
  ) async => OwnerPropertyRecord(
    await _call('recordOwnerPropertyCheck', {
      'id': property.id,
      'revision': property.revision,
      ...details,
    }),
  );
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
      if (auth.currentUser?.uid != uid) {
        throw const DocumentFailure(
          'Your session changed. Reopen this property.',
        );
      }
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw DocumentFailure(
        error.message ?? 'Your property could not be saved. Retry.',
      );
    }
  }

  @override
  Future<List<OwnerPropertyRecord>> list({bool admin = false}) async {
    final response = await _call('listOwnerProperties', {'admin': admin});
    return (response['properties'] as List)
        .map(
          (value) =>
              OwnerPropertyRecord(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
  }

  @override
  Future<OwnerPropertyRecord> save(
    OwnerPropertyRecord? property,
    int step,
    Map<String, dynamic> input,
    String operationId,
  ) async => OwnerPropertyRecord(
    await _call('saveOwnerPropertyStep', {
      'id': property?.id,
      'revision': property?.revision ?? 0,
      'operationId': operationId,
      'step': step,
      'input': input,
    }),
  );
  @override
  Future<OwnerPropertyRecord> uploadPhotos(
    OwnerPropertyRecord property,
    List<AgreementPageFile> photos,
    String operationId, {
    bool admin = false,
  }) async {
    if (photos.isEmpty ||
        photos.length > 5 ||
        photos.any(
          (file) =>
              file.contentType == 'application/pdf' ||
              file.bytes.length > 10485760,
        ) ||
        photos.fold<int>(0, (total, file) => total + file.bytes.length) >
            20971520) {
      throw const DocumentFailure(
        'Choose 1 to 5 JPG/PNG photos, up to 10 MB each and 20 MB in total.',
      );
    }
    for (final photo in photos) {
      photo.validate();
    }
    final uid = auth.currentUser?.uid;
    final grant = await _call('beginOwnerPropertyPhotos', {
      'id': property.id,
      'revision': property.revision,
      'operationId': operationId,
      'specs': photos.map((photo) => photo.payload).toList(),
      'admin': admin,
    });
    final uploadId = grant['uploadId'];
    final paths = grant['paths'];
    if (uploadId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(uploadId) ||
        paths is! List ||
        paths.length != photos.length ||
        List.generate(
          photos.length,
          (index) =>
              paths[index] == 'ownerPropertyUploads/$uid/$uploadId/$index',
        ).contains(false)) {
      throw const DocumentFailure(
        'The private photo upload could not be confirmed.',
      );
    }
    if (grant['completed'] != true) {
      for (var index = 0; index < photos.length; index++) {
        if (auth.currentUser?.uid != uid) {
          throw const DocumentFailure(
            'Your session changed. Reopen this property.',
          );
        }
        await storage
            .ref(paths[index] as String)
            .putData(
              photos[index].bytes,
              SettableMetadata(
                contentType: photos[index].contentType,
                cacheControl: 'private, no-store',
              ),
            );
      }
    }
    final result = OwnerPropertyRecord(
      await _call('completeOwnerPropertyPhotos', {
        'uploadId': uploadId,
        'admin': admin,
      }),
    );
    if (result.id != property.id) {
      throw const DocumentFailure('The saved photos could not be confirmed.');
    }
    return result;
  }

  @override
  Future<AgreementPageFile> readPhoto(
    OwnerPropertyRecord property,
    int index, {
    bool admin = false,
  }) async {
    final response = await _call('readOwnerPropertyPhoto', {
      'id': property.id,
      'index': index,
      'admin': admin,
    });
    final size = response['size'];
    final encoded = response['base64'];
    if (size is! int ||
        size <= 0 ||
        size > 10485760 ||
        encoded is! String ||
        encoded.length > ((size + 2) ~/ 3) * 4) {
      throw const DocumentFailure('This private photo could not be confirmed.');
    }
    final file = AgreementPageFile(
      name: 'Property photo ${index + 1}',
      bytes: Uint8List.fromList(base64Decode(encoded)),
    );
    file.validate();
    if (file.bytes.length != size ||
        file.digest != response['sha256'] ||
        file.contentType != response['contentType']) {
      throw const DocumentFailure('The photo failed its integrity check.');
    }
    return file;
  }

  @override
  Future<OwnerPropertyRecord> requestPlan(
    OwnerPropertyRecord property,
    String plan,
    String method,
    String day,
    String slot,
  ) async => OwnerPropertyRecord(
    await _call('requestOwnerPropertyPlan', {
      'id': property.id,
      'revision': property.revision,
      'plan': plan,
      'method': method,
      'day': day,
      'slot': slot,
    }),
  );
}
