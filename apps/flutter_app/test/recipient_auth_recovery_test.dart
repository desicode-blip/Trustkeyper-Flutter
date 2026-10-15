import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/document_requests/data/document_request_repository.dart';
import 'package:trustkeyper/src/features/document_requests/data/recipient_document_gateway.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/recipient_document_screen.dart';
import 'document_request_test.dart' as fixture;
import 'inline_documents_test.dart' show fixtureImage;

class AuthRecipient extends fixture.RecipientFake
    implements RecipientVerificationSession {
  final changes = StreamController<String?>.broadcast();
  String role = 'tenant';
  @override
  String? currentUid;
  bool stallRead = false, stallVerify = false;
  int reads = 0;
  @override
  Stream<String?> get identities => changes.stream;
  @override
  Future<DocumentRequestInfo> read(String token) async {
    reads++;
    if (stallRead) return Completer<DocumentRequestInfo>().future;
    return DocumentRequestInfo({
      ...fixture
          .information(
            verified: verified,
            paper: paper,
            status: received ? 'added' : 'seen',
          )
          .data,
      'role': role,
    });
  }

  @override
  Future<void> verifyOtp(String code) async {
    if (stallVerify) return Completer<void>().future;
    verified = true;
    currentUid = role;
    changes.add(currentUid);
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> mount(
  WidgetTester tester,
  AuthRecipient gateway, {
  bool stallPicker = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(gateway.changes.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: RecipientDocumentScreen(
        token: fixture.token,
        gateway: gateway,
        networkTimeout: const Duration(seconds: 2),
        pickFile: (_) => stallPicker
            ? Completer<Never>().future
            : Future.value(fixtureImage()),
        reviewFile: (_) async => true,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> signIn(WidgetTester tester) async {
  await tester.tap(find.text('Continue with +911111111111'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(find.byType(TextField), '123456');
  await tester.tap(find.text('Verify code'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'changing invitation cancels a pending chooser without freezing the new link',
    (tester) async {
      final gateway = AuthRecipient();
      await mount(tester, gateway, stallPicker: true);
      await signIn(tester);
      await tester.tap(find.text('Upload').first);
      await tester.pump();
      await tester.tap(find.text('Have a PDF? Choose a file instead'));
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecipientDocumentScreen(
            token:
                '${List.filled(64, 'c').join()}.${List.filled(43, 'd').join()}',
            gateway: gateway,
            networkTimeout: const Duration(seconds: 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Cancel selection'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Continue with +911111111111'), findsOneWidget);
    },
  );
  testWidgets(
    'ending verification while chooser is open leaves no stale cancellation control',
    (tester) async {
      final gateway = AuthRecipient();
      await mount(tester, gateway, stallPicker: true);
      await signIn(tester);
      await tester.tap(find.text('Upload').first);
      await tester.pump();
      await tester.tap(find.text('Have a PDF? Choose a file instead'));
      await tester.pump();
      gateway.verified = false;
      gateway.currentUid = null;
      gateway.changes.add(null);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Cancel selection'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Continue with +911111111111'), findsOneWidget);
    },
  );
  for (final role in ['owner', 'tenant']) {
    testWidgets('$role sign-in identity event reaches interactive documents', (
      tester,
    ) async {
      final gateway = AuthRecipient()..role = role;
      await mount(tester, gateway);
      await signIn(tester);
      expect(
        find.text(
          role == 'owner' ? 'Upload documents' : 'Test needs your documents',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(role == 'owner' ? 'Photo' : 'Upload').first);
      await tester.pump();
      gateway.stallRead = true;
      final reads = gateway.reads;
      await tester.tap(find.text('Have a PDF? Choose a file instead'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(gateway.reads, reads);
      expect(find.text('Front added'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('stalled OTP verification releases buttons and offers retry', (
    tester,
  ) async {
    final gateway = AuthRecipient()..stallVerify = true;
    await mount(tester, gateway);
    await signIn(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('taking too long'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify code'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'stalled initial read can retry without replacing the invitation',
    (tester) async {
      final gateway = AuthRecipient()..stallRead = true;
      await mount(tester, gateway);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gateway.stallRead = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Continue with +911111111111'), findsOneWidget);
    },
  );
  testWidgets(
    'unresponsive file chooser is cancellable and does not block details',
    (tester) async {
      final gateway = AuthRecipient();
      await mount(tester, gateway, stallPicker: true);
      await signIn(tester);
      await tester.tap(find.text('Upload').first);
      await tester.pump();
      await tester.tap(find.text('Have a PDF? Choose a file instead'));
      await tester.pump();
      await tester.tap(find.text('Cancel selection'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find
                  .ancestor(
                    of: find.text('Have a PDF? Choose a file instead'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is TextButton,
                    ),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
