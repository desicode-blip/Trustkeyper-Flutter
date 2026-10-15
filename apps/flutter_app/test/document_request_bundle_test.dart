import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/document_requests/data/recipient_document_gateway.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/document_link_dialog.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/document_request_widgets.dart';
import 'document_request_test.dart' as fixture;

class SessionRecipient extends fixture.RecipientFake
    implements RecipientVerificationSession {
  final changes = StreamController<String?>.broadcast();
  @override
  String? currentUid = 'owner';
  @override
  Stream<String?> get identities => changes.stream;
}

void main() {
  testWidgets(
    'whole document link accepts both Aadhaar sides, PAN and validated typed bank details',
    (tester) async {
      final gateway = fixture.RecipientFake()
        ..verified = true
        ..paper = 'all';
      await fixture.open(tester, gateway);
      expect(find.text('3 things for TEST ONLY Property 101'), findsOneWidget);
      expect(
        tester
            .widgetList<DocumentRoundAction>(find.byType(DocumentRoundAction))
            .singleWhere((action) => action.label == 'Type')
            .glyph,
        'pencil',
      );
      expect(fixture.send(tester).onPressed, isNull);
      await fixture.chooseRecipientFile(tester);
      await fixture.chooseRecipientFile(tester);
      await tester.tap(find.text('File').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test Owner');
      await tester.enterText(fields.at(1), 'TEST Bank');
      await tester.enterText(fields.at(2), '123456789012');
      await tester.enterText(fields.at(3), '123456789099');
      await tester.enterText(fields.at(4), 'SBIN0001234');
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Numbers are not the same. Check again.'),
        findsOneWidget,
      );
      expect(gateway.submissions, 0);
      await tester.enterText(fields.at(3), '123456789012');
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();
      expect(fixture.send(tester).onPressed, isNotNull);
      await tester.tap(find.text('Send to Test'));
      await tester.pumpAndSettle();
      expect(gateway.sent, {
        DocumentKind.aadhaarFront,
        DocumentKind.aadhaarBack,
        DocumentKind.pan,
      });
      expect(gateway.sentBank?['accountNumber'], '123456789012');
      expect(find.text('Documents sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recipient session ending clears selected identity files and returns to phone verification',
    (tester) async {
      final gateway = SessionRecipient()..verified = true;
      await fixture.open(tester, gateway);
      await fixture.chooseRecipientFile(tester, stayOnDetails: true);
      gateway.verified = false;
      gateway.currentUid = null;
      gateway.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Front added'), findsNothing);
      expect(find.text('Continue with +911111111111'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await gateway.changes.close();
    },
  );

  testWidgets(
    'email selector uses actual recipient email; missing email routes to person editing',
    (tester) async {
      String? selected;
      Future<void> open(String email) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showDialog<String>(
                      context: context,
                      builder: (_) => DocumentLinkDialog(
                        paper: 'Aadhaar card',
                        name: 'Test Owner',
                        phone: '+911111111111',
                        email: email,
                        canEditEmail: true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      await open('test@example.com');
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(selected, 'Email');
      await open('');
      await tester.tap(find.text('Add email'));
      await tester.pumpAndSettle();
      expect(selected, 'Add email');
    },
  );
}
