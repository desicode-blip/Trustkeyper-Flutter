import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/ui_test_main.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/features/document_requests/presentation/recipient_document_screen.dart';

void main() {
  testWidgets(
    'offline recipient photo and file actions only select synthetic documents',
    (tester) async {
      final app = UiTestApp();
      addTearDown(app.router.dispose);
      addTearDown(app.properties.dispose);
      await tester.pumpWidget(app);
      for (final paper in ['aadhaar', 'pan', 'bank', 'all']) {
        app.router.go('/ui-test/recipient/$paper');
        await tester.pumpAndSettle();
        final screen = tester.widget<RecipientDocumentScreen>(
          find.byType(RecipientDocumentScreen),
        );
        expect(screen.pickFile, isNotNull);
        for (final camera in [true, false]) {
          final file = await screen.pickFile!(camera);
          expect(file, isNotNull);
          expect(file!.name, 'TEST-DOCUMENT-NOT-VALID.pdf');
          expect(file.bytes.take(5), '%PDF-'.codeUnits);
          expect(file.validate, returnsNormally);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'offline gallery opens native previews without initializing Firebase',
    (tester) async {
      final app = UiTestApp();
      addTearDown(app.router.dispose);
      addTearDown(app.properties.dispose);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('TrustKeyper UI Test'), findsOneWidget);
      expect(find.textContaining('OFFLINE TEST APP'), findsOneWidget);
      for (final name in [
        'login',
        'phone-otp',
        'email-otp',
        'profile',
        'roles',
        'approval-pending',
        'approval-verified',
        'paused',
        'broker-home',
      ]) {
        app.router.push('/preview/$name');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (name != 'broker-home') {
          expect(find.byType(AbsorbPointer), findsWidgets);
        } else {
          expect(find.text('Namaste, Test'), findsOneWidget);
        }
        app.router.pop();
        await tester.pumpAndSettle();
      }
      app.router.push('/broker/property');
      await tester.pumpAndSettle();
      expect(find.text('Select the property'), findsOneWidget);
      expect(tester.takeException(), isNull);
      app.router.push('/ui-test/agreement');
      await tester.pumpAndSettle();
      expect(find.text('How many owners?'), findsOneWidget);
      expect(app.drafts.records, isEmpty);
      expect(tester.takeException(), isNull);
      app.router.push('/ui-test/documents');
      await tester.pumpAndSettle();
      expect(find.text('Private documents'), findsOneWidget);
      expect(app.documentStore.files, isEmpty);
      expect(tester.takeException(), isNull);
      app.router.push('/ui-test/demo-agreement');
      await tester.pumpAndSettle();
      expect(find.textContaining('DEMO ONLY'), findsOneWidget);
      expect(find.text('Sign agreement'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'UI-test properties are local, validated and retain IDs across edits',
    () async {
      final repository = UiTestPropertyRepository();
      addTearDown(repository.dispose);
      expect(await repository.watchProperties().first, isEmpty);
      final input = BrokerProperty(
        id: '',
        address: 'Test flat',
        rooms: '2 BHK',
        floor: 1,
        totalFloors: 2,
        furnishing: 'Empty',
      );
      final saved = await repository.save(input);
      expect(saved.id, 'ui-test-1');
      expect(
        (await repository.watchProperties().first).single.address,
        'Test flat',
      );
      final changed = BrokerProperty.fromMap(saved.id, {
        ...saved.toMap(),
        'address': 'Edited test flat',
      });
      final updated = await repository.save(changed);
      expect(updated.id, saved.id);
      expect(
        (await repository.watchProperties().first).single.address,
        'Edited test flat',
      );
      for (final label in ['', 'rjh', 'A', '1']) {
        final optionalProperty = await repository.save(
          BrokerProperty.fromMap('', {...input.toMap(), 'address': label}),
        );
        expect(optionalProperty.address, label);
        expect(optionalProperty.id, isNotEmpty);
      }
      await expectLater(
        repository.save(
          BrokerProperty.fromMap('', {...input.toMap(), 'floor': -1}),
        ),
        throwsStateError,
      );
      final anotherSession = UiTestPropertyRepository();
      addTearDown(anotherSession.dispose);
      expect(await anotherSession.watchProperties().first, isEmpty);
    },
  );
}
