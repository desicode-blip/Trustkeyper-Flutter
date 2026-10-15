import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/document_requests/data/broker_paper_state.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/broker_document_links.dart';
import 'package:trustkeyper/ui_test_main.dart';
import 'agreement_draft_test.dart' show sampleDraft;
import 'document_request_test.dart' show RequestsFake;

DocumentRequestInfo request(
  RequestedPaper paper,
  String status, {
  String? channel = 'WhatsApp',
  Map<String, dynamic>? extra,
}) => DocumentRequestInfo({
  'requestId': 'request-${paper.name}',
  'partyId': 'owner-1',
  'partyName': 'Rajesh Kumar',
  'phone': '+919000000001',
  'brokerName': 'Rahul',
  'address': 'Phoenix Towers 402',
  'role': 'owner',
  'type': paper.name,
  'status': status,
  'version': 1,
  'channel': channel,
  'issuedAtMs': DateTime.now().millisecondsSinceEpoch - 3600000,
  'sharedAtMs': DateTime.now().millisecondsSinceEpoch - 120000,
  'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 86400000,
  'submission': {
    'uploadId': 'upload-${paper.name}',
    'addedByName': 'Rajesh Kumar',
    'files': {
      for (final kind in paper.slots)
        kind.name: {'path': 'private', 'name': 'TEST.png'},
    },
  },
  ...?extra,
});

class LiveRequests extends RequestsFake {
  final changes = StreamController<List<DocumentRequestInfo>>.broadcast();
  List<DocumentRequestInfo> items = [];
  String? lastAction;
  RequestedPaper? lastPaper;
  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) async* {
    yield items;
    yield* changes.stream;
  }

  void emit(List<DocumentRequestInfo> value) {
    items = value;
    changes.add(value);
  }

  @override
  Future<void> record(
    DocumentRequestInfo info,
    String action, {
    String? reason,
    String? channel,
    RequestedPaper? paper,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    lastAction = action;
    lastPaper = paper;
    items = [
      for (final item in items)
        if (item.id == info.id)
          DocumentRequestInfo({
            ...item.data,
            'closedPapers': {
              ...item.closedPapers,
              paper!.name: {
                'action': action,
                'atMs': DateTime.now().millisecondsSinceEpoch,
              },
            },
          })
        else
          item,
    ];
    changes.add(items);
  }
}

