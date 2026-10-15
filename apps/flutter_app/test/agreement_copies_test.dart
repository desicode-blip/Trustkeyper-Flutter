import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/agreement_copies/agreement_copies.dart';
import 'package:trustkeyper/src/features/agreement_copies/admin_copy_upload_screen.dart';
import 'package:trustkeyper/src/features/agreement_copies/agreement_copy_screen.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';

AgreementCopyFile fixture() => AgreementCopyFile(
  name: 'TEST demo.pdf',
  bytes: Uint8List.fromList(utf8.encode('%PDF-1.4\nTEST ONLY\n%%EOF')),
);

class CopyGateway implements AgreementCopyGateway {
  bool fail = false;
  final requests = <AgreementCopyRequest>[];
  @override
  String operationId() => 'test-copy-operation';
  @override
  Future<AgreementCopyFile> read(String agreementId, int revision) async =>
      fixture();
  @override
  Future<void> publish(AgreementCopyRequest request) async {
    requests.add(request);
    if (fail) throw const DocumentFailure('Test interrupted upload');
  }
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 300);
  await Scrollable.ensureVisible(tester.element(finder));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'signed-copy design uses server data and never exposes admin processing or invented delivery',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AgreementCopyScreen(
            agreementId: 'agreement',
            revision: 1,
            demo: false,
            role: 'owner',
            reader: () async => AgreementCopyFile(
              name: 'Signed agreement.pdf',
              bytes: fixture().bytes,
              mode: 'externally_signed',
              partyCount: 3,
              startDate: DateTime(2026, 10, 12),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agreement signed by all 3'), findsOneWidget);
      expect(find.text('12 Oct 2026'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.textContaining('admin'), findsNothing);
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(find.textContaining('payout'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'received private copy must match exact ID/version, contents, size and checksum',
    () {
      final file = fixture();
      final data = <String, dynamic>{
        'ready': true,
        'agreementId': 'agreement',
        'revision': 1,
        'mode': 'demo',
        'size': file.bytes.length,
        'sha256': file.digest,
        'base64': base64Encode(file.bytes),
      };
      expect(decodeAgreementCopy(data, 'agreement', 1).bytes, file.bytes);
      for (final change in <Map<String, dynamic>>[
        {'revision': 2},
        {'agreementId': 'other'},
        {'mode': 'unknown'},
        {'sha256': 'forged'},
        {'size': 21 * 1024 * 1024},
      ]) {
        expect(
          () => decodeAgreementCopy({...data, ...change}, 'agreement', 1),
          throwsA(isA<DocumentFailure>()),
        );
      }
    },
  );
  testWidgets(
    'only reviewed selection can publish; no success on interruption and retry is immutable',
    (tester) async {
      final gateway = CopyGateway()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminCopyUploadScreen(
            agreementId: 'agreement',
            revision: 1,
            property: 'TEST property',
            gateway: gateway,
            picker: () async => fixture(),
            review: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Choose and review PDF');
      await tap(tester, 'Publish private copy');
      expect(gateway.requests.length, 1);
      expect(
        find.text('Copy published and confirmed by the server.'),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);
      gateway.fail = false;
      await tap(tester, 'Retry same upload');
      expect(gateway.requests.last, same(gateway.requests.first));
      expect(
        find.text('Copy published and confirmed by the server.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('cancelled or rejected file review does not publish', (
    tester,
  ) async {
    final gateway = CopyGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminCopyUploadScreen(
          agreementId: 'agreement',
          revision: 1,
          property: 'TEST property',
          gateway: gateway,
          picker: () async => fixture(),
          review: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Choose and review PDF');
    await tap(tester, 'Publish private copy');
    expect(gateway.requests, isEmpty);
  });

  testWidgets('copy screen remains usable at 320px with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: AgreementCopyScreen(
          agreementId: 'agreement',
          revision: 1,
          demo: true,
          role: 'tenant',
          reader: () async => fixture(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Read agreement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
