import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'src/core/testing/approval_fixture.dart';
import 'src/core/testing/payment_fixture.dart';
import 'src/core/testing/repair_fixture.dart';
import 'src/core/testing/inspection_fixture.dart';
import 'src/core/testing/tenancy_fixture.dart';
import 'src/core/testing/move_out_fixture.dart';
import 'src/features/tenancy/move_out_screen.dart';
import 'src/core/testing/renewal_fixture.dart';
import 'src/core/testing/callback_fixture.dart';
import 'src/core/testing/signing_fixture.dart';
import 'src/core/testing/owner_property_fixture.dart';
import 'src/features/owner/presentation/owner_property_setup_screen.dart';
import 'src/features/broker/data/agreement_imports.dart';
import 'src/features/broker/presentation/sign_only_screen.dart';
import 'src/features/owner/presentation/manager_callback_screen.dart';
import 'src/features/broker/presentation/agreement_renewal_screen.dart';
import 'src/features/tenancy/move_in_screen.dart';
import 'src/features/inspections/inspection_screen.dart';
import 'src/features/repairs/presentation/repair_detail_screen.dart';
import 'src/features/payments/presentation/rent_payment_screen.dart';
import 'src/features/agreement_copies/agreement_copies.dart';
import 'src/features/agreement_copies/agreement_copy_screen.dart';
import 'src/features/agreement_approvals/presentation/recipient_approval_screen.dart';
import 'package:go_router/go_router.dart';

import 'src/core/theme/app_theme.dart';
import 'src/core/testing/document_fixture.dart';
import 'src/core/testing/tenant_setup_fixture.dart';
import 'src/core/testing/account_fixture.dart';
import 'src/features/account/presentation/account_screens.dart';
import 'src/features/tenant/presentation/tenant_setup_screen.dart';
import 'src/features/broker/presentation/broker_records_screen.dart';
import 'src/core/testing/document_request_fixture.dart';
import 'src/core/testing/broker_updates_fixture.dart';
import 'src/features/broker/presentation/broker_updates_screen.dart';
import 'src/features/broker/presentation/broker_agreements_list.dart';
import 'src/features/broker/data/agreement_progress_repository.dart';
import 'src/core/testing/recipient_fixture.dart';
import 'src/core/testing/participant_fixture.dart';
import 'src/features/participants/presentation/participant_workspace_screen.dart';
import 'src/features/document_requests/data/document_request_repository.dart';
import 'src/features/document_requests/presentation/recipient_document_screen.dart';
import 'src/core/widgets/approved_navigation.dart';
import 'src/features/auth/presentation/auth_screens.dart';
import 'src/features/auth/data/account_roles.dart';
import 'src/features/auth/presentation/login_method.dart';
import 'src/features/broker/data/broker_property_repository.dart';
import 'src/features/broker/data/broker_repository.dart';
import 'src/features/broker/data/agreement_draft.dart';
import 'src/features/broker/data/agreement_draft_repository.dart';
import 'src/features/broker/data/private_documents.dart';
import 'src/features/broker/presentation/private_documents_screen.dart';
import 'src/features/broker/data/demo_agreement.dart';
import 'src/features/broker/presentation/demo_agreement_screen.dart';
import 'src/features/broker/presentation/broker_agreement_wizard.dart';
import 'src/features/broker/presentation/approved_broker_home.dart';
import 'src/features/broker/presentation/broker_property_screen.dart';
import 'src/features/broker/presentation/broker_start_screen.dart';

