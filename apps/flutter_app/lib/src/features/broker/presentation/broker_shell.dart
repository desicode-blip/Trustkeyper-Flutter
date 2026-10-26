import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../agreement_copies/agreement_copy_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import 'approved_broker_home.dart';
import '../../account/data/account_gateway.dart';
import '../../account/presentation/account_screens.dart';
import '../../../core/widgets/approved_navigation.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/firebase_auth_service.dart';
import '../../auth/presentation/auth_screens.dart';
import '../data/broker_repository.dart';
import '../data/agreement_progress_repository.dart';
import '../data/broker_updates_repository.dart';
import '../data/broker_push_service.dart';
import 'broker_draft_cards.dart';
import 'broker_agreements_list.dart';
import 'broker_records_screen.dart';
import 'broker_web_entry_screen.dart';
import '../data/broker_property_repository.dart';
import '../../document_requests/data/document_request_repository.dart';
import '../../agreement_approvals/presentation/broker_approval_screen.dart'
    as replies;
import '../data/agreement_draft.dart';
import '../../inspections/inspection_screen.dart';
import '../../tenancy/move_in_screen.dart';

class BrokerShell extends StatefulWidget {
  const BrokerShell({
    required this.approvalPending,
    super.key,
    this.repository,
    this.initialTab = 0,
  });

  final bool approvalPending;
  final BrokerRepository? repository;
  final int initialTab;

  @override
  State<BrokerShell> createState() => _BrokerShellState();
}

class _BrokerShellState extends State<BrokerShell> {
  late final BrokerRepository repository;
  late final Stream<BrokerProfile> profileStream;
  late final Stream<List<BrokerAgreementSummary>> agreementsStream;
  late final Stream<List<BrokerPaymentSummary>> paymentsStream;
  int selectedIndex = 0;
  AgreementProgressRepository? progressRepository;
  FirebaseBrokerUpdatesRepository? updates;
  Stream<List<BrokerAgreementSummary>>? savedDraftAgreements;
  BrokerPushService? push;
  late final Stream<List<BrokerProperty>> recordProperties;
  FirebaseBrokerPropertyRepository? recordPropertyRepository;
  DocumentRequests? recordDocuments;
  AccountGateway? accountGateway;

