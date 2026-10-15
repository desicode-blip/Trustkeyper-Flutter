import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/signing_fixture.dart';
import 'package:trustkeyper/src/core/testing/document_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_imports.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/presentation/sign_only_screen.dart';
import 'package:trustkeyper/src/features/broker/presentation/signing_requests_screen.dart';

void main() {
  AgreementPageFile page() =>
      AgreementPageFile(name: 'TEST agreement.pdf', bytes: testDocumentPdf());
  test(
    'sign-only validates one PDF, unique signer numbers and both required roles',
    () {
      const people = [
        AgreementSigner(
          name: 'TEST Owner',
          phone: '+911111111111',
          role: 'owner',
        ),
        AgreementSigner(
          name: 'TEST Tenant',
          phone: '+912222222222',
          role: 'tenant',
        ),
      ];
      expect(() => validateSigningRequest([page()], people), returnsNormally);
      expect(
        () => validateSigningRequest([page(), page()], people),
        throwsA(isA<DocumentFailure>()),
      );
      expect(
        () => validateSigningRequest([page()], [people.first]),
        throwsA(isA<DocumentFailure>()),
      );
      expect(
        () => validateSigningRequest(
          [page()],
          [
            people.first,
            const AgreementSigner(
              name: 'TEST Tenant',
              phone: '+911111111111',
              role: 'tenant',
            ),
          ],
        ),
        throwsA(isA<DocumentFailure>()),
      );
    },
  );
  Future<void> open(
    WidgetTester tester,
    OfflineSigningGateway gateway, {
    bool reviewed = true,
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SignOnlyScreen(
          gateway: gateway,
          picker: (camera) async => page(),
          reviewer: (file) async => reviewed,
          offline: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enterPeople(WidgetTester tester) async {
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), 'TEST Owner');
    await tester.enterText(inputs.at(1), '1111111111');
    await tester.ensureVisible(inputs.at(2));
    await tester.enterText(inputs.at(2), 'TEST Tenant');
    await tester.ensureVisible(inputs.at(3));
    await tester.enterText(inputs.at(3), '2222222222');
  }

  testWidgets(
    'unreviewed or cancelled pages cannot advance to signer capture',
    (tester) async {
      final gateway = OfflineSigningGateway();
      await open(tester, gateway, reviewed: false);
      await press(tester, 'Choose PDF file');
      await press(tester, 'Next');
      expect(
        find.textContaining('Open and check every page before'),
        findsOneWidget,
      );
      await press(tester, 'TEST agreement.pdf');
      await press(tester, 'Next');
      expect(find.text('Who will sign?'), findsNothing);
      expect(gateway.operations, isEmpty);
    },
  );
  testWidgets(
    'reviewed pages and exact people reach server-confirmed receipt with an idempotent retry',
    (tester) async {
      final gateway = OfflineSigningGateway()..failFirstSend = true;
      await open(tester, gateway);
      await press(tester, 'Choose PDF file');
      await press(tester, 'TEST agreement.pdf');
      await press(tester, 'Next');
      expect(find.text('Who will sign?'), findsOneWidget);
      await enterPeople(tester);
      await press(tester, 'Next');
      await press(tester, 'Send for signing');
      expect(
        find.textContaining('TEST connection interrupted'),
        findsOneWidget,
      );
      await press(tester, 'Retry same send');
      expect(gateway.operations.length, 2);
      expect(gateway.operations.toSet().length, 1);
      expect(find.text('Done! We have your agreement'), findsWidgets);
      await press(tester, 'See progress');
      expect(find.text('Agreement received'), findsOneWidget);
      expect(find.text('Agreement signed'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'signer omissions and duplicate numbers retain entered details for correction',
    (tester) async {
      final gateway = OfflineSigningGateway();
      await open(tester, gateway);
      await press(tester, 'Choose PDF file');
      await press(tester, 'TEST agreement.pdf');
      await press(tester, 'Next');
      await press(tester, 'Next');
      expect(find.textContaining('Give every signer a name'), findsOneWidget);
      await enterPeople(tester);
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(3), '1111111111');
      await press(tester, 'Next');
      expect(find.text('Who will sign?'), findsOneWidget);
      expect(gateway.operations, isEmpty);
    },
  );
  testWidgets(
    'narrow entry and private empty progress screen do not overflow or require Firebase',
    (tester) async {
      final gateway = OfflineSigningGateway();
      await open(tester, gateway, size: const Size(320, 740));
      expect(tester.takeException(), isNull);
      await press(tester, 'See saved signing requests');
      expect(find.byType(SigningRequestsScreen), findsOneWidget);
      expect(find.text('No signing requests yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
