import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/core/testing/broker_updates_fixture.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft_repository.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_progress_repository.dart';
import 'package:trustkeyper/src/features/broker/data/broker_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_agreement_wizard.dart';
import 'package:trustkeyper/src/core/testing/document_request_fixture.dart';
import 'package:trustkeyper/src/features/broker/data/broker_document_context.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_agreements_list.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_updates_screen.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_document_review_screen.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'agreement_draft_test.dart' show sampleDraft, DraftRepositoryFake;
import 'agreement_progress_test.dart'
    show checkpoint, MemoryProgressPersistence;
import 'private_documents_test.dart' show MemoryDocumentStore;

DocumentRequestInfo request({
  String role = 'owner',
  String partyId = 'owner-2',
  int revision = 1,
  String status = 'added',
}) {
  final draft = sampleDraft();
  final person = (role == 'owner' ? draft.owners : draft.tenants).firstWhere(
    (party) => party.id == partyId,
  );
  return DocumentRequestInfo({
    'requestId': 'a' * 64,
    'draftId': draft.id,
    'revision': revision,
    'partyId': partyId,
    'role': role,
    'partyName': person.name,
    'phone': person.phone,
    'email': person.email,
    'status': status,
    'type': 'all',
  });
}

void main() {
  testWidgets('an upload update resumes the approved exact-person step once', (
    tester,
  ) async {
    final progress = checkpoint(stage: 'money');
    final value = resolveBrokerDocumentContext(request(), progress: progress);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BrokerDocumentReviewScreen(
          requestId: 'a' * 64,
          loadContext: () async => value,
          onResume: opened.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(opened, [value.resumePath]);
    expect(Uri.parse(opened.single).queryParameters, {
      'role': 'owner',
      'partyId': 'owner-2',
    });
    await tester.pump();
    expect(opened.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'exact-person reopening renders the matching owner or tenant documents and saves safely',
    (tester) async {
      final persistence = MemoryProgressPersistence();
      final repository = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'broker',
      );
      await repository.save(checkpoint(stage: 'money'));
      for (final target in [
        ('owner', 'owner-2', 'Test Owner Two'),
        ('tenant', 'tenant-2', 'Test Tenant Two'),
      ]) {
        final loaded = await repository.load('test-draft');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: BrokerAgreementWizard(
              initialProgress: loaded,
              initialPartyRole: target.$1,
              initialPartyId: target.$2,
              repository: DraftRepositoryFake(),
              progressRepository: repository,
              documentRequests: OfflineDocumentRequests(),
              documentFactory: (draft) => PrivateDocuments(
                draftId: draft.id,
                revision: draft.revision,
                partyIds: [
                  ...draft.owners,
                  ...draft.tenants,
                ].map((party) => party.id).toSet(),
                store: MemoryDocumentStore(),
                currentUid: () => 'broker',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(target.$3), findsOneWidget);
        expect(find.text('Aadhaar card'), findsOneWidget);
        await tester.tap(find.byTooltip('Send link').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
        await tester.pumpAndSettle();
        final saved = await repository.load('test-draft');
        expect(saved.stage, '${target.$1}Papers');
        expect(saved.person, 1);
        expect(saved.draft.id, 'test-draft');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'draft deletion requires confirmation and removes the versioned saved flow',
    (tester) async {
      final progress = OfflineBrokerProgress();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrokerAgreementsList(
              agreements: Stream.value([]),
              approvalPending: false,
              progressRepository: progress,
              itemBuilder: (_, agreement) => Text(agreement.property),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete draft'));
      await tester.pumpAndSettle();
      expect(progress.saved, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(progress.saved, isNull);
      expect(find.text('No agreements yet'), findsOneWidget);
    },
  );
  testWidgets(
    'signed and in-progress filters separate real signed copies and hide obsolete draft duplicates',
    (tester) async {
      final progress = OfflineBrokerProgress();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrokerAgreementsList(
              agreements: Stream.value([
                BrokerAgreementSummary(
                  id: progress.saved!.draft.id,
                  property: 'Signed property',
                  people: 'TEST',
                  status: 'signed',
                  monthlyRentPaise: 10000,
                  updatedAt: null,
                  revision: 1,
                  copyMode: 'externally_signed',
                ),
                const BrokerAgreementSummary(
                  id: 'progress',
                  property: 'Waiting property',
                  people: 'TEST',
                  status: 'request_received',
                  monthlyRentPaise: 10000,
                  updatedAt: null,
                ),
              ]),
              approvalPending: false,
              progressRepository: progress,
              itemBuilder: (_, agreement) => Text(agreement.property),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsNothing);
      await tester.tap(find.text('Signed'));
      await tester.pumpAndSettle();
      expect(find.text('Signed property'), findsOneWidget);
      expect(find.text('Waiting property'), findsNothing);
      await tester.tap(find.text('In progress'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting property'), findsOneWidget);
      expect(find.text('Signed property'), findsNothing);
    },
  );
  test(
    're-entry restores exact owner or tenant even when saved flow is at a different stage',
    () {
      for (final target in [('owner', 'owner-2'), ('tenant', 'tenant-2')]) {
        final value = resolveBrokerDocumentContext(
          request(role: target.$1, partyId: target.$2),
          progress: checkpoint(stage: 'money'),
        );
        expect(value.draft.revision, 1);
        expect(value.progress!.stage, 'money');
        expect(value.progress!.inputs['rent'], '');
        expect(Uri.parse(value.resumePath).queryParameters, {
          'role': target.$1,
          'partyId': target.$2,
        });
      }
    },
  );
  test(
    'notification remains reviewable after complete draft replaces progress',
    () async {
      final completed = AgreementDraft.fromMap(sampleDraft().id, {
        ...sampleDraft().toMap(),
        'revision': 1,
      });
      final progress = OfflineBrokerProgress()..saved = null;
      final value = await loadBrokerDocumentContext(
        request: request(),
        progressRepository: progress,
        loadCompleted: (_) async => completed,
      );
      expect(value.progress, isNull);
      expect(value.resumePath, contains('/broker/draft/test-draft'));
    },
  );
  test(
    'deleted, revoked, newer revision and changed party cannot reopen old private data',
    () {
      for (final received in [
        request(status: 'revoked'),
        request(revision: 3),
      ]) {
        expect(
          () => resolveBrokerDocumentContext(received, progress: checkpoint()),
          throwsA(isA<DocumentFailure>()),
        );
      }
      final changed = request();
      expect(
        () => resolveBrokerDocumentContext(
          DocumentRequestInfo({...changed.data, 'phone': '+919000000099'}),
          progress: checkpoint(),
        ),
        throwsA(isA<DocumentFailure>()),
      );
      expect(
        () => resolveBrokerDocumentContext(changed),
        throwsA(isA<DocumentFailure>()),
      );
    },
  );
  test(
    'unavailable progress is not mistaken for a deleted draft and cannot fall back silently',
    () async {
      final progress = OfflineBrokerProgress();
      await expectLater(
        loadBrokerDocumentContext(
          request: request(),
          progressRepository: progress,
          loadCompleted: (_) async =>
              throw const DraftFailure('Server unavailable'),
        ),
        throwsA(isA<DraftFailure>()),
      );
    },
  );
  testWidgets(
    'upload updates mark read before opening and retain read state on screen reopen',
    (tester) async {
      final repository = OfflineBrokerUpdates();
      String? opened;
      Widget page() => MaterialApp(
        theme: AppTheme.light,
        home: BrokerUpdatesScreen(
          repository: repository,
          now: () => DateTime(2026, 10, 11, 20),
          onOpen: (update) => opened = update.requestId,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      await tester.tap(find.text('TEST Rajesh added documents'));
      await tester.pumpAndSettle();
      expect(opened, 'c' * 64);
      expect(repository.items.first.unread, false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNothing);
    },
  );
  testWidgets('failed read receipt does not claim success or navigate', (
    tester,
  ) async {
    final repository = OfflineBrokerUpdates()..failRead = true;
    bool opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BrokerUpdatesScreen(
          repository: repository,
          onOpen: (_) => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST Rajesh added documents'));
    await tester.pumpAndSettle();
    expect(opened, false);
    expect(repository.items.first.unread, true);
    expect(
      find.text('Could not open this update. Check your connection and retry.'),
      findsOneWidget,
    );
  });
  for (final size in [
    const Size(440, 956),
    const Size(363.4, 812),
    const Size(320, 640),
  ]) {
    for (final updates in [true, false]) {
      testWidgets(
        '${updates ? 'updates' : 'drafts'} follows approved layout at ${size.width}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final progress = OfflineBrokerProgress();
          final notifications = OfflineBrokerUpdates();
          final boundary = GlobalKey();
          final font = FontLoader('Roboto');
          font.addFont(rootBundle.load('assets/fonts/Roboto-400.ttf'));
          font.addFont(rootBundle.load('assets/fonts/Roboto-600.ttf'));
          font.addFont(rootBundle.load('assets/fonts/Roboto-700.ttf'));
          await font.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: RepaintBoundary(
                key: boundary,
                child: updates
                    ? BrokerUpdatesScreen(
                        repository: notifications,
                        now: () => DateTime(2026, 10, 11, 20),
                        onOpen: (_) {},
                      )
                    : Scaffold(
                        body: SafeArea(
                          child: BrokerAgreementsList(
                            agreements: Stream.value([]),
                            approvalPending: false,
                            progressRepository: progress,
                            updates: notifications,
                            itemBuilder: (_, agreement) =>
                                Text(agreement.property),
                          ),
                        ),
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!updates) {
            final rows = [
              for (final label in ['All', 'In progress', 'Signed', 'Drafts'])
                tester.getTopLeft(find.widgetWithText(ChoiceChip, label)).dy,
            ];
            expect(rows.every((row) => (row - rows.first).abs() < 1), isTrue);
            await tester.tap(find.text('Drafts'));
            await tester.pumpAndSettle();
            expect(find.text('Stopped at Tenant documents'), findsOneWidget);
            await tester.tap(find.byTooltip('Delete draft'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
            expect(progress.saved, isNotNull);
          }
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('WRITE_UI_CAPTURES') &&
              size.width == 440) {
            await tester.runAsync(() async {
              final capture =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await capture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '../../output/ui-audit/native/build33-${updates ? 'updates' : 'drafts'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              capture.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
