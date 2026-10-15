import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_draft.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_field_validation.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_progress_repository.dart';
import 'package:trustkeyper/src/features/broker/data/broker_property_repository.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_agreement_wizard.dart';
import 'agreement_draft_test.dart' show sampleDraft, DraftRepositoryFake;
import 'agreement_progress_test.dart' show MemoryProgressPersistence;
import 'broker_property_test.dart' show sampleProperty, captureScreen;
import 'private_documents_test.dart' show MemoryDocumentStore;

AgreementDraft changed(Map<String, dynamic> values) =>
    AgreementDraft.fromMap('test-draft', {...sampleDraft().toMap(), ...values});

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto');
    for (final weight in [400, 500, 600, 700]) {
      fonts.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  test(
    'blank property text does not block properties, drafts or checkpoints',
    () {
      for (final address in ['', '       ']) {
        final property = BrokerProperty.fromMap('property', {
          ...sampleProperty().toMap(),
          'address': address,
        });
        expect(property.validationError, isNull);
        final progress = AgreementProgress(
          draft: changed({'propertyAddress': address}),
          stage: 'ownerCount',
          person: 0,
        );
        expect(progress.validationError, isNull);
        expect(changed({'propertyAddress': address}).validationError, isNull);
        expect(
          agreementFieldIssues(changed({'propertyAddress': address})),
          isEmpty,
        );
        expect(
          progress.validationError,
          isNot(contains('draft progress is invalid')),
        );
      }
    },
  );

  test(
    'short flat names and addresses work in properties, agreements and checkpoints',
    () {
      for (final address in ['1', '402', 'A', '22/B', 'घर']) {
        final draft = changed({'propertyAddress': address});
        final property = BrokerProperty.fromMap('property', {
          ...sampleProperty().toMap(),
          'address': address,
        });
        expect(property.validationError, isNull);
        expect(draft.validationError, isNull);
        expect(
          AgreementProgress(
            draft: draft,
            stage: 'ownerCount',
            person: 0,
          ).validationError,
          isNull,
        );
      }
    },
  );

  test('checkpoint does not demand future names, dates or amounts', () {
    final draft = changed({
      'owners': [
        {'id': 'owner-1'},
      ],
      'tenants': [
        {'id': 'tenant-1'},
      ],
      'monthlyRentPaise': -1,
      'securityDepositPaise': -1,
      'startDateISO': null,
      'endDateISO': null,
    });
    expect(
      AgreementProgress(
        draft: draft,
        stage: 'owner',
        person: 0,
      ).validationError,
      isNull,
    );
  });

  test('all invalid fields identify their exact person and optional email', () {
    final draft = changed({
      'owners': [
        {'id': 'owner-1', 'name': '', 'phone': '+91', 'email': 'broken'},
        sampleDraft().owners[1].toMap(),
      ],
    });
    final issues = agreementFieldIssues(
      draft,
    ).where((issue) => issue.stage == 'owner').toList();
    expect(issues.map((issue) => issue.field), [
      'owner/0/name',
      'owner/0/phone',
      'owner/0/email',
    ]);
    expect(issues.every((issue) => issue.person == 0), isTrue);
    expect(issues.last.message, contains('leave it empty'));
  });

  test(
    'duplicate phones identify both people without cross-role restrictions',
    () {
      final draft = changed({
        'owners': [
          sampleDraft().owners.first.toMap(),
          {
            ...sampleDraft().owners[1].toMap(),
            'phone': sampleDraft().owners.first.phone,
          },
        ],
      });
      expect(
        agreementFieldIssues(
          draft,
        ).where((issue) => issue.field.endsWith('/phone')).length,
        2,
      );
      expect(agreementFieldIssues(sampleDraft()), isEmpty);
    },
  );

  test(
    'money, shares, dates and brokerage have independent correction targets',
    () {
      final draft = changed({
        'monthlyRentPaise': -1,
        'securityDepositPaise': 100,
        'monthlyMaintenancePaise': -1,
        'ownerBrokeragePaise': -1,
        'startDateISO': null,
        'endDateISO': null,
      });
      final issues = agreementFieldIssues(
        draft,
        inputs: {'rent': '', 'maintenance': 'bad'},
      );
      expect(
        issues.map((issue) => issue.field),
        containsAll([
          'rent',
          'maintenance',
          'depositShares',
          'startDate',
          'endDate',
          'ownerBrokerage',
        ]),
      );
      expect(
        issues.firstWhere((issue) => issue.field == 'rent').message,
        'Enter monthly rent.',
      );
      expect(
        issues.firstWhere((issue) => issue.field == 'maintenance').message,
        contains('non-negative'),
      );
      expect(
        agreementFieldIssues(
          sampleDraft(lockIn: 12),
        ).any((issue) => issue.field == 'lockIn'),
        isTrue,
      );
    },
  );

  for (final width in [320.0, 363.4, 440.0]) {
    testWidgets('owner errors appear once beside their fields at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: BrokerAgreementWizard(
              property: sampleProperty(),
              repository: DraftRepositoryFake(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'bad');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Please check these details'), findsNothing);
      expect(find.text('Fix'), findsNothing);
      expect(find.text('Enter the full name.'), findsOneWidget);
      expect(
        find.text('Enter a valid 10-digit Indian mobile number.'),
        findsOneWidget,
      );
      expect(
        find.text('Enter a valid email address, or leave it empty.'),
        findsOneWidget,
      );
      final decorations = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.decoration!.errorText)
          .toList();
      expect(decorations.every((message) => message != null), isTrue);
      expect(
        find.text(
          'This draft progress is invalid. Reopen the property to continue.',
        ),
        findsNothing,
      );
      await captureScreen(
        tester,
        boundary,
        'build37-owner-fields-${width.round()}',
      );
      await tester.tap(find.byType(TextField).last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .last
            .focusNode!
            .hasFocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'correcting owner fields removes errors and opens working papers',
    (tester) async {
      final persistence = MemoryProgressPersistence();
      final progress = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'test-broker',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            property: sampleProperty(),
            repository: DraftRepositoryFake(),
            progressRepository: progress,
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
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Please check these details'), findsNothing);
      expect(find.text('Enter the full name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'TEST Owner');
      await tester.enterText(find.byType(TextField).at(1), '1111111111');
      await tester.pumpAndSettle();
      expect(find.text('Please check these details'), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Aadhaar front'), findsOneWidget);
      expect((await progress.load('stable-draft-id')).stage, 'ownerPapers');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tenant two errors do not name or change tenant one', (
    tester,
  ) async {
    final draft = changed({
      'tenants': [
        sampleDraft().tenants.first.toMap(),
        {...sampleDraft().tenants[1].toMap(), 'name': '', 'phone': '+91'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerAgreementWizard(
          initialProgress: AgreementProgress(
            draft: draft,
            stage: 'tenant',
            person: 1,
          ),
          repository: DraftRepositoryFake(),
        ),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the full name.'), findsOneWidget);
    expect(find.text('Please check these details'), findsNothing);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .decoration!
          .errorText,
      'Enter the full name.',
    );
    await tester.tap(find.text('Tenant 1'));
    await tester.pumpAndSettle();
    expect(find.text('Test Tenant One'), findsOneWidget);
    expect(find.text('Please check these details'), findsNothing);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.decoration!.errorText == null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'fixing tenant two money fields retains a valid non-party checkpoint',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final persistence = MemoryProgressPersistence();
      final progress = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'test-broker',
      );
      final draft = changed({
        'owners': [sampleDraft().owners.first.toMap()],
        'tenants': [
          sampleDraft().tenants.first.toMap(),
          {...sampleDraft().tenants[1].toMap(), 'rentSharePaise': -1},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: draft,
              stage: 'review',
              person: 0,
            ),
            repository: DraftRepositoryFake(),
            progressRepository: progress,
          ),
        ),
      );
      await tester.tap(find.text('Save private draft'));
      await tester.pumpAndSettle();
      final shareFix = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText().startsWith(
                  'Tenant 2 · Rent share:',
                ) ==
                true,
      );
      await tester.tap(shareFix);
      await tester.pumpAndSettle();
      expect(find.text('Please check these details'), findsNothing);
      final target = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Rent share *' &&
            widget.focusNode?.hasFocus == true,
      );
      expect(target, findsOneWidget);
      await tester.enterText(target, '11000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final saved = await progress.load('test-draft');
      expect(saved.stage, 'dates');
      expect(saved.person, 0);
      expect(saved.draft.tenants[1].rentSharePaise, 1100000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('resumed periods open missing dates with inline errors only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerAgreementWizard(
          initialProgress: AgreementProgress(
            draft: changed({'startDateISO': null, 'endDateISO': null}),
            stage: 'periods',
            person: 0,
          ),
          repository: DraftRepositoryFake(),
        ),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Choose start date *'), findsOneWidget);
    expect(find.text('Choose the agreement start date.'), findsOneWidget);
    expect(find.text('Please check these details'), findsNothing);
    expect(find.text('Fix'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('network save failure is not misreported as missing fields', (
    tester,
  ) async {
    final persistence = MemoryProgressPersistence()..failWrite = true;
    final progress = FirebaseAgreementProgressRepository(
      persistence: persistence,
      currentUid: () => 'test-broker',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerAgreementWizard(
          property: sampleProperty(),
          repository: DraftRepositoryFake(),
          progressRepository: progress,
        ),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('How many owners?'), findsOneWidget);
    expect(
      find.text('Could not save progress. Check your connection and retry.'),
      findsOneWidget,
    );
    expect(find.text('Please check these details'), findsNothing);
    expect(persistence.records, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'blank property text advances and saves without asking for an address',
    (tester) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final persistence = MemoryProgressPersistence();
      final progress = FirebaseAgreementProgressRepository(
        persistence: persistence,
        currentUid: () => 'test-broker',
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: BrokerAgreementWizard(
              property: BrokerProperty.fromMap('existing-property', {
                ...sampleProperty().toMap(),
                'address': '',
              }),
              repository: DraftRepositoryFake(),
              progressRepository: progress,
              documentFactory: (draft) => PrivateDocuments(
                draftId: draft.id,
                revision: draft.revision,
                partyIds: {
                  ...draft.owners,
                  ...draft.tenants,
                }.map((party) => party.id).toSet(),
                store: MemoryDocumentStore(),
                currentUid: () => 'test-broker',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Add owner'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Owner 1 details'), findsOneWidget);
      expect(find.text('Please check these details'), findsNothing);
      await captureScreen(tester, boundary, 'build36-blank-property-owner');
      final saved = await progress.load('stable-draft-id');
      expect(saved.draft.owners.length, 2);
      expect(saved.draft.propertyAddress, '');
      expect(
        saved.draft.propertyDetails!['address'],
        saved.draft.propertyAddress,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