void main() {
  if (!const bool.fromEnvironment('TRUSTKEYPER_UI_TEST')) {
    throw StateError(
      'Build this entry point with TRUSTKEYPER_UI_TEST=true so it cannot use the live package identity.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UiTestApp());
}

class UiTestApp extends StatelessWidget {
  UiTestApp({super.key, this.documentNow}) {
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const _Gallery()),
        GoRoute(
          path: '/ui-test/account/profile',
          builder: (context, state) => Scaffold(
            body: SafeArea(
              child: AccountProfilePanel(
                name: 'Rahul Sharma',
                phone: '+91 98480 11223',
                role: 'broker',
                bankName: 'SBI',
                bankLast4: '7766',
                gateway: OfflineAccountGateway(),
                onSignedOut: () => context.go('/'),
              ),
            ),
            bottomNavigationBar: ApprovedBrokerNavigation(
              selectedIndex: 4,
              onSelected: (_) => context.go('/'),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/account/details',
          builder: (context, state) =>
              AccountDetailsScreen(gateway: OfflineAccountGateway()),
        ),
        GoRoute(
          path: '/ui-test/account/help',
          builder: (context, state) => const AccountHelpScreen(),
        ),
        GoRoute(
          path: '/ui-test/account/close',
          builder: (context, state) => AccountClosureScreen(
            gateway: OfflineAccountGateway(),
            onSignedOut: () => context.go('/'),
          ),
        ),
        GoRoute(
          path: '/ui-test/tenant-setup/:step',
          builder: (context, state) => TenantSetupScreen(
            agreementId: 'offline-home',
            gateway: OfflineTenantSetupGateway(
              step: int.parse(state.pathParameters['step']!),
            ),
            onDone: () => context.go('/'),
          ),
        ),
        GoRoute(
          path: '/ui-test/broker-records',
          builder: (context, state) => Scaffold(
            body: SafeArea(
              child: BrokerRecordsScreen(
                agreements: Stream.value([
                  BrokerAgreementSummary(
                    id: 'offline-record',
                    property: 'Phoenix Towers 402',
                    propertyId: 'offline-property',
                    people: 'Rajesh Kumar · Priya Sharma',
                    status: 'draft',
                    monthlyRentPaise: 2200000,
                    updatedAt: null,
                    details: {
                      'owners': [
                        {
                          'id': 'owner-one',
                          'name': 'Rajesh Kumar',
                          'phone': '+919988776655',
                          'email': 'owner@test.invalid',
                        },
                      ],
                      'tenants': [
                        {
                          'id': 'tenant-one',
                          'name': 'Priya Sharma',
                          'phone': '+919876543211',
                        },
                      ],
                    },
                  ),
                ]),
                properties: Stream.value([
                  BrokerProperty(
                    id: 'offline-property',
                    address: 'Phoenix Towers 402',
                    rooms: '2 BHK',
                    floor: 4,
                    totalFloors: 8,
                    furnishing: 'Empty',
                  ),
                ]),
                onAddProperty: () => context.push('/broker/agreement'),
                onOpenAgreement: (_) => context.push('/broker/agreement'),
                onPhotoChecks: (_, _) => context.push('/ui-test/photo-checks'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/field-guidance',
          builder: (context, state) => BrokerAgreementWizard(
            property: BrokerProperty(
              id: 'offline-missing-address',
              address: '',
              rooms: '2 BHK',
              floor: 4,
              totalFloors: 8,
              furnishing: 'Empty',
            ),
            repository: drafts,
            propertyRepository: properties,
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: documentStore,
              currentUid: () => 'offline-test',
            ),
            pickDocument: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            takeDocumentPhoto: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/broker-updates',
          builder: (context, state) => BrokerUpdatesScreen(
            repository: brokerUpdates,
            now: () => DateTime(2026, 10, 11, 20),
            onOpen: (update) => context.push(
              '/broker/progress/offline-saved-flow?role=${update.data['role']}&partyId=${update.data['partyId']}',
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/broker-drafts',
          builder: (context, state) => Scaffold(
            body: SafeArea(
              child: BrokerAgreementsList(
                agreements: Stream.value([]),
                approvalPending: false,
                progressRepository: brokerProgress,
                updates: brokerUpdates,
                itemBuilder: (_, agreement) => Text(agreement.property),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/broker/updates',
          builder: (context, state) => BrokerUpdatesScreen(
            repository: brokerUpdates,
            now: () => DateTime(2026, 10, 11, 20),
            onOpen: (update) => context.push(
              '/broker/progress/offline-saved-flow?role=${update.data['role']}&partyId=${update.data['partyId']}',
            ),
          ),
        ),
        GoRoute(
          path: '/broker/progress/:id',
          builder: (context, state) => BrokerAgreementWizard(
            initialProgress: brokerProgress.saved,
            progressRepository: brokerProgress,
            initialPartyRole: state.uri.queryParameters['role'],
            initialPartyId: state.uri.queryParameters['partyId'],
            repository: drafts,
            documentRequests: OfflineDocumentRequests(),
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: documentStore,
              currentUid: () => 'offline-test',
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/broker-owner-links',
          builder: (context, state) => BrokerAgreementWizard(
            initialProgress: AgreementProgress(
              draft: AgreementDraft(
                id: 'offline-owner-links',
                propertyAddress: 'OFFLINE TEST · Phoenix Towers 402',
                owners: const [
                  AgreementParty(
                    id: 'offline-owner-1',
                    name: 'Test Rajesh Kumar',
                    phone: '+919000000001',
                    email: 'owner@example.invalid',
                  ),
                  AgreementParty(
                    id: 'offline-owner-2',
                    name: 'Test Owner Two',
                    phone: '+919000000002',
                  ),
                ],
                tenants: const [
                  AgreementParty(
                    id: 'offline-tenant-1',
                    name: 'Test Tenant',
                    phone: '+919000000003',
                    rentSharePaise: 2200000,
                    depositSharePaise: 4400000,
                  ),
                ],
                monthlyRentPaise: 2200000,
                maintenancePaise: 0,
                depositPaise: 4400000,
                startDate: DateTime(2026, 10, 1),
                endDate: DateTime(2027, 8, 31),
                ownerBrokeragePaise: 0,
                tenantBrokeragePaise: 0,
                revision: 1,
              ),
              stage: 'ownerPapers',
              person: 0,
            ),
            repository: drafts,
            documentRequests: OfflineDocumentRequests(),
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: documentStore,
              currentUid: () => 'offline-test-broker',
            ),
            pickDocument: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            takeDocumentPhoto: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/broker-documents/:role/:status',
          builder: (context, state) => _brokerDocuments(
            state.pathParameters['role']!,
            state.pathParameters['status']!,
          ),
        ),
        GoRoute(
          path: '/ui-test/owner-callback/:status',
          builder: (context, state) => ManagerCallbackScreen(
            gateway: OfflineCallbackFixture(
              status: state.pathParameters['status'] ?? 'none',
            ),
            offline: true,
          ),
        ),
        GoRoute(
          path: '/broker/renew',
          builder: (context, state) => AgreementRenewalScreen(
            gateway: OfflineRenewalGateway(
              saveDraft: (draft) => drafts.records[draft.id] = draft,
            ),
            offline: true,
            now: DateTime(2026, 10, 10),
            onDraft: (id) => router.push('/ui-test/renewal-draft/$id'),
          ),
        ),
        GoRoute(
          path: '/ui-test/renewal-draft/:id',
          builder: (context, state) => BrokerAgreementWizard(
            initialDraft: drafts.records[state.pathParameters['id']],
            repository: drafts,
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: documentStore,
              currentUid: () => 'ui-test-broker',
            ),
            pickDocument: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            takeDocumentPhoto: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            onSaved: () => router.go('/'),
          ),
        ),
        GoRoute(
          path: '/ui-test/move-in/:stage',
          builder: (context, state) {
            final stage = state.pathParameters['stage'];
            final rent = stage?.startsWith('rent-') ?? false;
            final fixture = OfflineTenancyFixture(
              role: stage == 'tenant' || stage == 'rent-tenant'
                  ? 'tenant'
                  : stage == 'rent-owner'
                  ? 'owner'
                  : 'broker',
              ready: stage != 'photos',
              active: stage == 'notice' || rent,
            );
            if (rent) fixture.data['today'] = '2026-11-08';
            return MoveInScreen(
              agreementId: 'offline-home',
              role: fixture.role,
              gateway: OfflineTenancyGateway(fixture),
              photos: fixture,
              camera: fixture.camera,
              offline: true,
              initialPage: rent
                  ? 'rent'
                  : stage == 'notice'
                  ? 'notice'
                  : 'checklist',
            );
          },
        ),
        GoRoute(
          path: '/ui-test/move-out/:stage',
          builder: (context, state) {
            final stage = state.pathParameters['stage'];
            final fixture = OfflineMoveOutFixture(
              role: stage == 'owner'
                  ? 'owner'
                  : stage == 'tenant' || stage == 'tenant-keys'
                  ? 'tenant'
                  : stage == 'admin'
                  ? 'admin'
                  : 'broker',
              ready: stage != 'photos' && stage != 'tenant-keys',
              published: ['owner', 'tenant', 'admin'].contains(stage),
              disputed: stage == 'admin',
            );
            return MoveOutScreen(
              agreementId: 'offline-move-out',
              role: fixture.role,
              gateway: OfflineMoveOutGateway(fixture),
              photos: fixture,
              camera: fixture.camera,
              offline: true,
              initialPage: stage == 'tenant-keys'
                  ? 'keys'
                  : ['owner', 'tenant', 'admin'].contains(stage)
                  ? 'report'
                  : 'checklist',
            );
          },
        ),
        GoRoute(
          path: '/ui-test/photo-checks',
          builder: (context, state) {
            final fixture = OfflineInspectionFixture();
            return InspectionScreen(
              propertyId: 'offline-flat',
              gateway: fixture,
              camera: fixture.camera,
              offline: true,
            );
          },
        ),
        GoRoute(
          path: '/preview/switch-role',
          builder: (context, state) =>
              AccountRoleScreen(gateway: OfflineAccountRoleGateway()),
        ),
        GoRoute(
          path: '/ui-test/repairs/:stage',
          builder: (context, state) {
            final fixture = OfflineRepairFixture(
              role: state.pathParameters['stage'] == 'tenant'
                  ? 'tenant'
                  : 'owner',
              completed: state.pathParameters['stage'] != 'approval',
            );
            return RepairDetailScreen(
              issueId: 'offline-repair',
              gateway: fixture,
              photoReader: fixture,
              offline: true,
            );
          },
        ),
        GoRoute(
          path: '/ui-test/payments/:stage',
          builder: (context, state) => RentPaymentScreen(
            agreementId: 'offline-no-payment',
            revision: 1,
            offlineFixture: true,
            gateway: OfflinePaymentFixture(
              firstPayment: state.pathParameters['stage'] == 'first',
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/agreement-copy',
          builder: (context, state) => AgreementCopyScreen(
            agreementId: 'offline-demo-copy',
            revision: 1,
            demo: true,
            role: 'owner',
            reader: () async => AgreementCopyFile(
              name: 'TEST demo agreement.pdf',
              bytes: testDocumentPdf(),
              mode: 'demo',
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/workspace/:role',
          builder: (context, state) {
            final owner = state.pathParameters['role'] == 'owner';
            final fixture = OfflineParticipantFixture(
              empty: state.uri.queryParameters['empty'] == 'true',
            );
            return ParticipantWorkspaceScreen(
              repository: fixture,
              role: owner ? 'owner' : 'tenant',
              identity: owner
                  ? OfflineParticipantFixture.owner
                  : OfflineParticipantFixture.tenant,
              issueWriter: fixture,
              photoReader: fixture,
              now: DateTime(2026, 10, 9),
            );
          },
        ),
        GoRoute(
          path: '/ui-test/recipient/:paper',
          builder: (context, state) => RecipientDocumentScreen(
            token:
                '${List.filled(64, 'a').join()}.${List.filled(43, 'b').join()}',
            gateway: OfflineRecipientFixture(
              paper: RequestedPaper.values.byName(
                state.pathParameters['paper']!,
              ),
            ),
            pickFile: (_) async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/approval/:role',
          builder: (context, state) => RecipientApprovalScreen(
            token:
                '${List.filled(64, 'a').join()}.${List.filled(43, 'b').join()}',
            gateway: OfflineApprovalFixture(
              role: state.pathParameters['role']!,
              changed: state.uri.queryParameters['changed'] == 'true',
            ),
          ),
        ),
        GoRoute(
          path: '/preview/:screen',
          builder: (context, state) {
            final name = state.pathParameters['screen'];
            final screen = switch (name) {
              'onboarding' => const OnboardingScreen(),
              'login' => const LoginScreen(),
              'phone-otp' => const OtpScreen(
                destination: '9999999999',
                method: LoginMethod.phone,
              ),
              'email-otp' => const OtpScreen(
                destination: 'demo@example.com',
                method: LoginMethod.email,
              ),
              'profile' => const ProfileSetupScreen(),
              'roles' => const RoleSelectionScreen(),
              'approval-pending' => const BrokerApprovalScreen(),
              'approval-verified' => const BrokerApprovalScreen(
                phoneVerified: true,
                emailVerified: true,
              ),
              'paused' => const AccountPausedScreen(),
              'broker-home' => _Home(),
              _ => const _Unavailable(
                'This screen has not been implemented in the UI-test gallery.',
              ),
            };
            return name == 'onboarding' || name == 'broker-home'
                ? screen
                : AbsorbPointer(child: screen);
          },
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const AbsorbPointer(child: LoginScreen()),
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
          path: '/broker/property',
          builder: (context, state) =>
              BrokerPropertyScreen(repository: properties),
        ),
        GoRoute(
          path: '/broker/agreement',
          builder: (context, state) => _PropertyResult(
            property: state.extra is BrokerProperty
                ? state.extra as BrokerProperty
                : null,
          ),
        ),
        GoRoute(
          path: '/ui-test/agreement',
          builder: (context, state) => BrokerAgreementWizard(
            property: BrokerProperty(
              id: 'ui-test-house',
              address: 'UI Test Flat 402, Test Towers',
              rooms: '2 BHK',
              floor: 4,
              totalFloors: 8,
              furnishing: 'Empty',
            ),
            repository: drafts,
            documentFactory: (draft) => PrivateDocuments(
              draftId: draft.id,
              revision: draft.revision,
              partyIds: [
                ...draft.owners,
                ...draft.tenants,
              ].map((party) => party.id).toSet(),
              store: documentStore,
              currentUid: () => 'ui-test-broker',
            ),
            pickDocument: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            takeDocumentPhoto: () async => DocumentFile(
              name: 'TEST-DOCUMENT-NOT-VALID.pdf',
              bytes: testDocumentPdf(),
            ),
            onSaved: () => router.go('/'),
          ),
        ),
        GoRoute(
          path: '/ui-test/demo-agreement',
          builder: (context, state) => DemoAgreementScreen(
            agreement: DemoAgreement(
              AgreementDraft(
                id: 'offline-demo-agreement',
                propertyAddress: 'UI Test Flat 402, Test Towers',
                owners: const [
                  AgreementParty(
                    id: 'owner-test',
                    name: 'Test Owner',
                    phone: '+919000000001',
                  ),
                ],
                tenants: const [
                  AgreementParty(
                    id: 'tenant-test',
                    name: 'Test Tenant',
                    phone: '+919000000002',
                    rentSharePaise: 2200000,
                    depositSharePaise: 4400000,
                  ),
                ],
                monthlyRentPaise: 2200000,
                maintenancePaise: 0,
                depositPaise: 4400000,
                startDate: DateTime(2026, 10, 1),
                endDate: DateTime(2027, 8, 31),
                ownerBrokeragePaise: 1100000,
                tenantBrokeragePaise: 2200000,
                lockInMonths: 6,
                noticeMonths: 1,
                revision: 1,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/ui-test/documents',
          builder: (context, state) => PrivateDocumentsScreen(
            draft: AgreementDraft(
              id: 'ui-test-documents',
              propertyAddress: 'Offline test flat',
              owners: const [
                AgreementParty(
                  id: 'owner-test',
                  name: 'Test Owner',
                  phone: '+919000000001',
                ),
              ],
              tenants: const [
                AgreementParty(
                  id: 'tenant-test',
                  name: 'Test Tenant',
                  phone: '+919000000002',
                ),
              ],
              monthlyRentPaise: 100000,
              maintenancePaise: 0,
              depositPaise: 100000,
              startDate: DateTime(2026, 10, 1),
              endDate: DateTime(2027, 8, 31),
              ownerBrokeragePaise: 0,
              tenantBrokeragePaise: 0,
              revision: 1,
            ),
            documents: PrivateDocuments(
              draftId: 'ui-test-documents',
              revision: 1,
              partyIds: {'owner-test', 'tenant-test'},
              store: documentStore,
              currentUid: () => 'offline-test',
            ),
            pickFile: () async => DocumentFile(
              name: 'Offline-test-fixture.pdf',
              bytes: testDocumentPdf(),
            ),
          ),
        ),
        GoRoute(
          path: '/broker/sign-only',
          builder: (context, state) => SignOnlyScreen(
            gateway: OfflineSigningGateway(),
            offline: true,
            picker: (camera) async => AgreementPageFile(
              name: 'OFFLINE TEST agreement.pdf',
              bytes: testDocumentPdf(),
            ),
          ),
        ),
        for (final path in ['/broker/bank'])
          GoRoute(
            path: path,
            builder: (context, state) => const _Unavailable(
              'This downstream workflow is still incomplete. No account, bank, payment or document is changed.',
            ),
          ),
        GoRoute(
          path: '/owner/onboarding',
          builder: (context, state) =>
              OwnerPropertySetupScreen(gateway: ownerProperties, offline: true),
        ),
      ],
    );
  }

  late final GoRouter router;
  final DateTime Function()? documentNow;
  final properties = UiTestPropertyRepository();
  final drafts = UiTestDraftRepository();
  final brokerProgress = OfflineBrokerProgress();
  final brokerUpdates = OfflineBrokerUpdates();
  final documentStore = UiTestDocumentStore();
  final ownerProperties = OfflineOwnerPropertyGateway();

  Widget _brokerDocuments(String role, String status) {
    final party = AgreementParty(
      id: '$role-1',
      name: role == 'owner' ? 'Rajesh Kumar' : 'Priya Sharma',
      phone: role == 'owner' ? '+919988776655' : '+919876543211',
      email: role == 'owner' ? 'rajesh.kumar@gmail.com' : '',
    );
    final draft = AgreementDraft(
      id: 'offline-design-$role-$status',
      propertyAddress: 'Phoenix Towers 402',
      owners: [
        if (role == 'owner')
          party
        else
          const AgreementParty(
            id: 'owner-1',
            name: 'Rajesh Kumar',
            phone: '+919988776655',
          ),
        const AgreementParty(
          id: 'owner-2',
          name: 'Owner Two',
          phone: '+919000000002',
        ),
      ],
      tenants: [
        if (role == 'tenant')
          party
        else
          const AgreementParty(
            id: 'tenant-1',
            name: 'Priya Sharma',
            phone: '+919876543211',
          ),
        const AgreementParty(
          id: 'tenant-2',
          name: 'Tenant Two',
          phone: '+919000000004',
        ),
      ],
      monthlyRentPaise: 2200000,
      maintenancePaise: 0,
      depositPaise: 4400000,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2027, 8, 31),
      ownerBrokeragePaise: 0,
      tenantBrokeragePaise: 0,
      revision: 1,
    );
    final requests = OfflineBrokerDocumentStates(
      party,
      status,
      now: documentNow,
    );
    return BrokerAgreementWizard(
      key: ValueKey('offline-design-$role-$status'),
      initialProgress: AgreementProgress(
        draft: draft,
        stage: role == 'owner' ? 'ownerPapers' : 'tenantPapers',
        person: 0,
      ),
      repository: drafts,
      documentRequests: requests,
      documentNow: documentNow,
      documentFactory: (draft) => PrivateDocuments(
        draftId: draft.id,
        revision: draft.revision,
        partyIds: [
          ...draft.owners,
          ...draft.tenants,
        ].map((party) => party.id).toSet(),
        store: documentStore,
        currentUid: () => 'offline-test-broker',
      ),
      pickDocument: () async => DocumentFile(
        name: 'TEST-DOCUMENT-NOT-VALID.pdf',
        bytes: testDocumentPdf(),
      ),
      takeDocumentPhoto: () async => DocumentFile(
        name: 'TEST-DOCUMENT-NOT-VALID.pdf',
        bytes: testDocumentPdf(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'TrustKeyper UI Test — offline fixtures',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    routerConfig: router,
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery();
  static const accountExamples = {
    'Broker · profile and account controls (offline)':
        '/ui-test/account/profile',
    'Broker · editable verified details (offline)': '/ui-test/account/details',
    'Broker · help and common questions': '/ui-test/account/help',
    'Account · closure safeguards (offline)': '/ui-test/account/close',
  };
  static const entries = {
    ...accountExamples,
    'Tenant · confirm home and flatmates (offline)': '/ui-test/tenant-setup/0',
    'Tenant · confirm rent share (offline)': '/ui-test/tenant-setup/2',
    'Broker · searchable records (offline)': '/ui-test/broker-records',
    'Owner documents · live upload transition (offline)':
        '/ui-test/broker-documents/owner/live-partial',
    'Owner documents · live completion (offline)':
        '/ui-test/broker-documents/owner/live-complete',
    'Owner documents · waiting (offline)':
        '/ui-test/broker-documents/owner/sent',
    'Owner documents · one received (offline)':
        '/ui-test/broker-documents/owner/partial',
    'Owner documents · all received (offline)':
        '/ui-test/broker-documents/owner/complete',
    'Owner documents · seen (offline)': '/ui-test/broker-documents/owner/seen',
    'Owner documents · resend cooldown (offline)':
        '/ui-test/broker-documents/owner/cooldown',
    'Owner documents · unclear and expired (offline)':
        '/ui-test/broker-documents/owner/problems',
    'Owner documents · deleted (offline)':
        '/ui-test/broker-documents/owner/deleted',
    'Tenant documents · waiting (offline)':
        '/ui-test/broker-documents/tenant/sent',
    'Tenant documents · all received (offline)':
        '/ui-test/broker-documents/tenant/complete',
    'Broker · missing fields (offline)': '/ui-test/field-guidance',
    'Broker · optional property labels (offline)': '/broker/property',
    'Broker · upload updates and reopen (offline)': '/ui-test/broker-updates',
    'Broker · saved drafts and continue (offline)': '/ui-test/broker-drafts',
    'Broker · owner Add and Send link (offline)': '/ui-test/broker-owner-links',
    'Owner · five-step property setup (offline)': '/owner/onboarding',
    'Sign only · page review and signer details (offline)': '/broker/sign-only',
    'Owner · request a manager callback (offline)':
        '/ui-test/owner-callback/none',
    'Owner · confirmed manager call (offline)':
        '/ui-test/owner-callback/confirmed',
    'Owner · missed call and reschedule (offline)':
        '/ui-test/owner-callback/missed',
    'Renew · saved signed agreement (offline)': '/broker/renew',
    'Move-out · room comparisons (offline)': '/ui-test/move-out/photos',
    'Move-out · deductions and handover (offline)': '/ui-test/move-out/broker',
    'Move-out · tenant key return code (offline)':
        '/ui-test/move-out/tenant-keys',
    'Move-out · tenant deductions and bank (offline)':
        '/ui-test/move-out/tenant',
    'Move-out · owner report approval (offline)': '/ui-test/move-out/owner',
    'Move-out · team disputed item review (offline)': '/ui-test/move-out/admin',
    'Move-in · room photos and meters (offline)': '/ui-test/move-in/photos',
    'Move-in · broker key confirmation (offline)': '/ui-test/move-in/keys',
    'Move-in · tenant key count and code (offline)': '/ui-test/move-in/tenant',
    'Rent follow-up · broker notes and extension (offline)':
        '/ui-test/move-in/rent-broker',
    'Rent follow-up · owner more time (offline)': '/ui-test/move-in/rent-owner',
    'Rent follow-up · tenant promise (offline)': '/ui-test/move-in/rent-tenant',
    'Move-out · notice and lock-in warning (offline)':
        '/ui-test/move-in/notice',
    'Photo checks · camera and timeline (offline)': '/ui-test/photo-checks',
    'Switch role · offline preview': '/preview/switch-role',
    'Owner · approve repair quote (offline)': '/ui-test/repairs/approval',
    'Owner · repair photos and bill (offline)': '/ui-test/repairs/completed',
    'Tenant · confirm repair outcome (offline)': '/ui-test/repairs/tenant',
    'Payments · first payment layout only': '/ui-test/payments/first',
    'Payments · choose advance months only': '/ui-test/payments/advance',
    'Owner · demo agreement reply': '/ui-test/approval/owner',
    'Agreement copy · read and save demo PDF': '/ui-test/agreement-copy',
    'Tenant · demo agreement reply': '/ui-test/approval/tenant',
    'Changed agreement · say yes again': '/ui-test/approval/owner?changed=true',
    'Owner dashboard · interactive offline fixture': '/ui-test/workspace/owner',
    'Tenant dashboard · interactive offline fixture':
        '/ui-test/workspace/tenant',
    'Owner · no linked home': '/ui-test/workspace/owner?empty=true',
    'Tenant · no linked home': '/ui-test/workspace/tenant?empty=true',
    'Four onboarding pages': '/preview/onboarding',
    'Login preview': '/preview/login',
    'Phone OTP': '/preview/phone-otp',
    'Email OTP': '/preview/email-otp',
    'Name and email': '/preview/profile',
    'Role choices': '/preview/roles',
    'Approval pending': '/preview/approval-pending',
    'Verified approval fixture': '/preview/approval-verified',
    'Paused account': '/preview/paused',
    'Broker home': '/preview/broker-home',
    'New, renew and sign choices': '/broker/start',
    'Agreement introduction': '/broker/agreement/steps',
    'Interactive property journey': '/broker/property',
    'Interactive agreement draft': '/ui-test/agreement',
    'Private documents · offline fixture': '/ui-test/documents',
    'Recipient Aadhaar · offline preview': '/ui-test/recipient/aadhaar',
    'Recipient PAN · offline preview': '/ui-test/recipient/pan',
    'Recipient bank proof · offline preview': '/ui-test/recipient/bank',
    'Owner document link · all three · offline': '/ui-test/recipient/all',
    'Demo agreement · not for signing': '/ui-test/demo-agreement',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TrustKeyper UI Test')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'OFFLINE TEST APP — NOT YOUR LIVE ACCOUNT\n\nAuthentication screens are read-only previews. Property and agreement drafts are kept only in memory. No Firebase login, real OTP, payment, upload or message is sent. Android internet access is disabled.\n\nUse the phone’s Back button to return here. Other app screens are still pending.',
          ),
        ),
        const SizedBox(height: 20),
        for (final entry in entries.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.key),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(entry.value),
          ),
      ],
    ),
  );
}

class _Home extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ApprovedBrokerHome(
        profile: const BrokerProfile(
          displayName: 'Test Broker',
          email: '',
          phone: '',
          approvalStatus: 'approved',
        ),
        approvalPending: false,
        onOpenProfile: () => context.push('/preview/profile'),
      ),
    ),
    bottomNavigationBar: ApprovedBrokerNavigation(
      selectedIndex: 0,
      onSelected: (index) {
        if (index == 4) {
          context.push('/preview/profile');
        } else if (index != 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This tab has not been implemented in the offline UI-test gallery.',
              ),
            ),
          );
        }
      },
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('UI test — not connected')),
    body: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
  );
}

class _PropertyResult extends StatelessWidget {
  const _PropertyResult({required this.property});
  final BrokerProperty? property;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Property test result')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saved in this test app’s memory only. No agreement was created or sent.',
          ),
          const SizedBox(height: 24),
          if (property != null)
            Text(
              '${property!.address}\n${property!.rooms} · ${property!.furnishing}\n${property!.inventory.entries.where((entry) => entry.value > 0).map((entry) => '${entry.key}: ${entry.value}').join(', ')}',
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to test gallery'),
          ),
        ],
      ),
    ),
  );
}

class UiTestPropertyRepository implements BrokerPropertyRepository {
  final _changes = StreamController<List<BrokerProperty>>.broadcast();
  final _properties = <BrokerProperty>[];
  int _nextId = 0;

  @override
  Stream<List<BrokerProperty>> watchProperties() => Stream.multi((controller) {
    controller.add(List.unmodifiable(_properties));
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<BrokerProperty> save(BrokerProperty property) async {
    final error = property.validationError;
    if (error != null) throw StateError(error);
    final saved = BrokerProperty.fromMap(
      property.id.isEmpty ? 'ui-test-${++_nextId}' : property.id,
      property.toMap(),
    );
    _properties.removeWhere((existing) => existing.id == saved.id);
    _properties.add(saved);
    _changes.add(List.unmodifiable(_properties));
    return saved;
  }

  Future<void> dispose() => _changes.close();
}

class UiTestDraftRepository implements AgreementDraftRepository {
  final records = <String, AgreementDraft>{};
  int sequence = 0;
  @override
  String newId() => 'ui-test-draft-${++sequence}';
  @override
  Future<AgreementDraft> load(String id) async {
    final draft = records[id];
    if (draft == null) {
      throw const DraftFailure('Test draft not found in memory.');
    }
    return draft;
  }

  @override
  Future<void> save(AgreementDraft draft) async {
    if (draft.validationError != null) {
      throw DraftFailure(draft.validationError!);
    }
    records[draft.id] = AgreementDraft.fromMap(draft.id, {
      ...draft.toMap(),
      'revision': draft.revision + 1,
    });
  }
}

class UiTestDocumentStore implements PrivateDocumentStore {
  final files = <String, DocumentFile>{};
  @override
  Future<PrivateDocument?> metadata(String path) async {
    final file = files[path];
    return file == null
        ? null
        : PrivateDocument(
            name: file.name,
            size: file.bytes.length,
            contentType: file.contentType,
          );
  }

  @override
  Future<Uint8List> read(String path) async => files[path]!.bytes;
  @override
  Future<void> write(
    String path,
    DocumentFile file,
    void Function(double) progress,
  ) async {
    progress(0.5);
    files[path] = file;
    progress(1);
  }

  @override
  Future<void> remove(String path) async {
    files.remove(path);
  }
}
