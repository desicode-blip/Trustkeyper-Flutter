import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/presentation/private_documents_screen.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/broker_document_links.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'agreement_draft_test.dart' show sampleDraft;
import 'document_request_test.dart' show RequestsFake, information;
import 'inline_documents_test.dart' show fixtureImage;
import 'private_documents_test.dart' show MemoryDocumentStore;
import 'support/document_preview_wait.dart';

class BundleRequests extends RequestsFake {
  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) =>
      Stream.value([
        DocumentRequestInfo({
          ...information(paper: 'all', status: 'added').data,
          'partyName': sampleDraft().owners.first.name,
          'phone': sampleDraft().owners.first.phone,
          'submission': {
            'addedByName': 'Test Owner',
            'files': {
              'aadhaarFront': {'name': 'TEST front.png'},
              'aadhaarBack': {'name': 'TEST back.png'},
              'pan': {'name': 'TEST pan.png'},
            },
            'bankDetails': {
              'method': 'upi',
              'upiId': 'testowner@okbank',
              'verified': false,
            },
          },
        }),
      ]);
}

void main() {
  testWidgets(
    'broker Add dialog really uploads both pages, views and deletes without sending a link',
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
      final requests = RequestsFake();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrivateDocumentsScreen(
                draft: draft,
                embedded: true,
                onlyPartyId: 'owner-1',
                requests: requests,
                documents: PrivateDocuments(
                  draftId: draft.id,
                  revision: draft.revision,
                  partyIds: {'owner-1'},
                  store: store,
                  currentUid: () => 'test-broker',
                ),
                pickFile: () async => fixtureImage(),
                takePhoto: () async => fixtureImage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add').first);
      await tester.pumpAndSettle();
      expect(find.text('Click photo'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      await tester.tap(find.text('Upload'));
      await waitForDocumentPreview(tester);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(find.text('Front added'), findsOneWidget);
      expect(store.files.length, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Back'));
      await waitForDocumentPreview(tester);
      await tester.tap(find.text('Upload private copy'));
      await tester.pumpAndSettle();
      expect(find.text('Back added'), findsOneWidget);
      expect(store.files.length, 2);
      await tester.tap(find.byTooltip('Delete Aadhaar back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(store.files.length, 1);
      expect(find.text('Back added'), findsNothing);
      expect(requests.creates, 0);
      expect(requests.records, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'whole-bundle receipt updates each paper and received bundle cannot be reminded',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BrokerDocumentLinks(
                requests: BundleRequests(),
                draftId: 'test',
                revision: 1,
                party: sampleDraft().owners.first,
                onAdd: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added by Test'), findsNWidgets(2));
      expect(find.text('Added · details added'), findsOneWidget);
      expect(find.text('Remind'), findsNothing);
      expect(find.text('Resend'), findsNothing);
      await tester.ensureVisible(find.byTooltip('See').last);
      await tester.tap(find.byTooltip('See').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('See bank details'));
      await tester.pumpAndSettle();
      expect(
        find.text('UPI ID: testowner@okbank\nNot bank verified'),
        findsOneWidget,
      );
      expect(find.text('Bank details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
