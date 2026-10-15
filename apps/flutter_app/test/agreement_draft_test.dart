import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft_repository.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_agreement_wizard.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'private_documents_test.dart' show MemoryDocumentStore;

AgreementDraft sampleDraft({
  int rentShare = 1100000,
  int depositShare = 2200000,
  int ownerFee = 1100000,
  int tenantFee = 2200000,
  int lockIn = 6,
  int notice = 1,
}) => AgreementDraft(
  id: 'test-draft',
  propertyAddress: 'UI Test Flat 402, Test Towers',
  owners: const [
    AgreementParty(
      id: 'owner-1',
      name: 'Test Owner One',
      phone: '+919000000001',
    ),
    AgreementParty(
      id: 'owner-2',
      name: 'Test Owner Two',
      phone: '+919000000002',
    ),
  ],
  tenants: [
    AgreementParty(
      id: 'tenant-1',
      name: 'Test Tenant One',
      phone: '+919000000003',
      rentSharePaise: rentShare,
      depositSharePaise: depositShare,
    ),
    const AgreementParty(
      id: 'tenant-2',
      name: 'Test Tenant Two',
      phone: '+919000000004',
      rentSharePaise: 1100000,
      depositSharePaise: 2200000,
    ),
  ],
  monthlyRentPaise: 2200000,
  maintenancePaise: 0,
  depositPaise: 4400000,
  startDate: DateTime(2026, 10, 1),
  endDate: DateTime(2027, 8, 31),
  ownerBrokeragePaise: ownerFee,
  tenantBrokeragePaise: tenantFee,
  lockInMonths: lockIn,
  noticeMonths: notice,
);

class DraftRepositoryFake implements AgreementDraftRepository {
  bool failSave = false;
  final attempts = <AgreementDraft>[];
  @override
  String newId() => 'stable-draft-id';
  @override
  Future<AgreementDraft> load(String id) async => sampleDraft();
  @override
  Future<void> save(AgreementDraft draft) async {
    attempts.add(draft);
    if (failSave) throw const DraftFailure('Save failed; try again.');
    if (draft.validationError != null) {
      throw DraftFailure(draft.validationError!);
    }
  }
}

