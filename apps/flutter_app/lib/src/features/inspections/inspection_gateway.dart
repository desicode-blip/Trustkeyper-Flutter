import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../broker/data/private_documents.dart';

class InspectionList {
  InspectionList(this.data);
  final Map<String, dynamic> data;
  String get address => data['address'] as String? ?? '';
  String get role => data['actorRole'] as String? ?? '';
  bool get canCapture => data['canCapture'] == true;
  List<Map<String, dynamic>> get checks => (data['checks'] as List? ?? [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList();
}

abstract interface class InspectionGateway {
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? role,
  ]);
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input);
  Future<void> save(Map<String, dynamic> grant, DocumentFile file);
  Future<DocumentFile> photo(String propertyId, String checkId);
  Future<void> review(Map<String, dynamic> input);
}

class FirebaseInspectionGateway implements InspectionGateway {
  FirebaseInspectionGateway({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseFirestore? database,
    FirebaseStorage? storage,
  }) : auth = auth ?? FirebaseAuth.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       database = database ?? FirebaseFirestore.instance,
       storage = storage ?? FirebaseStorage.instance;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  final FirebaseFirestore database;
  final FirebaseStorage storage;
  final updates = StreamController<void>.broadcast();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in again to open photo checks.');
    final response = await functions.httpsCallable(name).call(data);
    if (uid != auth.currentUser?.uid) {
      throw StateError('Your login changed. Reopen photo checks.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Stream<InspectionList> watch(
    String propertyId,
    String? agreementId, [
    String? role,
  ]) {
    late StreamController<InspectionList> controller;
    StreamSubscription<User?>? identities;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profiles;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? agreements;
    StreamSubscription<void>? changes;
    Timer? timer;
    var generation = 0;
    String? activeUid;
    Future<void> refresh() async {
      final request = ++generation;
      try {
        final data = await _call('listPropertyInspections', {
          'propertyId': propertyId,
          'agreementId': ?agreementId,
          'role': ?role,
        });
        if (!controller.isClosed && generation == request) {
          controller.add(InspectionList(data));
        }
      } catch (error, stack) {
        if (!controller.isClosed && generation == request) {
          controller.addError(error, stack);
        }
      }
    }

    controller = StreamController<InspectionList>(
      onListen: () {
        identities = auth.authStateChanges().listen((user) {
          ++generation;
          profiles?.cancel();
          agreements?.cancel();
          if (activeUid != null && activeUid != user?.uid) {
            controller.addError(
              StateError('Your login changed. Reopen photo checks.'),
            );
          }
          activeUid = user?.uid;
          if (user == null) {
            controller.addError(
              StateError('Log in again to open photo checks.'),
            );
            return;
          }
          profiles = database
              .collection('users')
              .doc(user.uid)
              .snapshots()
              .listen(
                (_) => refresh(),
                onError: (Object error) {
                  ++generation;
                  if (!controller.isClosed) controller.addError(error);
                },
              );
          if (agreementId != null) {
            agreements = database
                .collection('agreements')
                .doc(agreementId)
                .snapshots()
                .listen(
                  (_) => refresh(),
                  onError: (Object error) {
                    ++generation;
                    if (!controller.isClosed) controller.addError(error);
                  },
                );
          }
          refresh();
        });
        changes = updates.stream.listen((_) => refresh());
        timer = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
      },
      onCancel: () async {
        ++generation;
        timer?.cancel();
        await identities?.cancel();
        await profiles?.cancel();
        await agreements?.cancel();
        await changes?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Map<String, dynamic>> begin(Map<String, dynamic> input) async => {
    ...await _call('beginPropertyInspection', input),
    'sessionUid': auth.currentUser?.uid,
    'request': input,
  };
  @override
  Future<void> save(Map<String, dynamic> grant, DocumentFile file) async {
    file.validate();
    if (!file.contentType.startsWith('image/')) {
      throw StateError('Take a camera photo, not a PDF.');
    }
    final uid = grant['sessionUid'];
    if (uid == null || auth.currentUser?.uid != uid) {
      throw StateError('Your login changed. Take the photo again.');
    }
    final refreshed = await _call(
      'beginPropertyInspection',
      Map<String, dynamic>.from(grant['request'] as Map),
    );
    if (refreshed['submitted'] != true && grant['uploaded'] != true) {
      await storage
          .ref(grant['path'] as String)
          .putData(
            file.bytes,
            SettableMetadata(
              contentType: file.contentType,
              cacheControl: 'private, no-store',
            ),
          );
      grant['uploaded'] = true;
    }
    if (auth.currentUser?.uid != uid) {
      throw StateError('Your login changed. Reopen photo checks.');
    }
    await _call('submitPropertyInspection', {'checkId': grant['checkId']});
    updates.add(null);
  }

  @override
  Future<DocumentFile> photo(String propertyId, String checkId) async {
    final data = await _call('readPropertyInspectionPhoto', {
      'propertyId': propertyId,
      'checkId': checkId,
    });
    final size = data['size'];
    final encoded = data['base64'];
    if (size is! int ||
        size <= 0 ||
        size > DocumentFile.maximumBytes ||
        encoded is! String ||
        encoded.length > ((DocumentFile.maximumBytes + 2) ~/ 3) * 4) {
      throw StateError('This photo is unavailable.');
    }
    final bytes = Uint8List.fromList(base64Decode(encoded));
    if (bytes.length != size) {
      throw StateError('This photo could not be confirmed.');
    }
    final file = DocumentFile(name: 'Property photo.png', bytes: bytes);
    file.validate();
    return file;
  }

  @override
  Future<void> review(Map<String, dynamic> input) async {
    await _call('reviewPropertyInspection', input);
    updates.add(null);
  }
}
