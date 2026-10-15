import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/document_fixture.dart';
import 'package:trustkeyper/src/features/broker/data/private_pdf_reference.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/presentation/private_documents_screen.dart';

import 'agreement_draft_test.dart' show sampleDraft;
import 'support/document_preview_wait.dart';

class MemoryDocumentStore implements PrivateDocumentStore {
  final files = <String, DocumentFile>{};
  bool failWrite = false;
  bool failRead = false;
  VoidCallback? afterRead;
  @override
  Future<PrivateDocument?> metadata(String path) async {
    if (failRead) throw StateError('offline');
    final file = files[path];
    afterRead?.call();
    return file == null
        ? null
        : PrivateDocument(
            name: file.name,
            size: file.bytes.length,
            contentType: file.contentType,
          );
  }

  @override
  Future<Uint8List> read(String path) async => files[path]!.bytes;
  @override
  Future<void> write(
    String path,
    DocumentFile file,
    void Function(double) progress,
  ) async {
    if (failWrite) throw StateError('offline');
    progress(0.5);
    files[path] = file;
    progress(1);
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

DocumentFile pdf([String name = 'test.pdf']) => DocumentFile(
  name: name,
  bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\nTest fixture\n%%EOF')),
);

void main() {
  late MemoryDocumentStore store;
  late PrivateDocuments documents;
  String? uid;
  setUp(() {
    uid = 'broker-test';
    store = MemoryDocumentStore();
    documents = PrivateDocuments(
      draftId: 'draft-test',
      revision: 1,
      partyIds: {'owner-1', 'owner-2', 'tenant-1', 'tenant-2'},
      store: store,
      currentUid: () => uid,
    );
  });

  test('validates bytes instead of trusting extension and MIME', () {
    expect(pdf().contentType, 'application/pdf');
    expect(
      DocumentFile(
        name: 'wrong.exe',
        bytes: Uint8List.fromList([255, 216, 255, 0]),
      ).contentType,
      'image/jpeg',
    );
    expect(
      DocumentFile(
        name: 'test.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ).contentType,
      'image/png',
    );
    expect(
      () => DocumentFile(
        name: 'fake.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      ).validate(),
      throwsA(isA<DocumentFailure>()),
    );
    expect(
      () => DocumentFile(name: 'empty.pdf', bytes: Uint8List(0)).validate(),
      throwsA(isA<DocumentFailure>()),
    );
  });
  test('10 MB boundary and immutable copy', () {
    final input = Uint8List(DocumentFile.maximumBytes);
    input.setRange(0, 5, utf8.encode('%PDF-'));
    final file = DocumentFile(name: 'large.pdf', bytes: input);
    file.validate();
    input[0] = 0;
    expect(file.bytes[0], 37);
    expect(() => file.bytes[0] = 0, throwsUnsupportedError);
    expect(
      () => DocumentFile(
        name: 'large.pdf',
        bytes: Uint8List(DocumentFile.maximumBytes + 1),
      ).validate(),
      throwsA(isA<DocumentFailure>()),
    );
  });
  test(
    'scopes every document by user, draft, revision, person and side',
    () async {
      final progress = <double>[];
      await documents.upload(
        'owner-1',
        DocumentKind.aadhaarFront,
        pdf(),
        progress.add,
      );
      await documents.upload(
        'owner-1',
        DocumentKind.aadhaarBack,
        pdf('back.pdf'),
        (_) {},
      );
      expect(store.files.length, 2);
      expect(
        store.files.keys.first,
        'users/broker-test/documents/drafts/draft-test/revisions/1/owner-1/aadhaarFront/current',
      );
      expect(progress, [0.5, 1]);
      expect(
        await documents.metadata('owner-2', DocumentKind.aadhaarFront),
        isNull,
      );
      expect(
        (await documents.read('owner-1', DocumentKind.aadhaarBack)).name,
        'back.pdf',
      );
      final revised = PrivateDocuments(
        draftId: 'draft-test',
        revision: 2,
        partyIds: {'owner-1'},
        store: store,
        currentUid: () => uid,
      );
      expect(
        await revised.metadata('owner-1', DocumentKind.aadhaarFront),
        isNull,
      );
    },
  );
  test('replacement and deletion leave other slots untouched', () async {
    await documents.upload('owner-1', DocumentKind.pan, pdf(), (_) {});
    await documents.upload(
      'owner-1',
      DocumentKind.bankProof,
      pdf('bank.pdf'),
      (_) {},
    );
    await documents.upload(
      'owner-1',
      DocumentKind.pan,
      pdf('corrected.pdf'),
      (_) {},
    );
    expect(
      (await documents.metadata('owner-1', DocumentKind.pan))!.name,
      'corrected.pdf',
    );
    await documents.remove('owner-1', DocumentKind.pan);
    expect(await documents.metadata('owner-1', DocumentKind.pan), isNull);
    expect(
      (await documents.metadata('owner-1', DocumentKind.bankProof))!.name,
      'bank.pdf',
    );
  });
  test(
    'unknown person, traversal, unsaved revision and session rejected',
    () async {
      expect(
        () => PrivateDocuments(
          draftId: '../draft',
          revision: 1,
          partyIds: {'owner-1'},
          store: store,
          currentUid: () => uid,
        ),
        throwsA(isA<DocumentFailure>()),
      );
      expect(
        () => PrivateDocuments(
          draftId: 'draft',
          revision: 0,
          partyIds: {'owner-1'},
          store: store,
          currentUid: () => uid,
        ),
        throwsA(isA<DocumentFailure>()),
      );
      await expectLater(
        documents.upload('intruder', DocumentKind.pan, pdf(), (_) {}),
        throwsA(isA<DocumentFailure>()),
      );
      uid = 'another-user';
      await expectLater(
        documents.upload('owner-1', DocumentKind.pan, pdf(), (_) {}),
        throwsA(isA<DocumentFailure>()),
      );
      expect(store.files, isEmpty);
    },
  );
  test('changed session during load does not display metadata', () async {
    store.afterRead = () => uid = null;
    await expectLater(
      documents.metadata('owner-1', DocumentKind.pan),
      throwsA(isA<DocumentFailure>()),
    );
  });
  test('failed upload preserves current copy for retry', () async {
    await documents.upload('owner-1', DocumentKind.pan, pdf(), (_) {});
    store.failWrite = true;
    await expectLater(
      documents.upload('owner-1', DocumentKind.pan, pdf('new.pdf'), (_) {}),
      throwsStateError,
    );
    expect(
      (await documents.metadata('owner-1', DocumentKind.pan))!.name,
      'test.pdf',
    );
  });
  testWidgets(
    'private upload, preview and confirmed deletion work without Firebase',
    (tester) async {
      tester.view.physicalSize = const Size(440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PrivateDocumentsScreen(
            draft: sampleDraft(),
            documents: documents,
            pickFile: () async => DocumentFile(
              name: 'test.png',
              bytes: base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM0TPjPQApgIkk1w6gG4gATkergYFQDMYDkUAIA+V4BsKI64joAAAAASUVORK5CYII=',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add document').first);
      await waitForDocumentPreview(tester);
      await tester.pumpAndSettle();
      expect(find.text('Review before uploading'), findsOneWidget);
      expect(store.files, isEmpty);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(store.files.length, 1);
      expect(find.textContaining('Uploaded · Not verified'), findsOneWidget);
      await tester.tap(find.text('View'));
      await waitForDocumentPreview(tester, upload: false);
      await tester.pumpAndSettle();
      expect(find.text('Private document'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.files.length, 1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(store.files, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('loading error is recoverable and never presented as absence', (
    tester,
  ) async {
    store.failRead = true;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateDocumentsScreen(
          draft: sampleDraft(),
          documents: documents,
          pickFile: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Document operation failed'), findsOneWidget);
    store.failRead = false;
    await tester.tap(find.text('Retry loading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Document operation failed'), findsNothing);
  });

  test('same-name private PDFs never share the document viewer cache', () {
    final file = DocumentFile(name: 'document.pdf', bytes: testDocumentPdf());
    final first = privatePdfReference(file);
    final second = privatePdfReference(file);
    expect(first.key, isNot(second.key));
    expect(first.data, file.bytes);
    expect(first.useProgressiveLoading, isFalse);
  });

  test(
    'private PDF reference rejects mislabeled non-PDF data before opening',
    () {
      final file = DocumentFile(
        name: 'document.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(() => privatePdfReference(file), throwsA(isA<DocumentFailure>()));
    },
  );
}
