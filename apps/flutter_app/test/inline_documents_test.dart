import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_progress_repository.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_agreement_wizard.dart';

import 'agreement_draft_test.dart' show sampleDraft, DraftRepositoryFake;
import 'agreement_progress_test.dart' show MemoryProgressPersistence;
import 'private_documents_test.dart' show MemoryDocumentStore;
import 'support/document_preview_wait.dart';

DocumentFile fixtureImage() => DocumentFile(
  name: 'TEST-NOT-VALID.png',
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM0TPjPQApgIkk1w6gG4gATkergYFQDMYDkUAIA+V4BsKI64joAAAAASUVORK5CYII=',
  ),
);

void main() {
  testWidgets(
    'owner papers support immediate uploads, camera, view, replacement and removal',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryDocumentStore();
      final persistence = MemoryProgressPersistence();
      final progressRepository = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'test-broker',
      );
      final initial = AgreementProgress(
        draft: sampleDraft(),
        stage: 'ownerPapers',
        person: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            initialProgress: initial,
            repository: DraftRepositoryFake(),
            progressRepository: progressRepository,
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: store,
              currentUid: () => 'test-broker',
            ),
            pickDocument: () async => fixtureImage(),
            takeDocumentPhoto: () async => fixtureImage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not collected'), findsNothing);
      expect(find.text('Add document'), findsNWidgets(4));
      await tester.ensureVisible(find.text('Add document').first);
      await tester.tap(find.text('Add document').first);
      await waitForDocumentPreview(tester);
      await tester.pumpAndSettle();
      expect(store.files, isEmpty);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(
        store.files.keys.single,
        contains('/revisions/1/owner-1/aadhaarFront/'),
      );
      expect(find.textContaining('Uploaded · Not verified'), findsOneWidget);
      await tester.tap(find.text('View'));
      await waitForDocumentPreview(tester, upload: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Take photo').first);
      await tester.tap(find.text('Take photo').first);
      await waitForDocumentPreview(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(store.files.length, 1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(store.files, isEmpty);
      await tester.tap(find.text('Next: Owner 2'));
      await tester.pumpAndSettle();
      final saved = await progressRepository.load('test-draft');
      expect(saved.stage, 'owner');
      expect(saved.person, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving an edited identity invalidates old document slots even before Next',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryDocumentStore();
      final persistence = MemoryProgressPersistence();
      final progressRepository = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'test-broker',
      );
      PrivateDocuments documentsFor(AgreementDraft draft, {int? revision}) =>
          PrivateDocuments(
            draftId: draft.id,
            revision: revision ?? draft.revision,
            partyIds: [
              ...draft.owners,
              ...draft.tenants,
            ].map((party) => party.id).toSet(),
            store: store,
            currentUid: () => 'test-broker',
          );
      await documentsFor(
        sampleDraft(),
        revision: 1,
      ).upload('owner-1', DocumentKind.pan, fixtureImage(), (_) {});
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: sampleDraft(),
              stage: 'owner',
              person: 0,
            ),
            repository: DraftRepositoryFake(),
            progressRepository: progressRepository,
            documentFactory: documentsFor,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).at(1), '9000000005');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save progress'));
      await tester.tap(find.text('Save progress'));
      await tester.pumpAndSettle();
      final saved = await progressRepository.load('test-draft');
      expect(saved.draft.owners.first.id, isNot('owner-1'));
      expect(saved.draft.owners.first.phone, '+919000000005');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerAgreementWizard(
            initialProgress: saved,
            repository: DraftRepositoryFake(),
            progressRepository: progressRepository,
            documentFactory: documentsFor,
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add document'), findsNWidgets(4));
      expect(find.text('View'), findsNothing);
      expect(store.files.keys.single, contains('/owner-1/pan/'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant document uploads use the current tenant and pending revision',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryDocumentStore();
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: sampleDraft(),
              stage: 'tenantPapers',
              person: 1,
            ),
            repository: DraftRepositoryFake(),
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: store,
              currentUid: () => 'test-broker',
            ),
            pickDocument: () async => fixtureImage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add document').last);
      await tester.tap(find.text('Add document').last);
      await waitForDocumentPreview(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(
        store.files.keys.single,
        contains('/revisions/1/tenant-2/bankProof/'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed progress save keeps the person form and does not advance',
    (tester) async {
      final persistence = MemoryProgressPersistence()..failWrite = true;
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: sampleDraft(),
              stage: 'ownerCount',
              person: 0,
            ),
            repository: DraftRepositoryFake(),
            progressRepository: FirebaseAgreementProgressRepository(
              persistence: persistence,
              currentUid: () => 'broker',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('How many owners?'), findsOneWidget);
      expect(find.textContaining('Could not save progress'), findsOneWidget);
      expect(persistence.records, isEmpty);
    },
  );

  testWidgets(
    'editing a complete draft offers unchanged previous documents for explicit reviewed reuse',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryDocumentStore();
      final draft = AgreementDraft.fromMap('test-draft', {
        ...sampleDraft().toMap(),
        'revision': 1,
      });
      PrivateDocuments documentsFor(AgreementDraft value) => PrivateDocuments(
        draftId: value.id,
        revision: value.revision,
        partyIds: [
          ...value.owners,
          ...value.tenants,
        ].map((party) => party.id).toSet(),
        store: store,
        currentUid: () => 'test-broker',
      );
      await documentsFor(
        draft,
      ).upload('owner-1', DocumentKind.aadhaarFront, fixtureImage(), (_) {});
      await tester.pumpWidget(
        MaterialApp(
          home: BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: draft,
              stage: 'ownerPapers',
              person: 0,
            ),
            repository: DraftRepositoryFake(),
            documentFactory: documentsFor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review previous copy'), findsOneWidget);
      expect(store.files.length, 1);
      await tester.ensureVisible(find.text('Review previous copy'));
      await tester.tap(find.text('Review previous copy'));
      await waitForDocumentPreview(tester);
      await tester.pumpAndSettle();
      expect(find.text('Review before uploading'), findsOneWidget);
      expect(store.files.length, 1);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(store.files.length, 2);
      expect(
        store.files.keys,
        contains(contains('/revisions/2/owner-1/aadhaarFront/')),
      );
      expect(find.text('Review previous copy'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
