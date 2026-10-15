import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trustkeyper/src/core/theme/app_colors.dart';
import 'package:trustkeyper/src/core/theme/app_theme.dart';
import 'package:trustkeyper/src/features/experiences/data/experience_catalog.dart';
import 'package:trustkeyper/src/features/journeys/data/journey_catalog.dart';
import 'package:trustkeyper/src/features/journeys/presentation/guided_journey_screen.dart';
import 'package:trustkeyper/src/features/auth/data/firebase_auth_service.dart';
import 'package:trustkeyper/src/features/auth/presentation/approved_auth_widgets.dart';
import 'package:trustkeyper/src/features/auth/presentation/auth_screens.dart';
import 'package:trustkeyper/src/features/auth/presentation/login_method.dart';
import 'package:trustkeyper/src/features/broker/data/broker_repository.dart';
import 'package:trustkeyper/src/features/broker/presentation/broker_shell.dart';
import 'package:trustkeyper/src/features/payments/presentation/payment_checkout_screen.dart';
import 'package:trustkeyper/src/features/admin/data/admin_repository.dart';
import 'package:trustkeyper/src/features/admin/presentation/admin_auth_screen.dart';
import 'package:trustkeyper/src/features/admin/presentation/admin_dashboard_screen.dart';

void main() {
  test('brand primary colour stays aligned with the design system', () {
    expect(AppColors.primary.toARGB32(), 0xFF3160FF);
  });

  test('every approved mobile journey has usable steps', () {
    final journeys = [
      JourneyCatalog.agreementApprovalOwner,
      JourneyCatalog.agreementApprovalTenant,
      JourneyCatalog.aadhaarSigning,
      JourneyCatalog.brokerSigningProgress,
      JourneyCatalog.moveIn,
      JourneyCatalog.tenantSetup,
      JourneyCatalog.tenantFirstPayment,
      JourneyCatalog.tenantRepair,
      JourneyCatalog.moveOutTenant,
      JourneyCatalog.ownerMoveOut,
      JourneyCatalog.brokerMoveOut,
      JourneyCatalog.brokerLateRent,
    ];

    expect(journeys, everyElement(isNotEmpty));
    expect(
      journeys.expand((journey) => journey),
      everyElement(
        predicate<JourneyStep>(
          (step) => step.title.isNotEmpty && step.action.isNotEmpty,
        ),
      ),
    );
  });

  testWidgets('approved OTP input renders six separate digit boxes', (
    tester,
  ) async {
    final controller = TextEditingController(text: '123456');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ApprovedOtpInput(controller: controller)),
      ),
    );

    for (var index = 0; index < 6; index += 1) {
      expect(find.byKey(ValueKey('otp-digit-$index')), findsOneWidget);
    }
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('login exposes complete phone and email authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    expect(find.text('Get OTP'), findsOneWidget);
    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.text('Email address'), findsOneWidget);
  });

  test(
    'Firebase billing failures are converted into an actionable OTP error',
    () {
      final message = firebaseAuthErrorMessage(
        code: 'internal-error',
        message: 'An internal error has occurred. [ BILLING_NOT_ENABLED ]',
      );

      expect(message, contains('Firebase phone billing is not enabled'));
      expect(message, isNot(contains('BILLING_NOT_ENABLED')));
    },
  );

  testWidgets(
    'email code screen shows the email and the correct resend cooldown',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const OtpScreen(
            destination: 'ajay@example.com',
            method: LoginMethod.email,
            challengeId: 'test-challenge',
          ),
        ),
      );
      expect(find.text('Sent to ajay@example.com'), findsOneWidget);
      expect(find.text('Send again in 1:00'), findsOneWidget);
      expect(
        find.text('Check your inbox and Spam. The code expires in 5 minutes.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('auth selector uses one clipped surface without white seams', (
    tester,
  ) async {
    var selected = LoginMethod.phone;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AuthMethodSelector(
              selected: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    final selector = tester.widget<Material>(
      find.byKey(const ValueKey('auth-method-selector')),
    );
    expect(selector.clipBehavior, Clip.antiAlias);
    expect(selector.shape, isA<StadiumBorder>());

    final selectedPhone = tester.widget<Ink>(
      find.byKey(const ValueKey('auth-method-phone')),
    );
    expect(
      (selectedPhone.decoration as BoxDecoration).color,
      AppColors.background,
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    final selectedEmail = tester.widget<Ink>(
      find.byKey(const ValueKey('auth-method-email')),
    );
    expect(
      (selectedEmail.decoration as BoxDecoration).color,
      AppColors.background,
    );
  });

  testWidgets('email verification screen explains delivery and recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const EmailVerificationScreen(email: 'ajay@example.com'),
      ),
    );

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('ajay@example.com'), findsOneWidget);
    expect(find.text('Resend verification email'), findsOneWidget);
    expect(find.text("I've verified my email"), findsOneWidget);
  });

  test('experience catalog lists 18 design groups, not visual parity', () {
    expect(ExperienceCatalog.all, hasLength(18));
    expect(
      ExperienceCatalog.all.map((experience) => experience.page),
      orderedEquals(List<int>.generate(18, (index) => index + 1)),
    );
    expect(
      ExperienceCatalog.all
          .where((experience) => experience.archived)
          .map((experience) => experience.page),
      orderedEquals([13, 14]),
    );
    expect(
      ExperienceCatalog.all.where(
        (experience) => !experience.archived && experience.steps.isNotEmpty,
      ),
      everyElement(
        predicate<ExperienceDefinition>(
          (experience) => experience.steps.every(
            (step) => step.title.isNotEmpty && step.action.isNotEmpty,
          ),
        ),
      ),
    );
  });

  testWidgets('payment checkout is visibly marked as test mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentCheckoutScreen(previewOnly: true)),
    );

    expect(find.text('Pay November rent'), findsOneWidget);
    expect(find.textContaining('SIMULATION ONLY'), findsOneWidget);
    expect(find.text('Simulate payment'), findsOneWidget);
    expect(find.textContaining('No money moves'), findsOneWidget);
  });

  test('broker greeting always comes from the persisted profile name', () {
    const profile = BrokerProfile(
      displayName: 'Ajay Bhatnagar',
      email: 'ajay@trustkeyper.com',
      phone: '+919999999999',
      approvalStatus: 'pending',
    );

    expect(profile.greetingName, 'Ajay');
    expect(profile.initial, 'A');
  });

  testWidgets('approved profile and role copy replaces preview UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileSetupScreen()),
    );

    expect(find.text('Welcome! What is your name?'), findsOneWidget);
    expect(find.text('As on your Aadhaar card.'), findsOneWidget);
    expect(find.text('Send OTP to email'), findsOneWidget);
    expect(find.text('Email *'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RoleSelectionScreen()),
    );

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Pick one. You can add another later.'), findsOneWidget);
    expect(find.text('I own a house and give it on rent'), findsOneWidget);
    expect(find.text('I live in a rented house'), findsOneWidget);
    expect(find.text('Preview all approved journeys'), findsNothing);
  });

  testWidgets('first-time broker sees their real name and empty data', (
    tester,
  ) async {
    final repository = _FakeBrokerRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrokerShell(approvalPending: true, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Namaste, Ajay'), findsOneWidget);
    expect(find.textContaining('Rahul'), findsNothing);
    expect(find.text('What do you want to do today?'), findsOneWidget);

    await tester.tap(find.text('Agreements'));
    await tester.pumpAndSettle();

    expect(find.text('No agreements yet'), findsOneWidget);
    expect(find.textContaining('Phoenix'), findsNothing);
  });

  test('admin records normalize live Firebase-shaped values', () {
    const record = AdminRecord(
      id: 'broker-ajay',
      path: 'users/broker-ajay',
      data: {
        'displayName': 'Ajay Bhatnagar',
        'roles': ['broker'],
        'approvalStatus': 'pending',
        'amountPaise': 4500000,
      },
    );

    expect(record.displayName, 'Ajay Bhatnagar');
    expect(record.hasRole('broker'), isTrue);
    expect(record.status, 'pending');
    expect(record.integer(const ['amountPaise']), 4500000);
  });

  test(
    'Razorpay TEST records cannot inflate live rent totals or late-rent counts',
    () {
      const data = AdminData(
        payments: [
          AdminRecord(
            id: 'test-paid',
            path: 'payments/test-paid',
            data: {'mode': 'test', 'status': 'paid', 'amountPaise': 3300000},
          ),
          AdminRecord(
            id: 'test-late',
            path: 'payments/test-late',
            data: {'mode': 'test', 'status': 'late', 'amountPaise': 1100000},
          ),
          AdminRecord(
            id: 'real-late',
            path: 'payments/real-late',
            data: {'mode': 'live', 'status': 'late', 'amountPaise': 1100000},
          ),
        ],
      );
      expect(data.payments.length, 3);
      expect(data.livePayments.map((payment) => payment.id), ['real-late']);
      expect(data.lateRent, 1);
    },
  );

  testWidgets('admin login renders on a desktop viewport', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: AdminLoginScreen(gateway: _FakeAdminAuthGateway())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Admin panel'), findsOneWidget);
    expect(find.text('Log in'), findsWidgets);
  });

  testWidgets('admin dashboard uses live records without seeded people', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeAdminRepository(
      const AdminData(
        users: [
          AdminRecord(
            id: 'broker-ajay',
            path: 'users/broker-ajay',
            data: {
              'displayName': 'Ajay Bhatnagar',
              'phone': '+919999999999',
              'roles': ['broker'],
              'approvalStatus': 'pending',
            },
          ),
          AdminRecord(
            id: 'broker-priya',
            path: 'users/broker-priya',
            data: {
              'displayName': 'Priya Sharma',
              'phone': '+919888888888',
              'roles': ['broker'],
              'approvalStatus': 'approved',
            },
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminDashboardScreen(
          repository: repository,
          adminDisplayName: 'Aman',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 broker approvals'), findsOneWidget);
    expect(find.textContaining('Rahul'), findsNothing);

    await tester.tap(find.text('Brokers'));
    await tester.pumpAndSettle();
    expect(find.text('Ajay Bhatnagar'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsNothing);

    await tester.tap(find.text('Approved').first);
    await tester.pumpAndSettle();
    expect(find.text('Ajay Bhatnagar'), findsNothing);
    expect(find.text('Priya Sharma'), findsOneWidget);

    await tester.tap(find.text('Waiting · 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(repository.approvedUserId, 'broker-ajay');
  });
}

class _FakeBrokerRepository implements BrokerRepository {
  @override
  Stream<List<BrokerAgreementSummary>> watchAgreements() =>
      Stream.value(const []);

  @override
  Stream<List<BrokerPaymentSummary>> watchPayments() => Stream.value(const []);

  @override
  Stream<BrokerProfile> watchProfile() => Stream.value(
    const BrokerProfile(
      displayName: 'Ajay Bhatnagar',
      email: 'ajay@trustkeyper.com',
      phone: '+919999999999',
      approvalStatus: 'pending',
    ),
  );
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository(this.data);

  final AdminData data;
  String? approvedUserId;

  @override
  Stream<AdminData> watchData() => Stream.value(data);

  @override
  Future<void> approveBroker(String userId) async {
    approvedUserId = userId;
  }

  @override
  Future<void> createRepairFromPhoto(AdminRecord photo) async {}

  @override
  Future<void> recordRentFollowUp(String paymentId, String action) async {}

  @override
  Future<void> rejectBroker(String userId, String reason, String note) async {}

  @override
  Future<void> requestPayoutAction(String payoutId, String action) async {}

  @override
  Future<void> reviewDocument(
    String documentId,
    String status, {
    String? reason,
  }) async {}

  @override
  Future<void> reviewPhoto(String path, String status) async {}

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {}

  @override
  Future<void> setAgreementStep(
    String agreementId,
    String step, {
    required int revision,
  }) async {}

  @override
  Future<void> returnAgreementDraft(
    String agreementId,
    String reason, {
    required int revision,
  }) async {}

  @override
  Future<void> setUserPaused(String userId, bool paused) async {}

  @override
  Future<void> updateMoveOut(String moveOutId, String status) async {}

  @override
  Future<void> updateRepair(
    String issueId,
    String status, {
    int? billPaise,
  }) async {}
}

class _FakeAdminAuthGateway implements AdminAuthGateway {
  @override
  Future<void> confirmCode(String code) async {}

  @override
  Future<bool> hasAdminAccess() async => false;

  @override
  Future<void> sendCode() async {}

  @override
  Future<AdminLoginResult> signIn(String email, String password) async =>
      const AdminLoginResult();

  @override
  Future<void> signOut() async {}
}
