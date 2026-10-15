import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/core/testing/owner_property_fixture.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/auth/presentation/approved_auth_widgets.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_imports.dart';
import 'package:trustkeyper/src/features/broker/data/private_documents.dart';
import 'package:trustkeyper/src/features/owner/data/owner_properties.dart';
import 'package:trustkeyper/src/features/owner/data/owner_lifecycle.dart';
import 'package:trustkeyper/src/features/owner/presentation/owner_lifecycle_screen.dart';
import 'package:trustkeyper/src/features/owner/presentation/public_owner_listing_screen.dart';

OwnerPropertyRecord testOwnerLifecycleProperty({
  String status = 'fee_offered',
}) => OwnerPropertyRecord({
  'id': 'a' * 64,
  'revision': 10,
  'nextStep': 4,
  'status': status,
  'plan': 'full_service',
  'details': {
    'name': 'TEST private nickname',
    'address': 'TEST ONLY Flat 1 Example Road Hyderabad',
    'homeType': 'Apartment',
    'rooms': '2 BHK',
    'furnishing': 'Semi',
    'rentPaise': 4600000,
    'depositPaise': 9200000,
    'whoCanStay': 'Family',
    'availableFrom': '2026-11-01',
  },
  'photos': [
    {'size': 10, 'sha256': 'b' * 64, 'contentType': 'image/png'},
  ],
  'feeOffer': {
    'feeBps': 800,
    'effectiveFrom': '2026-11-01',
    'notes': 'TEST check completed',
  },
  'contract': {
    'status': status == 'fee_offered' ? 'ready' : 'signed',
    'sourceFile': {'pageCount': 4, 'sha256': 'c' * 64},
  },
  if (status == 'listing_live')
    'listing': {
      'title': 'TEST public home',
      'locality': 'TEST Hyderabad',
      'views': 0,
      'status': 'live',
    },
  'candidates': {},
});

class TestOwnerLifecycleGateway implements OwnerLifecycleGateway {
  final actions = <String>[];
  final enquiries = <Map<String, dynamic>>[];
  bool failNext = false;
  Map<String, dynamic>? receiptValue;
  @override
  Future<Map<String, dynamic>> change(
    OwnerPropertyRecord property,
    String action,
    Map<String, dynamic> input,
  ) async {
    actions.add(action);
    if (failNext) {
      failNext = false;
      throw const DocumentFailure('TEST network failure; no confirmation.');
    }
    if (action == 'begin_consent') return {'challengeId': 'd' * 64};
    return {
      ...property.data,
      'revision': property.revision + 1,
      if (action == 'confirm_consent') ...{
        'status': 'contract_accepted',
        'contract': {...property.data['contract'], 'status': 'accepted'},
      },
      if (action == 'publish_listing') ...{
        'status': 'listing_live',
        'listing': {...input, 'status': 'live', 'views': 0},
      },
      if (action == 'choose_tenant') ...{
        'status': 'tenant_chosen',
        'chosenTenantId': input['candidateId'],
        'listing': {...property.data['listing'], 'status': 'paused'},
      },
    };
  }

  @override
  Future<OwnerPropertyRecord> uploadContract(
    OwnerPropertyRecord property,
    AgreementPageFile file,
    String kind,
    String reference,
    String operationId, {
    required bool signaturesChecked,
  }) async => throw UnimplementedError();
  @override
  Future<AgreementPageFile> readContract(
    OwnerPropertyRecord property, {
    bool signed = false,
    bool admin = false,
  }) async => AgreementPageFile(
    name: 'TEST ONLY contract.pdf',
    bytes: Uint8List.fromList('%PDF-1.7 TEST ONLY'.codeUnits),
  );
  @override
  Future<Map<String, dynamic>> readPublic(String id) async => {
    'id': id,
    'title': 'TEST public home',
    'locality': 'TEST Hyderabad',
    'photoCount': 0,
    'rentPaise': 4600000,
    'depositPaise': 9200000,
    'maintenancePaise': 0,
    'rooms': '2 BHK',
    'furnishing': 'Semi',
    'whoCanStay': 'Family',
    'availableFrom': '2026-11-01',
  };
  @override
  Future<AgreementPageFile> readPublicPhoto(String id, int index) async =>
      throw UnimplementedError();
  @override
  Future<void> enquire(String id, Map<String, dynamic> input) async {
    enquiries.add(input);
  }

