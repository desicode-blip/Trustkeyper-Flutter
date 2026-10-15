import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

enum DocumentKind {
  aadhaarFront('Aadhaar front'),
  aadhaarBack('Aadhaar back'),
  pan('PAN card'),
  bankProof('Bank proof');

  const DocumentKind(this.label);
  final String label;
}

class DocumentFailure implements Exception {
  const DocumentFailure(this.message);
  final String message;
}

class DocumentFile {
  DocumentFile({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String name;
  final Uint8List bytes;
  static const maximumBytes = 10 * 1024 * 1024;

  String get contentType {
    if (bytes.length >= 5 &&
        bytes[0] == 37 &&
        bytes[1] == 80 &&
        bytes[2] == 68 &&
        bytes[3] == 70 &&
        bytes[4] == 45) {
      return 'application/pdf';
    }
    if (bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'image/jpeg';
    }
    throw const DocumentFailure('Choose a JPG, PNG or PDF document.');
  }

  void validate() {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const DocumentFailure('Choose a non-empty file up to 10 MB.');
    }
    contentType;
  }
}

class PrivateDocument {
  const PrivateDocument({
    required this.name,
    required this.size,
    required this.contentType,
  });
  final String name;
  final int size;
  final String contentType;
}

abstract interface class PrivateDocumentStore {
  Future<PrivateDocument?> metadata(String path);
  Future<Uint8List> read(String path);
  Future<void> write(
    String path,
    DocumentFile file,
    void Function(double) progress,
  );
  Future<void> remove(String path);
}

class FirebasePrivateDocumentStore implements PrivateDocumentStore {
  FirebasePrivateDocumentStore(this.storage);
  final FirebaseStorage storage;
  @override
  Future<PrivateDocument?> metadata(String path) async {
    try {
      final metadata = await storage.ref(path).getMetadata();
      return PrivateDocument(
        name: metadata.customMetadata?['displayName'] ?? 'Document',
        size: metadata.size ?? 0,
        contentType: metadata.contentType ?? 'application/octet-stream',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    final bytes = await storage.ref(path).getData(DocumentFile.maximumBytes);
    if (bytes == null) throw const DocumentFailure('Document is unavailable.');
    return bytes;
  }

  @override
  Future<void> write(
    String path,
    DocumentFile file,
    void Function(double) progress,
  ) async {
    final task = storage
        .ref(path)
        .putData(
          file.bytes,
          SettableMetadata(
            contentType: file.contentType,
            cacheControl: 'private, no-store',
            customMetadata: {'displayName': file.name},
          ),
        );
    final subscription = task.snapshotEvents.listen((snapshot) {
      progress(
        snapshot.totalBytes == 0
            ? 0
            : snapshot.bytesTransferred / snapshot.totalBytes,
      );
    }, onError: (Object _) {});
    try {
      await task;
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> remove(String path) => storage.ref(path).delete();
}

class PrivateDocuments {
  PrivateDocuments({
    required this.draftId,
    required this.revision,
    required Set<String> partyIds,
    required this.store,
    required this.currentUid,
  }) : partyIds = Set.unmodifiable(partyIds) {
    ownerUid = currentUid();
    if (!_safe(draftId) ||
        revision < 1 ||
        partyIds.isEmpty ||
        partyIds.any((id) => !_safe(id))) {
      throw const DocumentFailure(
        'Save the private draft before adding documents.',
      );
    }
  }

  factory PrivateDocuments.firebase({
    required String draftId,
    required int revision,
    required Set<String> partyIds,
  }) => PrivateDocuments(
    draftId: draftId,
    revision: revision,
    partyIds: partyIds,
    store: FirebasePrivateDocumentStore(FirebaseStorage.instance),
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
  );

  final String draftId;
  final int revision;
  final Set<String> partyIds;
  final PrivateDocumentStore store;
  final String? Function() currentUid;
  late final String? ownerUid;

  static bool _safe(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);
  void _session() {
    if (ownerUid == null || !_safe(ownerUid!) || currentUid() != ownerUid) {
      throw const DocumentFailure(
        'Your session changed. Reopen this draft after logging in.',
      );
    }
  }

  String _path(String partyId, DocumentKind kind) {
    _session();
    if (!partyIds.contains(partyId)) {
      throw const DocumentFailure('This person is not in the saved draft.');
    }
    return 'users/$ownerUid/documents/drafts/$draftId/revisions/$revision/$partyId/${kind.name}/current';
  }

  Future<PrivateDocument?> metadata(String partyId, DocumentKind kind) async {
    final value = await store.metadata(_path(partyId, kind));
    _session();
    return value;
  }

  Future<DocumentFile> read(String partyId, DocumentKind kind) async {
    final path = _path(partyId, kind);
    final metadata = await store.metadata(path);
    if (metadata == null) {
      throw const DocumentFailure('Document is unavailable.');
    }
    _session();
    final bytes = await store.read(path);
    _session();
    final file = DocumentFile(name: metadata.name, bytes: bytes);
    file.validate();
    return file;
  }

  Future<void> upload(
    String partyId,
    DocumentKind kind,
    DocumentFile file,
    void Function(double) progress,
  ) async {
    file.validate();
    await store.write(_path(partyId, kind), file, (value) {
      if (currentUid() == ownerUid) progress(value.clamp(0, 1));
    });
    _session();
  }

  Future<void> remove(String partyId, DocumentKind kind) async {
    await store.remove(_path(partyId, kind));
    _session();
  }
}
