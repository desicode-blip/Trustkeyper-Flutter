import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/demo_agreement.dart';
import 'package:trustkeyper/src/features/broker/presentation/demo_agreement_screen.dart';

import 'agreement_draft_test.dart' show sampleDraft;

void main() {
  test(
    'demo contains all entered parties, exact money, dates and warnings',
    () {
      final demo = DemoAgreement(sampleDraft());
      expect(demo.text, contains('NOT FOR SIGNING'));
      for (final party in [...sampleDraft().owners, ...sampleDraft().tenants]) {
        expect(demo.text, contains(party.name));
        expect(demo.text, contains(party.phone));
      }
      expect(demo.text, contains('₹22,000.00'));
      expect(demo.text, contains('Twenty-two thousand rupees'));
      expect(demo.text, contains('31 Aug 2027'));
      expect(demo.text, contains('Not requested or recorded'));
      expect(() => demo.fields.clear(), throwsUnsupportedError);
    },
  );
  test('invalid shares cannot produce a demo', () {
    expect(() => DemoAgreement(sampleDraft(rentShare: 1)), throwsArgumentError);
  });
  test(
    'changed fields are deterministic and unrelated fields remain unchanged',
    () {
      final original = sampleDraft();
      final changed = AgreementDraft.fromMap(original.id, {
        ...original.toMap(),
        'ownerBrokeragePaise': 1200000,
      });
      final before = DemoAgreement(original);
      final after = DemoAgreement(changed);
      expect(after.changedFrom(before), {'brokerage'});
      expect(before.changedFrom(before), isEmpty);
      expect(before.snapshot, DemoAgreement(original).snapshot);
      expect(before.snapshot, isNot(after.snapshot));
    },
  );
  testWidgets('demo review is visibly non-signable on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DemoAgreementScreen(agreement: DemoAgreement(sampleDraft())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(DemoAgreement.warning), findsOneWidget);
    expect(find.text('Sign agreement'), findsNothing);
    expect(find.text('Record consent'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