  @override
  Future<Map<String, dynamic>> receipt(String id) async =>
      receiptValue ?? {'received': false};
}

class TestOwnerPhoneProof implements OwnerContractPhoneProof {
  int sent = 0;
  int confirmed = 0;
  bool fail = false;
  @override
  String get phone => '+911111111111';
  @override
  Future<void> sendCode() async {
    sent++;
  }

  @override
  Future<void> confirmCode(String code) async {
    if (fail) throw const DocumentFailure('TEST code not accepted.');
    confirmed++;
  }
}

class TestListingPhoneProof implements ListingPhoneProof {
  String? phone;
  int confirmed = 0;
  @override
  Future<void> send(String phone) async {
    this.phone = phone;
  }

  @override
  Future<void> confirm(String code) async {
    confirmed++;
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final status in ['chosen', 'declined']) {
    testWidgets(
      'existing $status enquiry shows its real status without creating another interest',
      (tester) async {
        final gateway = TestOwnerLifecycleGateway()
          ..receiptValue = {
            'received': true,
            'status': status,
            'identityChecked': true,
            'agreementReady': status == 'chosen',
          };
        await open(
          tester,
          PublicOwnerListingScreen(
            id: 'a' * 64,
            gateway: gateway,
            proof: TestListingPhoneProof(),
          ),
        );
        await tap(tester, 'I am interested');
        await tester.enterText(find.byType(TextField), '2222222222');
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tap(tester, 'Send OTP');
        await tester.enterText(
          find.descendant(
            of: find.byType(ApprovedOtpInput),
            matching: find.byType(TextField),
          ),
          '123456',
        );
        await tap(tester, 'Verify phone');
        expect(find.text('Your interest is received'), findsOneWidget);
        expect(find.textContaining('You are not yet selected'), findsNothing);
        expect(
          find.textContaining(
            status == 'chosen'
                ? 'You have been selected.'
                : 'The owner did not select this enquiry.',
          ),
          findsOneWidget,
        );
        expect(gateway.enquiries, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'owner reads actual terms, explicitly agrees, requests fresh OTP and retains failed confirmation',
    (tester) async {
      final gateway = TestOwnerLifecycleGateway();
      final proof = TestOwnerPhoneProof();
      await open(
        tester,
        OwnerLifecycleScreen(
          property: testOwnerLifecycleProperty(),
          gateway: gateway,
          proof: proof,
          properties: OfflineOwnerPropertyGateway(),
          documentReviewer: (_) async => true,
        ),
      );
      expect(find.text('₹3,680 a month'), findsOneWidget);
      await tap(tester, 'Agree and sign');
      expect(proof.sent, 0);
      await tap(tester, 'Read full contract (4 pages)');
      final checkbox = find.byType(CheckboxListTile).last;
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tap(tester, 'Agree and sign');
      expect(proof.sent, 1);
      expect(gateway.actions, ['begin_consent']);
      await tester.enterText(
        find.descendant(
          of: find.byType(ApprovedOtpInput),
          matching: find.byType(TextField),
        ),
        '123456',
      );
      proof.fail = true;
      await tap(tester, 'Confirm');
      expect(find.text('TEST code not accepted.'), findsOneWidget);
      expect(gateway.actions.contains('confirm_consent'), false);
      proof.fail = false;
      await tap(tester, 'Confirm');
      expect(gateway.actions.last, 'confirm_consent');
      expect(find.text('Agreement confirmed'), findsOneWidget);
      expect(find.text('Your plan has started'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'listing cannot publish until public fields and photos are approved; retry preserves the form',
    (tester) async {
      final gateway = TestOwnerLifecycleGateway();
      await open(
        tester,
        OwnerLifecycleScreen(
          property: testOwnerLifecycleProperty(status: 'plan_active'),
          gateway: gateway,
          proof: TestOwnerPhoneProof(),
          properties: OfflineOwnerPropertyGateway(),
        ),
      );
      await tap(tester, 'Find a tenant');
      await tester.enterText(find.byType(TextField).at(0), 'TEST home');
      await tester.enterText(find.byType(TextField).at(1), 'TEST Hyderabad');
      await tap(tester, 'Put it live');
      expect(gateway.actions, isEmpty);
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      gateway.failNext = true;
      await tap(tester, 'Put it live');
      expect(
        find.text('TEST network failure; no confirmation.'),
        findsOneWidget,
      );
      expect(find.text('TEST Hyderabad'), findsOneWidget);
      await tap(tester, 'Put it live');
      expect(find.text('Your listing is live'), findsOneWidget);
      expect(find.text('Verified tenant views'), findsOneWidget);
      await tap(tester, 'See interested tenants');
      expect(
        find.text(
          'No enquiries yet. This updates when a verified tenant contacts TrustKeyper.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'owner cannot select an unverified tenant and selecting a checked tenant shows paused listing, not active tenancy',
    (tester) async {
      final gateway = TestOwnerLifecycleGateway();
      final original = testOwnerLifecycleProperty(status: 'listing_live');
      final record = OwnerPropertyRecord({
        ...original.data,
        'candidates': {
          'e' * 64: {
            'name': 'TEST Priya',
            'status': 'interested',
            'household': 3,
            'work': 'TEST workplace',
            'moveIn': '2026-11-01',
          },
        },
      });
      await open(
        tester,
        OwnerLifecycleScreen(
          property: record,
          gateway: gateway,
          proof: TestOwnerPhoneProof(),
          properties: OfflineOwnerPropertyGateway(),
        ),
      );
      await tap(tester, 'See interested tenants');
      await tap(tester, 'TEST Priya');
      await tap(tester, 'Choose TEST Priya');
      expect(gateway.actions, isEmpty);
      expect(find.text('Identity check pending'), findsOneWidget);
      final checked = OwnerPropertyRecord({
        ...record.data,
        'candidates': {
          'e' * 64: {
            ...record.data['candidates']['e' * 64],
            'identityCheck': {'checked': true},
          },
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: OwnerLifecycleScreen(
            key: const ValueKey('checked'),
            property: checked,
            gateway: gateway,
            proof: TestOwnerPhoneProof(),
            properties: OfflineOwnerPropertyGateway(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'See interested tenants');
      await tap(tester, 'TEST Priya');
      await tap(tester, 'Choose TEST Priya');
      expect(gateway.actions.last, 'choose_tenant');
      expect(find.text('Your listing is paused now.'), findsOneWidget);
      expect(
        find.text(
          'The agreement link appears only when the actual agreement is prepared.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'public listing phone OTP and private enquiry run without installing the app or entering private owner documents',
    (tester) async {
      final gateway = TestOwnerLifecycleGateway();
      final proof = TestListingPhoneProof();
      await open(
        tester,
        PublicOwnerListingScreen(id: 'a' * 64, gateway: gateway, proof: proof),
        size: const Size(320, 780),
      );
      expect(find.text('TEST public home'), findsOneWidget);
      await tap(tester, 'I am interested');
      await tester.enterText(find.byType(TextField), '2222222222');
      await tap(tester, 'Send OTP');
      expect(proof.phone, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tap(tester, 'Send OTP');
      expect(proof.phone, '+912222222222');
      await tester.enterText(
        find.descendant(
          of: find.byType(ApprovedOtpInput),
          matching: find.byType(TextField),
        ),
        '123456',
      );
      await tap(tester, 'Verify phone');
      expect(proof.confirmed, 1);
      expect(gateway.enquiries.single['action'], 'view');
      await tester.enterText(find.byType(TextFormField).at(0), 'TEST Priya');
      await tester.enterText(find.byType(TextFormField).at(1), '3');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'TEST workplace',
      );
      await tap(tester, 'Send to TrustKeyper');
      expect(gateway.enquiries.last['action'], 'interest');
      expect(find.text('Your interest is received'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