void main() {
  testWidgets(
    'new multi-party journey saves the entered contract, not sample people',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = DraftRepositoryFake();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            property: BrokerProperty(
              id: 'property-from-picker',
              address: 'UI Test Flat 402, Test Towers',
              rooms: '2 BHK',
              floor: 4,
              totalFloors: 8,
              furnishing: 'Empty',
            ),
            repository: repository,
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: MemoryDocumentStore(),
              currentUid: () => 'test-broker',
            ),
            onSaved: () {},
          ),
        ),
      );
      Future<void> next() async {
        await tester.tap(
          find.textContaining(RegExp(r'^Next(?:: (Owner|Tenant) \d+)?$')),
        );
        await tester.pumpAndSettle();
      }

      Future<void> party(String name, String phone) async {
        await tester.enterText(find.byType(TextField).at(0), name);
        await tester.enterText(find.byType(TextField).at(1), phone);
        await next();
        expect(find.text('Aadhaar front'), findsOneWidget);
        expect(find.text('Aadhaar back'), findsOneWidget);
        expect(find.text('Add document'), findsNWidgets(4));
        await next();
      }

      await tester.tap(find.byTooltip('Add owner'));
      await tester.pumpAndSettle();
      await next();
      await party('First Actual Owner', '9000000011');
      await party('Second Actual Owner', '9000000012');
      expect(find.text('How many tenants?'), findsOneWidget);
      await tester.tap(find.byTooltip('Add tenant'));
      await tester.pumpAndSettle();
      await next();
      await party('First Actual Tenant', '9000000013');
      await party('Second Actual Tenant', '9000000014');
      await tester.enterText(find.byType(TextField).at(0), '22000.01');
      await tester.tap(find.text('2 months'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Split equally'));
      await tester.tap(find.text('Split equally'));
      await tester.pumpAndSettle();
      await next();
      await tester.tap(find.text('Choose start date *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await next();
      await tester.tap(find.text('6 months'));
      await tester.pumpAndSettle();
      await next();
      await tester.tap(find.text('Both'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '11000');
      await tester.enterText(find.byType(TextField).at(1), '22000');
      await tester.tap(find.text('Check agreement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save private draft'));
      await tester.pumpAndSettle();
      expect(find.text('Private draft saved'), findsOneWidget);
      final draft = repository.attempts.single;
      expect(draft.id, 'stable-draft-id');
      expect(draft.propertyId, 'property-from-picker');
      expect(draft.owners.map((entry) => entry.name), [
        'First Actual Owner',
        'Second Actual Owner',
      ]);
      expect(draft.tenants.map((entry) => entry.name), [
        'First Actual Tenant',
        'Second Actual Tenant',
      ]);
      expect(draft.monthlyRentPaise, 2200001);
      expect(draft.depositPaise, 4400002);
      expect(
        draft.tenants.fold(0, (total, entry) => total + entry.rentSharePaise),
        2200001,
      );
      expect(
        draft.tenants.fold(
          0,
          (total, entry) => total + entry.depositSharePaise,
        ),
        4400002,
      );
      expect(draft.lockInMonths, 6);
      expect(draft.noticeMonths, 1);
      expect(draft.brokeragePaise, 3300000);
      expect(draft.validationError, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'money parsing is exact and rejects malformed, negative and oversized amounts',
    () {
      expect(parseRupeesToPaise('22000.01'), 2200001);
      expect(parseRupeesToPaise('0.1'), 10);
      for (final input in [
        'NaN',
        'Infinity',
        '-1',
        '1e3',
        '22,000',
        '1.001',
        '100000001',
        '',
      ]) {
        expect(parseRupeesToPaise(input), isNull, reason: input);
      }
    },
  );
  test('calendar months clamp correctly, including leap years', () {
    expect(addCalendarMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addCalendarMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
    expect(
      addCalendarMonths(
        DateTime(2026, 10, 1),
        11,
      ).subtract(const Duration(days: 1)),
      DateTime(2027, 8, 31),
    );
  });
  test('Indian amount words include precise paise and do not drop zeros', () {
    expect(rupeesInWords(2200000), 'Twenty-two thousand rupees');
    expect(rupeesInWords(1100000), 'Eleven thousand rupees');
    expect(rupeesInWords(10000001), 'One lakh rupees and one paise');
    expect(rupeesInWords(0), 'Zero rupees');
  });
  test(
    'all parties, terms, shares and split brokerage survive a draft round trip',
    () {
      final draft = sampleDraft();
      expect(draft.validationError, isNull);
      final restored = AgreementDraft.fromMap(draft.id, draft.toMap());
      expect(restored.validationError, isNull);
      expect(restored.owners.length, 2);
      expect(restored.tenants.length, 2);
      expect(restored.brokeragePaise, 3300000);
      expect(restored.toMap(), draft.toMap());
      expect(draft.toMap().keys, isNot(contains('participantUids')));
      expect(draft.toMap().keys, isNot(contains('emailVerified')));
      expect(
        () => draft.owners.add(draft.owners.first),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'incorrect shares, negative brokerage and excessive periods block saving',
    () {
      expect(
        sampleDraft(rentShare: 1100001).validationError,
        contains('rent shares'),
      );
      expect(
        sampleDraft(depositShare: 2200001).validationError,
        contains('deposit shares'),
      );
      expect(sampleDraft(ownerFee: -1).validationError, contains('brokerage'));
      expect(
        sampleDraft(lockIn: 12).validationError,
        contains('agreement period'),
      );
      expect(
        sampleDraft(notice: 12).validationError,
        contains('agreement period'),
      );
      expect(sampleDraft(ownerFee: 0, tenantFee: 0).validationError, isNull);
      expect(
        sampleDraft(ownerFee: 0, tenantFee: 0).toMap()['brokeragePayer'],
        'none',
      );
    },
  );
  test('duplicate contacts and invalid identity are rejected', () {
    expect(
      AgreementDraft.validateParties(const [
        AgreementParty(id: 'one', name: 'Test One', phone: '+919000000001'),
        AgreementParty(id: 'two', name: 'Test Two', phone: '+919000000001'),
      ]),
      contains('different mobile'),
    );
    expect(
      const AgreementParty(
        id: 'one',
        name: 'Test',
        phone: '+919000000001',
        email: 'invalid',
      ).validationError,
      contains('valid email'),
    );
  });
  for (final width in [440.0, 320.0]) {
    testWidgets('multi-party count/details fit at $width and retain entries', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            property: BrokerProperty(
              id: 'test-property',
              address: 'UI Test Flat 402, Test Towers',
              rooms: '2 BHK',
              floor: 4,
              totalFloors: 8,
              furnishing: 'Unfurnished',
            ),
            repository: DraftRepositoryFake(),
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: MemoryDocumentStore(),
              currentUid: () => 'test-broker',
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Add owner'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Test Owner One');
      await tester.enterText(find.byType(TextField).at(1), '9000000001');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Aadhaar front'), findsOneWidget);
      expect(find.text('Add document'), findsNWidgets(4));
      await tester.tap(find.text('Next: Owner 2'));
      await tester.pumpAndSettle();
      expect(find.text('Owner 2 details'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Test Owner Two');
      await tester.enterText(find.byType(TextField).at(1), '9000000002');
      await tester.tap(find.text('Owner 1'));
      await tester.pumpAndSettle();
      expect(find.text('Test Owner One'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'private draft save failure preserves all fields and retry identity',
    (tester) async {
      final repository = DraftRepositoryFake()..failSave = true;
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            initialDraft: sampleDraft(),
            repository: repository,
            onSaved: () {
              saved = true;
            },
          ),
        ),
      );
      await tester.tap(find.text('Save private draft'));
      await tester.pumpAndSettle();
      expect(find.text('Save failed; try again.'), findsOneWidget);
      repository.failSave = false;
      await tester.tap(find.text('Save private draft'));
      await tester.pumpAndSettle();
      expect(find.text('Private draft saved'), findsOneWidget);
      expect(repository.attempts.map((draft) => draft.id), [
        'test-draft',
        'test-draft',
      ]);
      expect(repository.attempts.last.owners.length, 2);
      expect(repository.attempts.last.tenants.length, 2);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved, true);
    },
  );
  testWidgets(
    'shortening a term still allows fixing lock-in on the next screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            initialDraft: sampleDraft(lockIn: 11),
            repository: DraftRepositoryFake(),
          ),
        ),
      );
      final datesCard = find.ancestor(
        of: find.text('Dates and notice'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(datesCard);
      await tester.tap(
        find.descendant(of: datesCard, matching: find.text('Change')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Lock-in period'), findsOneWidget);
      await tester.tap(find.text('6 months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Dates and notice · Changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy brokerage split is reviewed instead of silently set to zero',
    (tester) async {
      final data = sampleDraft().toMap()
        ..remove('ownerBrokeragePaise')
        ..remove('tenantBrokeragePaise');
      final legacy = AgreementDraft.fromMap('legacy-draft', data);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            initialDraft: legacy,
            repository: DraftRepositoryFake(),
          ),
        ),
      );
      expect(find.textContaining('its split was not saved'), findsOneWidget);
      await tester.tap(find.text('Check agreement'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a positive amount, or change who pays the brokerage.'),
        findsNWidgets(2),
      );
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check agreement'));
      await tester.pumpAndSettle();
      expect(find.text('Save private draft'), findsOneWidget);
    },
  );
}
