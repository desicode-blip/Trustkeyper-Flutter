import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/presentation/private_documents_screen.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'package:trustkeyper/src/features/document_requests/data/recipient_document_gateway.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/recipient_document_screen.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/broker_document_links.dart';

import 'agreement_draft_test.dart' show sampleDraft;
import 'inline_documents_test.dart' show fixtureImage;
import 'support/document_preview_wait.dart';

final token = '${List.filled(64, 'a').join()}.${List.filled(43, 'b').join()}';
DocumentRequestInfo information({
  bool verified = false,
  String status = 'created',
  String paper = 'aadhaar',
}) => DocumentRequestInfo({
  'requestId': 'test',
  'type': paper,
  'status': status,
  'verified': verified,
  'partyId': 'owner-1',
  'phone': '+911111111111',
  'partyName': 'Test Owner',
  'brokerName': 'Test Broker',
  'address': 'TEST ONLY Property 101',
  'role': 'owner',
  'version': 1,
  'expiresAtMs': DateTime.now()
      .add(const Duration(days: 7))
      .millisecondsSinceEpoch,
});

class RecipientFake implements RecipientDocumentGateway {
  bool verified = false;
  bool failVerification = false;
  bool failSubmit = false;
  bool received = false;
  String paper = 'aadhaar';
  int submissions = 0;
  int otpRequests = 0;
  String? requestedPhone;
  Set<DocumentKind>? sent;
  Map<String, dynamic>? sentBank;
  @override
  Future<DocumentRequestInfo> read(String token) async => information(
    verified: verified,
    status: received ? 'added' : 'seen',
    paper: paper,
  );
  @override
  Future<bool> requestOtp(String phone) async {
    otpRequests++;
    requestedPhone = phone;
    return false;
  }

  @override
  Future<void> verifyOtp(String code) async {
    if (failVerification) {
      throw const DocumentFailure('That code is incorrect. Try again.');
    }
    verified = true;
  }

  @override
  Future<void> signOut() async {
    verified = false;
  }

  @override
  Future<DocumentRequestInfo> submit(
    String token,
    Map<DocumentKind, DocumentFile> files,
    void Function(double) progress, {
    Map<String, dynamic>? bankDetails,
    Map<String, dynamic>? linkedInDetails,
  }) async {
    submissions++;
    sent = files.keys.toSet();
    sentBank = bankDetails;
    if (failSubmit) {
      throw const DocumentFailure('Temporary send failure. Retry.');
    }
    progress(1);
    received = true;
    return information(verified: verified, status: 'added', paper: paper);
  }
}

class RequestsFake implements DocumentRequests {
  int creates = 0;
  int records = 0;
  @override
  Stream<List<DocumentRequestInfo>> watch(String draftId, int revision) =>
      Stream.value([]);
  @override
  Future<IssuedDocumentLink> create({
    required String draftId,
    required int revision,
    required String partyId,
    required RequestedPaper paper,
    bool remind = false,
  }) async {
    creates++;
    return IssuedDocumentLink(
      token,
      information(verified: true, paper: paper.name),
    );
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
    records++;
  }

  @override
  Future<DocumentFile> readFile(Map<String, dynamic> file) async =>
      fixtureImage();
}

Future<void> open(
  WidgetTester tester,
  RecipientFake fake, {
  String? requestToken,
}) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RecipientDocumentScreen(
        token: requestToken ?? token,
        gateway: fake,
        pickFile: (_) async => fixtureImage(),
        reviewFile: (_) async => true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (fake.verified && !fake.received) {
    await tester.tap(find.text('Continue with +911111111111'));
    await tester.pumpAndSettle();
  }
}