  @override
  void didUpdateWidget(BrokerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      selectedIndex = widget.initialTab.clamp(0, 4);
    }
  }

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialTab.clamp(0, 4);
    repository = widget.repository ?? FirebaseBrokerRepository();
    profileStream = repository.watchProfile();
    agreementsStream = repository.watchAgreements().asBroadcastStream();
    paymentsStream = repository.watchPayments();
    recordPropertyRepository = widget.repository == null
        ? FirebaseBrokerPropertyRepository()
        : null;
    recordProperties =
        recordPropertyRepository?.watchProperties() ?? Stream.value(const []);
    if (widget.repository == null) {
      accountGateway = FirebaseAccountGateway();
      progressRepository = FirebaseAgreementProgressRepository();
      updates = FirebaseBrokerUpdatesRepository();
      recordDocuments = FirebaseDocumentRequests();
      savedDraftAgreements = repository.watchAgreements();
    }
  }

  @override
  void dispose() {
    if (push != null) unawaited(push!.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && widget.repository == null) {
      return BrokerWebEntryScreen(
        phone: FirebaseAuthService.instance.currentUser?.phoneNumber ?? '',
      );
    }
    return StreamBuilder<BrokerProfile>(
      stream: profileStream,
      builder: (context, snapshot) {
        final profile =
            snapshot.data ??
            BrokerProfile.fromAuthUser(
              widget.repository == null
                  ? FirebaseAuthService.instance.currentUser
                  : null,
            );
        final approvalPending =
            snapshot.hasError || !profile.canCreateAgreements;
        if (approvalPending && push != null) {
          unawaited(push!.stop(removeDevices: true));
          push = null;
        }
        if (profile.paused) return const AccountPausedScreen();
        if (!approvalPending && updates != null && push == null) {
          push = BrokerPushService(
            onOpenUpdates: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.push('/broker/updates');
              });
            },
            onForeground: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Documents were uploaded.'),
                    action: SnackBarAction(
                      label: 'Updates',
                      onPressed: () => context.push('/broker/updates'),
                    ),
                  ),
                );
              }
            },
          );
          unawaited(push!.start());
        }
        final pages = [
          ApprovedBrokerHome(
            profile: profile,
            approvalPending: approvalPending,
            onOpenProfile: () => setState(() => selectedIndex = 4),
            updates: approvalPending ? null : updates,
            savedDrafts: approvalPending || progressRepository == null
                ? null
                : BrokerDraftSection(
                    repository: progressRepository!,
                    agreements: savedDraftAgreements,
                    onAddBank: profile.hasBankAccount
                        ? null
                        : () => context.push('/broker/bank'),
                  ),
          ),
          BrokerAgreementsList(
            agreements: agreementsStream,
            approvalPending: approvalPending,
            progressRepository: approvalPending ? null : progressRepository,
            updates: approvalPending ? null : updates,
            itemBuilder: (context, agreement) =>
                _AgreementCard(agreement: agreement),
          ),
          BrokerRecordsScreen(
            agreements: agreementsStream,
            properties: recordProperties,
            documents: approvalPending ? null : recordDocuments,
            identities: widget.repository == null
                ? profileStream.map(
                    (profile) => profile.canCreateAgreements
                        ? FirebaseAuth.instance.currentUser?.uid
                        : null,
                  )
                : null,
            expectedUid: widget.repository == null
                ? FirebaseAuth.instance.currentUser?.uid
                : null,
            watchDetailAgreements: repository.watchAgreements,
            watchDetailProperties: recordPropertyRepository?.watchProperties,
            onAddProperty: approvalPending
                ? null
                : () => context.push('/broker/agreement'),
            onUpdates: approvalPending
                ? null
                : () => context.push('/broker/updates'),
            onOpenAgreement: (agreement) {
              if (agreement.status == 'draft') {
                context.push(
                  '/broker/draft/${Uri.encodeComponent(agreement.id)}',
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => agreement.copyMode == null
                        ? replies.BrokerApprovalScreen(
                            draft: AgreementDraft.fromMap(
                              agreement.id,
                              agreement.details,
                            ),
                          )
                        : AgreementCopyScreen(
                            agreementId: agreement.id,
                            revision: agreement.revision,
                            demo: agreement.copyMode != 'externally_signed',
                            role: 'broker',
                          ),
                  ),
                );
              }
            },
            onPhotoChecks: (propertyId, agreementId) =>
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InspectionScreen(
                      role: 'broker',
                      propertyId: propertyId,
                      agreementId: agreementId,
                    ),
                  ),
                ),
          ),
          _PaymentsTab(payments: paymentsStream),
          AccountProfilePanel(
            name: profile.displayName,
            phone: profile.phone,
            email: profile.email,
            role: 'broker',
            bankName: profile.bankName ?? '',
            bankLast4: profile.bankAccountLast4 ?? '',
            gateway: accountGateway,
            onUpdates: approvalPending
                ? null
                : () => context.push('/broker/updates'),
            onSignedOut: () => context.go('/login'),
            onSwitchRole: () => context.push('/switch-role'),
          ),
        ];

        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: selectedIndex, children: pages),
          ),
          bottomNavigationBar: ApprovedBrokerNavigation(
            selectedIndex: selectedIndex,
            onSelected: (index) => setState(() => selectedIndex = index),
          ),
        );
      },
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.payments});

  final Stream<List<BrokerPaymentSummary>> payments;

  @override
  Widget build(BuildContext context) {
    return _DataTab<BrokerPaymentSummary>(
      title: 'Payments',
      stream: payments,
      emptyIcon: Icons.account_balance_wallet_outlined,
      emptyTitle: 'No payments yet',
      emptyBody:
          'Your brokerage payouts will appear here after an agreement is completed.',
      itemBuilder: (context, payment) => Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.currency_rupee, color: AppColors.primary),
          ),
          title: Text(payment.label),
          subtitle: Text(_readableStatus(payment.status)),
          trailing: Text(
            _formatPaise(payment.amountPaise),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  const _AgreementCard({required this.agreement});

  final BrokerAgreementSummary agreement;

  @override
  Widget build(BuildContext context) {
    final rent = agreement.monthlyRentPaise == null
        ? null
        : '${_formatPaise(agreement.monthlyRentPaise!)} / month';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              agreement.property,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text([agreement.people, ?rent].join(' · ')),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _readableStatus(agreement.status),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (agreement.status == 'draft') ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => context.push(
                  '/broker/draft/${Uri.encodeComponent(agreement.id)}',
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Open private draft'),
              ),
            ],
            if (agreement.copyMode == 'externally_signed')
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MoveInScreen(agreementId: agreement.id, role: 'broker'),
                  ),
                ),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Move-in checklist'),
              ),
            if (agreement.copyMode == 'externally_signed') ...[
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MoveInScreen(
                      agreementId: agreement.id,
                      role: 'broker',
                      initialPage: 'notice',
                    ),
                  ),
                ),
                icon: const Icon(Icons.output_outlined),
                label: const Text('Move-out and deposit'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MoveInScreen(
                      agreementId: agreement.id,
                      role: 'broker',
                      initialPage: 'rent',
                    ),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Rent follow-up'),
              ),
            ],
            if (agreement.copyMode != null && agreement.revision > 0)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AgreementCopyScreen(
                      agreementId: agreement.id,
                      revision: agreement.revision,
                      demo: agreement.copyMode == 'demo',
                    ),
                  ),
                ),
                icon: const Icon(Icons.description_outlined),
                label: Text(
                  agreement.copyMode == 'demo'
                      ? 'Read demo agreement copy'
                      : 'Signed agreement',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DataTab<T> extends StatelessWidget {
  const _DataTab({
    required this.title,
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.itemBuilder,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Stream<List<T>> stream;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snapshot) {
        return _TabList(
          title: title,
          actionLabel: actionLabel,
          onAction: onAction,
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const _LoadingState()
            else if (snapshot.hasError)
              const _LoadErrorState()
            else if ((snapshot.data ?? const []).isEmpty)
              _EmptyState(icon: emptyIcon, title: emptyTitle, body: emptyBody)
            else
              ...(snapshot.data ?? const []).map(
                (item) => itemBuilder(context, item),
              ),
          ],
        );
      },
    );
  }
}

class _TabList extends StatelessWidget {
  const _TabList({
    required this.title,
    required this.children,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            IconButton(
              onPressed: () => context.push('/experiences'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              tooltip: 'Messages',
            ),
          ],
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 18),
          PrimaryButton(label: actionLabel!, onPressed: onAction),
        ],
        const SizedBox(height: 24),
        ...children.expand((child) => [child, const SizedBox(height: 12)]),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 56),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  const _LoadErrorState();

  @override
  Widget build(BuildContext context) {
    return const _EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load this page',
      body: 'Check your internet connection and try again.',
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.muted, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

String _readableStatus(String status) {
  final words = status
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return 'In progress';
  final normalized = words.join(' ');
  return '${normalized.substring(0, 1).toUpperCase()}${normalized.substring(1)}';
}

String _formatPaise(int amountPaise) {
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  ).format(amountPaise / 100);
}
