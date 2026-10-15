import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/broker_records.dart';
import 'package:trustkeyper/src/features/broker/data/broker_repository.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_records_screen.dart';

BrokerAgreementSummary agreement(
  String id,
  String propertyId, {
  String status = 'draft',
}) => BrokerAgreementSummary(
  id: id,
  propertyId: propertyId,
  property: 'TEST same property name',
  people: 'TEST owner',
  status: status,
  monthlyRentPaise: 2200000,
  updatedAt: null,
  details: {
    'owners': [
      {
        'id': 'owner',
        'name': 'TEST owner',
        'phone': '+919999999999',
        'email': 'owner@test.invalid',
      },
    ],
    'tenants': [
      {'id': 'tenant', 'name': 'TEST tenant', 'phone': '+918888888888'},
    ],
  },
);
BrokerProperty property(String id) => BrokerProperty(
  id: id,
  address: 'TEST same property name',
  rooms: '2 BHK',
  floor: 1,
  totalFloors: 3,
  furnishing: 'Empty',
);

void main() {
  test('only explicitly addressed brokerage is a broker earning', () {
    expect(
      BrokerPaymentSummary.belongsToBroker({
        'participantUids': ['broker'],
        'recipientUid': 'owner',
        'kind': 'rent',
      }, 'broker'),
      false,
    );
    expect(
      BrokerPaymentSummary.belongsToBroker({
        'participantUids': ['broker'],
        'kind': 'brokerage',
      }, 'broker'),
      false,
    );
    expect(
      BrokerPaymentSummary.belongsToBroker({
        'recipientUid': 'broker',
        'kind': 'brokerage',
      }, 'broker'),
      true,
    );
  });
  testWidgets('property detail removes revoked metadata while open', (
    tester,
  ) async {
    final changes = StreamController<List<BrokerProperty>>.broadcast();
    addTearDown(changes.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BrokerRecordsScreen(
            agreements: Stream.value(const []),
            properties: Stream.value([property('private-home')]),
            watchDetailProperties: () => changes.stream,
            onAddProperty: null,
            onOpenAgreement: (_) {},
            onPhotoChecks: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST same property name'));
    await tester.pump();
    changes.add([property('private-home')]);
    await tester.pumpAndSettle();
    expect(find.text('2 BHK · Empty'), findsOneWidget);
    changes.add([]);
    await tester.pumpAndSettle();
    expect(find.text('2 BHK · Empty'), findsNothing);
    expect(
      find.text('This property is no longer in your records.'),
      findsOneWidget,
    );
  });
  test(
    'same property labels never collapse distinct saved IDs; drafts never imply rented',
    () {
      final records = brokerPropertyRecords(
        [property('one'), property('two')],
        [agreement('draft', 'one')],
      );
      expect(records.length, 2);
      expect(records.first.state, 'Agreement pending');
      expect(records.last.state, 'No active agreement');
      expect(
        brokerPropertyRecords([], [
          agreement('active', 'one', status: 'active'),
        ]).single.state,
        'Rented',
      );
    },
  );
  test(
    'people deduplicate by contact per role and count actual distinct property IDs',
    () {
      final agreements = [
        agreement('one', 'property-one'),
        agreement('two', 'property-one'),
        agreement('three', 'property-two'),
      ];
      final owners = brokerPersonRecords(agreements, 'owner');
      expect(owners.length, 1);
      expect(owners.single.propertyCount, 2);
      expect(
        brokerPersonRecords(agreements, 'tenant').single.name,
        'TEST tenant',
      );
    },
  );
  testWidgets(
    'property, owner and tenant tabs search real records and open detail',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BrokerRecordsScreen(
              agreements: Stream.value([agreement('one', 'property-one')]),
              properties: Stream.value([property('property-one')]),
              onAddProperty: () {},
              onOpenAgreement: (_) {},
              onPhotoChecks: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TEST same property name'), findsOneWidget);
      await tester.tap(find.text('Owners'));
      await tester.pumpAndSettle();
      expect(find.text('TEST owner'), findsOneWidget);
      expect(find.text('TEST tenant'), findsNothing);
      await tester.enterText(find.byType(TextField), '8888');
      await tester.pumpAndSettle();
      expect(find.text('TEST owner'), findsNothing);
      await tester.tap(find.text('Tenants'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEST tenant'));
      await tester.pumpAndSettle();
      expect(find.text('Properties (1)'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
    },
  );
  testWidgets(
    'private person disappears when source membership changes, not just after relogin',
    (tester) async {
      final changes =
          StreamController<List<BrokerAgreementSummary>>.broadcast();
      addTearDown(changes.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BrokerRecordsScreen(
              agreements: Stream.value([agreement('one', 'property-one')]),
              properties: Stream.value([property('property-one')]),
              watchDetailAgreements: () => changes.stream,
              onAddProperty: null,
              onOpenAgreement: (_) {},
              onPhotoChecks: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Owners'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TEST owner'));
      await tester.pump();
      changes.add([agreement('one', 'property-one')]);
      await tester.pumpAndSettle();
      expect(find.text('owner@test.invalid'), findsOneWidget);
      changes.add([]);
      await tester.pumpAndSettle();
      expect(find.text('owner@test.invalid'), findsNothing);
      expect(
        find.text('This person is no longer in your records.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'narrow records layout does not overflow with long names and statuses',
    (tester) async {
      tester.view.physicalSize = const Size(363, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BrokerRecordsScreen(
              agreements: Stream.value([agreement('one', 'property-one')]),
              properties: Stream.value([property('property-one')]),
              onAddProperty: null,
              onOpenAgreement: (_) {},
              onPhotoChecks: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