Future<void> showLinks(
  WidgetTester tester,
  LiveRequests fake, {
  ValueChanged<bool>? onCompletion,
  ValueChanged<RequestedPaper>? onAdd,
  Future<bool> Function(Uri)? openMessage,
  VoidCallback? onEditPerson,
  DateTime Function()? now,
}) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: BrokerDocumentLinks(
            now: now,
            requests: fake,
            draftId: 'test',
            revision: 1,
            party: AgreementParty(
              id: 'owner-1',
              name: 'Rajesh Kumar',
              phone: sampleDraft().owners.first.phone,
            ),
            onAdd: onAdd ?? (_) {},
            onCompletionChanged: onCompletion,
            openMessage: openMessage,
            onEditPerson: onEditPerson,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'resend countdown uses elapsed time and never needs a static production preview',
    (tester) async {
      var current = DateTime(2026, 10, 13, 12);
      final fake = LiveRequests()
        ..items = [
          request(
            RequestedPaper.aadhaar,
            'shared',
            extra: {
              'sharedAtMs': current.millisecondsSinceEpoch - 15000,
              'shareCount': 2,
              'expiresAtMs': current.millisecondsSinceEpoch + 86400000,
            },
          ),
        ];
      await showLinks(tester, fake, now: () => current);
      expect(find.text('0:45'), findsOneWidget);
      current = current.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:44'), findsOneWidget);
      current = current.add(const Duration(seconds: 44));
      await tester.pump(const Duration(seconds: 44));
      expect(find.byTooltip('Resend'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await fake.changes.close();
    },
  );
  testWidgets(
    'failed messaging shows recovery controls without claiming delivery',
    (tester) async {
      final fake = LiveRequests();
      var edits = 0;
      await showLinks(
        tester,
        fake,
        openMessage: (_) async => false,
        onEditPerson: () => edits++,
      );
      await tester.tap(find.byTooltip('Send link').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send link'));
      await tester.pumpAndSettle();
      expect(find.text('Link not sent'), findsOneWidget);
      expect(
        find.text('Could not open WhatsApp. Try another option.'),
        findsOneWidget,
      );
      expect(find.text('Send by SMS'), findsOneWidget);
      expect(find.text('Send by email'), findsOneWidget);
      expect(fake.lastAction, isNull);
      await tester.tap(find.text('Change number'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await fake.changes.close();
    },
  );

  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  test(
    'latest scoped request wins regardless of snapshot ordering; deleted bundle is not counted',
    () {
      final bundle = request(RequestedPaper.all, 'added');
      final newer = request(
        RequestedPaper.pan,
        'shared',
        extra: {'issuedAtMs': DateTime.now().millisecondsSinceEpoch},
      );
      for (final values in [
        [bundle, newer],
        [newer, bundle],
      ]) {
        final states = BrokerPaperState.resolve(values, {});
        expect(states[0].received, true);
        expect(states[1].waiting, true);
        expect(states[1].received, false);
        expect(states[2].received, true);
      }
      final removed = DocumentRequestInfo({
        ...bundle.data,
        'closedPapers': {
          'aadhaar': {
            'action': 'paper_deleted',
            'atMs': DateTime.now().millisecondsSinceEpoch,
          },
        },
      });
      final states = BrokerPaperState.resolve([removed], {});
      expect(states[0].deleted, true);
      expect(states[1].received, true);
      expect(states[2].received, true);
      expect(removed.slots, [DocumentKind.pan, DocumentKind.bankProof]);
    },
  );

  test(
    'partial Aadhaar is not done; expired submitted files remain viewable',
    () {
      final received = request(
        RequestedPaper.aadhaar,
        'added',
        extra: {'expiresAtMs': 1},
      );
      expect(BrokerPaperState.resolve([received], {}).first.done, true);
      final partial = BrokerPaperState.resolve([], {
        DocumentKind.aadhaarFront,
      }).first;
      expect(partial.done, false);
      expect(partial.label(DateTime.now()), 'Front added · add back');
    },
  );

  testWidgets(
    'waiting to one upload to all uploaded swaps actions and updates completion live',
    (tester) async {
      final fake = LiveRequests()
        ..items = [
          for (final paper in RequestedPaper.individual)
            request(paper, 'shared'),
        ];
      final completed = <bool>[];
      await showLinks(tester, fake, onCompletion: completed.add);
      expect(find.text('3 links sent on WhatsApp'), findsOneWidget);
      expect(find.text('Resend'), findsNWidgets(3));
      expect(find.text('See'), findsNothing);
      expect(find.textContaining('Delivery not confirmed'), findsNothing);
      expect(find.text('Send all documents link'), findsNothing);
      fake.emit([
        request(RequestedPaper.aadhaar, 'added'),
        request(RequestedPaper.pan, 'shared'),
        request(RequestedPaper.bank, 'shared'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('2 documents still waiting'), findsOneWidget);
      expect(find.text('Added by Rajesh'), findsOneWidget);
      expect(find.text('See'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      fake.emit([
        for (final paper in RequestedPaper.individual) request(paper, 'added'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('See'), findsNWidgets(3));
      expect(find.text('Resend'), findsNothing);
      expect(find.text('3 links sent on WhatsApp'), findsNothing);
      expect(completed, [false, true]);
      await tester.pumpWidget(const SizedBox());
      await fake.changes.close();
    },
  );

  testWidgets(
    'approved delete dialog cancels safely then removes only that paper',
    (tester) async {
      final fake = LiveRequests()
        ..items = [request(RequestedPaper.all, 'added')];
      await showLinks(tester, fake);
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete Aadhaar photo?'), findsOneWidget);
      await tester.tap(find.text('No, keep it'));
      await tester.pumpAndSettle();
      expect(fake.lastAction, null);
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, delete'));
      await tester.pumpAndSettle();
      expect(fake.lastAction, 'paper_deleted');
      expect(fake.lastPaper, RequestedPaper.aadhaar);
      expect(find.text('Deleted · add again'), findsOneWidget);
      expect(find.text('See'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      await fake.changes.close();
    },
  );

  testWidgets(
    'takeover requires approved confirmation and cancel never opens a picker',
    (tester) async {
      final fake = LiveRequests()
        ..items = [request(RequestedPaper.pan, 'shared')];
      final picked = <RequestedPaper>[];
      await showLinks(tester, fake, onAdd: picked.add);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('broker-paper-pan')),
          matching: find.byTooltip('Add'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add PAN yourself?'), findsOneWidget);
      await tester.tap(find.textContaining('No, wait for'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(fake.lastAction, null);
      await tester.pumpWidget(const SizedBox());
      await fake.changes.close();
    },
  );

  for (final role in ['owner', 'tenant']) {
    for (final width in [320.0, 390.0]) {
      testWidgets('narrow $role uploaded controls at $width', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = UiTestApp(documentNow: () => DateTime(2026, 10, 13, 12));
        await tester.pumpWidget(app);
        app.router.go('/ui-test/broker-documents/$role/complete');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('See'), findsNWidgets(role == 'tenant' ? 4 : 3));
        await tester.pumpWidget(const SizedBox());
        app.router.dispose();
      });
    }
    for (final transition in ['partial', 'complete']) {
      testWidgets('approved $role live $transition notification', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(440, 956);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        debugDisableShadows = false;
        final app = UiTestApp(documentNow: () => DateTime(2026, 10, 13, 12));
        await tester.pumpWidget(app);
        app.router.go('/ui-test/broker-documents/$role/live-$transition');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(
            transition == 'complete'
                ? 'All documents added for'
                : 'added Aadhaar card',
          ),
          findsOneWidget,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/broker-documents-$role-live-$transition.png',
          ),
        );
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        app.router.dispose();
      });
    }
    for (final status in [
      'empty',
      'sent',
      'seen',
      'partial',
      'complete',
      'cooldown',
      'problems',
      'deleted',
    ]) {
      testWidgets('approved $role $status at 440x956', (tester) async {
        tester.view.physicalSize = const Size(440, 956);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        final app = UiTestApp(documentNow: () => DateTime(2026, 10, 13, 12));
        await tester.pumpWidget(app);
        app.router.go('/ui-test/broker-documents/$role/$status');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text(role == 'owner' ? 'Next: Owner 2' : 'Next: Tenant 2'),
          findsOneWidget,
        );
        if (status == 'complete') {
          expect(find.text('All done'), findsOneWidget);
          expect(find.text('See'), findsNWidgets(role == 'tenant' ? 4 : 3));
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/broker-documents-$role-$status.png'),
        );
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox());
        app.router.dispose();
      });
    }
  }
}
