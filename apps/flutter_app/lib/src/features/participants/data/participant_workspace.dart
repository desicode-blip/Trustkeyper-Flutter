import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../broker/data/private_documents.dart';
import 'participant_repository.dart';

class ParticipantIdentity {
  const ParticipantIdentity({
    this.uid = '',
    this.name = '',
    this.phone = '',
    this.email = '',
    this.emailVerified = false,
  });
  final String uid;
  final String name;
  final String phone;
  final String email;
  final bool emailVerified;
}

DateTime? recordDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, dynamic>? linkedParty(
  ParticipantRecord agreement,
  ParticipantIdentity identity,
  String role,
) {
  final parties = agreement.data[role == 'owner' ? 'owners' : 'tenants'];
  final participants = agreement.data['participantUids'];
  if (parties is! List ||
      identity.uid.isEmpty ||
      participants is! List ||
      !participants.contains(identity.uid)) {
    return null;
  }
  final matches = parties.whereType<Map>().where(
    (party) =>
        party['uid'] == identity.uid ||
        (identity.phone.isNotEmpty && party['phone'] == identity.phone),
  );
  if (matches.length != 1) return null;
  return Map<String, dynamic>.from(matches.single);
}

int? personalShare(
  ParticipantRecord agreement,
  ParticipantIdentity identity,
  String key,
) {
  final value = linkedParty(agreement, identity, 'tenant')?[key];
  return value is int && value >= 0 ? value : null;
}

class IssueInput {
  const IssueInput({
    required this.agreementId,
    required this.category,
    required this.description,
    this.reportId = '',
    this.photos = const [],
  });
  final String agreementId;
  final String category;
  final String description;
  final String reportId;
  final List<DocumentFile> photos;
  static const categories = [
    'Water',
    'Electric',
    'Appliance',
    'Door / lock',
    'Other',
  ];
  String? get error {
    if (agreementId.isEmpty) return 'Choose your linked home.';
    if (!categories.contains(category)) return 'Choose the type of problem.';
    if (description.trim().length < 10 || description.trim().length > 2000) {
      return 'Describe the problem in 10–2000 characters.';
    }
    if (photos.length > 4) return 'Add up to four photos.';
    for (final photo in photos) {
      try {
        photo.validate();
        if (!photo.contentType.startsWith('image/')) {
          return 'Repair photos must be JPG or PNG images.';
        }
      } on DocumentFailure catch (failure) {
        return failure.message;
      }
    }
    return null;
  }
}

abstract interface class ParticipantIssueWriter {
  Future<String> create(IssueInput input);
}

String newRepairReportId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

abstract interface class IssuePhotoReader {
  Future<Uint8List> readPhoto(String issueId, String path);
}

class FirebaseParticipantIssueWriter
    implements ParticipantIssueWriter, IssuePhotoReader {
  FirebaseParticipantIssueWriter({
    required this.uid,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       storage = storage ?? FirebaseStorage.instance;
  final String Function() uid;
  final FirebaseFunctions functions;
  final FirebaseStorage storage;

  @override
  Future<String> create(IssueInput input) async {
    if (input.error != null) throw StateError(input.error!);
    final identity = uid();
    if (identity.isEmpty) throw StateError('Log in again before sending.');
    final reportId = input.reportId.isEmpty
        ? newRepairReportId()
        : input.reportId;
    final started = await functions.httpsCallable('beginRepairReport').call({
      'reportId': reportId,
      'agreementId': input.agreementId,
    });
    if (started.data['submitted'] != true) {
      for (var index = 0; index < input.photos.length; index++) {
        if (uid() != identity) {
          throw StateError('Your login changed. Reopen the report.');
        }
        final photo = input.photos[index];
        await storage
            .ref('repairUploads/$identity/$reportId/$index')
            .putData(
              photo.bytes,
              SettableMetadata(
                contentType: photo.contentType,
                cacheControl: 'private, no-store',
              ),
            );
      }
    }
    if (uid() != identity) {
      throw StateError('Your login changed. Reopen the report.');
    }
    final result = await functions.httpsCallable('submitRepairReport').call({
      'reportId': reportId,
      'category': input.category,
      'description': input.description.trim(),
      'photoCount': input.photos.length,
    });
    if (result.data['submitted'] != true ||
        result.data['reportId'] != reportId) {
      throw StateError('The server did not confirm this report. Retry.');
    }
    return reportId;
  }

  @override
  Future<Uint8List> readPhoto(String issueId, String path) async {
    if (!RegExp(
      '^issues/${RegExp.escape(issueId)}/photos/[0-3]\$',
    ).hasMatch(path)) {
      throw StateError('Invalid private photo reference.');
    }
    final identity = uid();
    if (identity.isEmpty) throw StateError('Log in again to view this photo.');
    final result = await functions
        .httpsCallable(
          'readRepairPhoto',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call({'reportId': issueId, 'index': int.parse(path.split('/').last)});
    final data = result.data;
    if (uid() != identity ||
        data is! Map ||
        data['path'] != path ||
        data['size'] is! int ||
        data['size'] <= 0 ||
        data['size'] > DocumentFile.maximumBytes ||
        data['base64'] is! String ||
        (data['base64'] as String).length >
            ((DocumentFile.maximumBytes + 2) ~/ 3) * 4) {
      throw StateError('Photo unavailable.');
    }
    final bytes = base64Decode(data['base64'] as String);
    if (bytes.length != data['size']) throw StateError('Photo unavailable.');
    return bytes;
  }
}