FilledButton send(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Send to Test'),
);
Future<void> chooseRecipientFile(
  WidgetTester tester, {
  bool stayOnDetails = false,
}) async {
  if (find.text('Photo').evaluate().isNotEmpty ||
      find.text('Cheque').evaluate().isNotEmpty) {
    await tester.tap(
      find.text('Photo').evaluate().isNotEmpty
          ? find.text('Photo').first
          : find.text('Cheque').first,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.text('Upload cancelled cheque').evaluate().isNotEmpty
        ? find.text('Upload cancelled cheque')
        : find.text('Have a PDF? Choose a file instead'),
  );
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Save');
  if (!stayOnDetails &&
      save.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(save).onPressed != null) {
    await tester.tap(save);
    await tester.pumpAndSettle();
  } else if (!stayOnDetails &&
      find.byTooltip('Back to documents').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Back to documents'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'recipient review confirms selection without claiming an upload',
    (tester) async {
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  accepted = await reviewPrivateDocument(
                    context,
                    fixtureImage(),
                    upload: true,
                    selectionOnly: true,
                  );
                },
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open review'));
      await waitForDocumentPreview(tester, selectionOnly: true);
      expect(find.text('Review selected file'), findsOneWidget);
      expect(find.textContaining('Nothing is sent'), findsOneWidget);
      expect(find.text('Upload private copy'), findsNothing);
      expect(accepted, isNull);
      await tester.tap(find.text('Use this file'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    },
  );
  test(
    'configured test-phone contacts can be entered without bypassing verification',
    () {
      for (final phone in ['+911111111111', '+912222222222']) {
        final party = AgreementParty(
          id: 'test-person',
          name: 'Test Person',
          phone: phone,
        );
        expect(party.validationError, isNull);
        expect(information().verified, isFalse);
      }
    },
  );
  test(
    'private URL keeps capability in fragment rather than request query',
    () {
      final url = IssuedDocumentLink(token, information()).url;
      expect(url.host, 'trustkeyper.web.app');
      expect(url.query, isEmpty);
      expect(Uri.parse(url.fragment).queryParameters['token'], token);
    },
  );
  testWidgets(
    'invitation requires real gateway OTP proof before showing upload controls',
    (tester) async {
      final fake = RecipientFake();
      await open(tester, fake);
      expect(find.text('Upload documents'), findsNothing);
      expect(find.textContaining('asked for your documents'), findsOneWidget);
      await tester.tap(find.text('Continue with +911111111111'));
      await tester.pumpAndSettle();
      expect(fake.requestedPhone, '+911111111111');
      await tester.enterText(find.byType(TextField), '000000');
      fake.failVerification = true;
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(find.textContaining('incorrect'), findsOneWidget);
      expect(find.text('Upload documents'), findsNothing);
      fake.failVerification = false;
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(find.text('Upload documents'), findsOneWidget);
      expect(send(tester).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Aadhaar needs both pages; failures do not report sent; confirmed retry sends only requested paper',
    (tester) async {
      final fake = RecipientFake()..verified = true;
      await open(tester, fake);
      await chooseRecipientFile(tester);
      expect(send(tester).onPressed, isNull);
      expect(fake.submissions, 0);
      await chooseRecipientFile(tester);
      expect(send(tester).onPressed, isNotNull);
      fake.failSubmit = true;
      await tester.tap(find.text('Send to Test'));
      await tester.pumpAndSettle();
      expect(find.text('Aadhaar card sent'), findsNothing);
      expect(find.text('Temporary send failure. Retry.'), findsOneWidget);
      fake.failSubmit = false;
      await tester.tap(find.text('Send to Test'));
      await tester.pumpAndSettle();
      expect(fake.sent, {DocumentKind.aadhaarFront, DocumentKind.aadhaarBack});
      expect(find.text('Aadhaar card sent'), findsOneWidget);
      expect(
        find.textContaining('does not mean it is identity-verified'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'PAN and bank request only one paper, and invalid links never show personal details',
    (tester) async {
      for (final paper in ['pan', 'bank']) {
        final fake = RecipientFake()
          ..verified = true
          ..paper = paper;
        await open(tester, fake);
        expect(find.text('Upload documents'), findsOneWidget);
        await chooseRecipientFile(tester);
        await tester.tap(find.text('Send to Test'));
        await tester.pumpAndSettle();
        expect(fake.sent, {
          paper == 'pan' ? DocumentKind.pan : DocumentKind.bankProof,
        });
      }
      await open(tester, RecipientFake(), requestToken: 'invalid');
      expect(find.text('Link unavailable'), findsOneWidget);
      expect(find.textContaining('Test Owner'), findsNothing);
      expect(find.text('Photo'), findsNothing);
    },
  );
  testWidgets(
    'changing links drops selected private files and stale confirmation',
    (tester) async {
      final fake = RecipientFake()..verified = true;
      await open(tester, fake);
      await chooseRecipientFile(tester, stayOnDetails: true);
      expect(find.text(fixtureImage().name), findsOneWidget);
      final next = RecipientFake();
      await open(tester, next);
      expect(find.text(fixtureImage().name), findsNothing);
      expect(find.text('Continue with +911111111111'), findsOneWidget);
    },
  );
  testWidgets(
    'broker shows three paper rows; canceled share creates nothing; copying is never marked sent',
    (tester) async {
      final fake = RequestsFake();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BrokerDocumentLinks(
              requests: fake,
              draftId: 'test',
              revision: 1,
              party: sampleDraft().owners.first,
              onAdd: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send link'), findsNWidgets(3));
      await tester.tap(find.byTooltip('Send link').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.creates, 0);
      await tester.longPress(find.text('Aadhaar card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Aadhaar card link'));
      await tester.pumpAndSettle();
      expect(fake.creates, 1);
      expect(fake.records, 0);
      expect(find.textContaining('No message has been sent'), findsOneWidget);
    },
  );
}
