import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import '../../features/broker/presentation/broker_web_entry_screen.dart';
import '../widgets/session_bound_screen.dart';
import '../../features/agreement_approvals/presentation/recipient_approval_screen.dart';
import '../../features/document_requests/presentation/recipient_document_screen.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_auth_screen.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/auth/presentation/login_method.dart';
import '../../features/auth/data/firebase_auth_service.dart';
import '../../features/broker/presentation/broker_shell.dart';
import '../../features/broker/presentation/broker_agreement_wizard.dart';
import '../../features/broker/presentation/unfinished_drafts_screen.dart';
import '../../features/broker/presentation/broker_updates_screen.dart';
import '../../features/broker/presentation/broker_document_review_screen.dart';
import '../../features/broker/presentation/broker_start_screen.dart';
import '../../features/broker/presentation/agreement_renewal_screen.dart';
import '../../features/broker/presentation/sign_only_screen.dart';
import '../../features/broker/presentation/signing_requests_screen.dart';
import '../../features/broker/presentation/broker_property_screen.dart';
import '../../features/broker/presentation/onboarding_agreement_screens.dart';
import '../../features/broker/presentation/send_for_signing_screens.dart';
import '../../features/broker/presentation/onboarding_house_screens.dart';
import '../../features/broker/presentation/onboarding_start_screens.dart';
import '../../features/broker/data/broker_property_repository.dart';
import '../../features/experiences/presentation/experience_hub_screen.dart';
import '../../features/owner/presentation/owner_shell.dart';
import '../../features/owner/presentation/owner_property_setup_screen.dart';
import '../../features/owner/presentation/owner_property_checks_screen.dart';
import '../../features/owner/presentation/public_owner_listing_screen.dart';
import '../../features/owner/presentation/manager_callback_screen.dart';
import '../../features/payments/presentation/payment_checkout_screen.dart';
import '../../features/tenant/presentation/tenant_shell.dart';
import '../../features/account/data/account_gateway.dart';
import '../../features/account/presentation/account_screens.dart';
import '../../features/tenancy/move_in_screen.dart';
import '../../features/tenancy/tenancy_picker_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/listing/:id',
      builder: (context, state) =>
          PublicOwnerListingScreen(id: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/agreement/reply',
      builder: (context, state) => RecipientApprovalScreen(
        token: state.uri.queryParameters['token'] ?? '',
      ),
    ),
    GoRoute(
      path: '/documents/request',
      builder: (context, state) => RecipientDocumentScreen(
        token: state.uri.queryParameters['token'] ?? '',
      ),
    ),
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => OnboardingScreen(
        initialPage:
            int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 0,
      ),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => LoginScreen(
        // Back arrow only when the user arrived from the welcome carousel.
        onBack: state.uri.queryParameters['from'] == 'onboarding'
            ? () => context.go('/onboarding?page=3')
            : null,
      ),
    ),
    GoRoute(
      path: '/account-paused',
      builder: (context, state) => const AccountPausedScreen(),
    ),
    GoRoute(
      path: '/broker/start',
      builder: (context, state) => const BrokerStartScreen(),
    ),
    GoRoute(
      path: '/broker/agreement/steps',
      builder: (context, state) => const BrokerAgreementStepsScreen(),
    ),
    GoRoute(
      path: '/broker/sign-only',
      builder: (context, state) =>
          const SessionBoundScreen(child: SignOnlyScreen()),
    ),
    GoRoute(
      path: '/broker/signing-requests',
      builder: (context, state) =>
          const SessionBoundScreen(child: SigningRequestsScreen()),
    ),
    GoRoute(
      path: '/admin/signing-requests',
      builder: (context, state) =>
          const AdminAccessGate(child: SigningRequestsScreen(admin: true)),
    ),
    GoRoute(
      path: '/admin/owner-property-checks',
      builder: (context, state) =>
          const AdminAccessGate(child: OwnerPropertyChecksScreen()),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final method =
            state.uri.queryParameters['method'] == LoginMethod.email.name
            ? LoginMethod.email
            : LoginMethod.phone;
        return OtpScreen(
          destination: state.uri.queryParameters['destination'] ?? '',
          method: method,
          challengeId: state.uri.queryParameters['challengeId'],
          profileEmailVerification:
              method == LoginMethod.email &&
              state.uri.queryParameters['purpose'] == 'profile-email',
          profilePhoneVerification:
              method == LoginMethod.phone &&
              state.uri.queryParameters['purpose'] == 'profile-phone',
        );
      },
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => EmailVerificationScreen(
        email: state.uri.queryParameters['email'] ?? '',
      ),
    ),
    GoRoute(
      path: '/profile-setup',
      builder: (context, state) {
        final auth = FirebaseAuthService.instance;
        final user = auth.currentUser;
        return ProfileSetupScreen(
          initialName: auth.pendingName ?? user?.displayName,
          initialEmail: auth.pendingEmail,
          verifiedEmail: user?.emailVerified == true ? user?.email : null,
          requiresPhoneVerification:
              user?.emailVerified == true && user?.phoneNumber == null,
        );
      },
    ),
    GoRoute(
      path: '/roles',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/switch-role',
      builder: (context, state) => const AccountRoleScreen(),
    ),
    GoRoute(
      path: '/experiences',
      builder: (context, state) => const ExperienceHubScreen(),
    ),
    GoRoute(
      path: '/experience/:id',
      builder: (context, state) =>
          ExperienceFlowScreen(experienceId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/broker',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: BrokerShell(
          approvalPending: state.uri.queryParameters['approval'] == 'pending',
        ),
      ),
    ),
    GoRoute(
      path: '/broker/approval',
      builder: (context, state) {
        final user = FirebaseAuthService.instance.currentUser;
        if (kIsWeb) {
          return BrokerWebEntryScreen(phone: user?.phoneNumber ?? '');
        }
        return BrokerApprovalScreen(
          phoneVerified: user?.phoneNumber?.isNotEmpty == true,
          emailVerified: user?.emailVerified == true,
        );
      },
    ),
    GoRoute(path: '/owner', builder: (context, state) => const OwnerShell()),
    GoRoute(
      path: '/owner/support',
      builder: (context, state) => const ManagerCallbackScreen(),
    ),
    GoRoute(
      path: '/broker/agreement',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: state.extra is BrokerProperty
            ? BrokerAgreementWizard(property: state.extra as BrokerProperty)
            : const BrokerPropertyScreen(),
      ),
    ),
    GoRoute(
      path: '/broker/draft/:id',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: BrokerDraftScreen(
          id: state.pathParameters['id']!,
          role: state.uri.queryParameters['role'],
          partyId: state.uri.queryParameters['partyId'],
        ),
      ),
    ),
    GoRoute(
      path: '/broker/unfinished',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: const UnfinishedDraftsScreen(),
      ),
    ),
    GoRoute(
      path: '/broker/progress/:id',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: ResumeDraftProgressScreen(
          id: state.pathParameters['id']!,
          role: state.uri.queryParameters['role'],
          partyId: state.uri.queryParameters['partyId'],
        ),
      ),
    ),
    GoRoute(
      path: '/broker/updates',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: const BrokerUpdatesScreen(),
      ),
    ),
    GoRoute(
      path: '/broker/documents/:id',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: BrokerDocumentReviewScreen(
          requestId: state.pathParameters['id']!,
        ),
      ),
    ),
    GoRoute(
      path: '/broker/property',
      builder: (context, state) => const OnboardChooseScreen(),
    ),
    GoRoute(
      path: '/broker/property/manual',
      builder: (context, state) => const BrokerPropertyScreen(),
    ),
    GoRoute(
      path: '/broker/property/new',
      builder: (context, state) => const OnboardNewScreen(),
    ),
    GoRoute(
      path: '/broker/onboarding/:id',
      builder: (context, state) => PropertySetupScreen(id: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'paper/:key',
          builder: (context, state) => PaperDetailScreen(id: state.pathParameters['id']!, paperKey: state.pathParameters['key']!, owner: int.tryParse(state.uri.queryParameters['o'] ?? '') ?? 0),
        ),
        GoRoute(
          path: 'ask/:key',
          builder: (context, state) => AskAgainScreen(id: state.pathParameters['id']!, paperKey: state.pathParameters['key']!, owner: int.tryParse(state.uri.queryParameters['o'] ?? '') ?? 0),
        ),
        GoRoute(
          path: 'agreement',
          builder: (context, state) => OwnerAgreementScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) => AgreementEditScreen(id: state.pathParameters['id']!, part: state.uri.queryParameters['part'] ?? 'fee'),
        ),
        GoRoute(
          path: 'sent',
          builder: (context, state) => AgreementSentScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'questions',
          builder: (context, state) => AgreementQuestionsScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'draft',
          builder: (context, state) => DraftScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'change',
          builder: (context, state) => AskChangeScreen(id: state.pathParameters['id']!, clause: state.uri.queryParameters['clause']),
        ),
        GoRoute(
          path: 'changes',
          builder: (context, state) => ChangesScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'change/:cid',
          builder: (context, state) => ChangeDecisionScreen(id: state.pathParameters['id']!, changeId: state.pathParameters['cid']!),
        ),
        GoRoute(
          path: 'versions',
          builder: (context, state) => VersionsScreen(id: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'sign',
          builder: (context, state) => SignScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/broker/signing',
      builder: (context, state) => SessionBoundScreen(
        expectedUid: FirebaseAuthService.instance.currentUser?.uid,
        child: const BrokerShell(approvalPending: false, initialTab: 1),
      ),
    ),
    GoRoute(
      path: '/broker/move-in',
      builder: (context, state) =>
          state.uri.queryParameters['agreementId'] is String
          ? MoveInScreen(
              agreementId: state.uri.queryParameters['agreementId']!,
              role: 'broker',
            )
          : const TenancyPickerScreen(role: 'broker'),
    ),
    GoRoute(
      path: '/broker/move-out',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'broker', initialPage: 'notice'),
    ),
    GoRoute(
      path: '/broker/late-rent',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'broker', initialPage: 'rent'),
    ),
    GoRoute(
      path: '/broker/renew',
      builder: (context, state) => const AgreementRenewalScreen(),
    ),
    GoRoute(
      path: '/broker/bank',
      builder: (context, state) => SessionBoundScreen(
        child: AccountBankScreen(gateway: FirebaseAccountGateway()),
      ),
    ),
    GoRoute(
      path: '/broker/review',
      builder: (context, state) =>
          const ExperienceFlowScreen(experienceId: 'review-edit-send'),
    ),
    GoRoute(
      path: '/owner/agreement',
      builder: (context, state) => OwnerShell(
        initialTab: 1,
        agreementId: state.uri.queryParameters['id'],
      ),
    ),
    GoRoute(
      path: '/owner/sign',
      builder: (context, state) => const OwnerShell(initialTab: 1),
    ),
    GoRoute(
      path: '/owner/move-out',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'owner', initialPage: 'notice'),
    ),
    GoRoute(
      path: '/owner/onboarding',
      builder: (context, state) =>
          const SessionBoundScreen(child: OwnerPropertySetupScreen()),
    ),
    GoRoute(
      path: '/owner/late-rent',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'owner', initialPage: 'rent'),
    ),
    GoRoute(path: '/tenant', builder: (context, state) => const TenantShell()),
    GoRoute(
      path: '/tenant/setup',
      builder: (context, state) => const TenantShell(),
    ),
    GoRoute(
      path: '/tenant/pay',
      builder: (context, state) => const PaymentCheckoutScreen(),
    ),
    GoRoute(
      path: '/tenant/agreement',
      builder: (context, state) => const TenantShell(),
    ),
    GoRoute(
      path: '/tenant/sign',
      builder: (context, state) => const TenantShell(),
    ),
    GoRoute(
      path: '/tenant/repair',
      builder: (context, state) => const TenantShell(initialTab: 2),
    ),
    GoRoute(
      path: '/tenant/move-out',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'tenant', initialPage: 'notice'),
    ),
    GoRoute(
      path: '/tenant/late-rent',
      builder: (context, state) =>
          const TenancyPickerScreen(role: 'tenant', initialPage: 'rent'),
    ),
    GoRoute(
      path: '/admin/login',
      builder: (context, state) => const AdminLoginScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) =>
          const AdminAccessGate(child: AdminDashboardScreen()),
    ),
  ],
);
