import 'dart:async';
import '../../account/data/account_gateway.dart';
import '../../account/presentation/account_screens.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../payments/data/rent_payments.dart';
import '../../payments/presentation/rent_payment_screen.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/session_bound_screen.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/demo_agreement.dart';
import '../../broker/presentation/demo_agreement_screen.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../data/participant_repository.dart';
import '../data/participant_workspace.dart';
import 'repair_photo_widgets.dart';
import '../../repairs/presentation/repair_detail_screen.dart';
import '../../agreement_copies/agreement_copy_screen.dart';
import '../../inspections/inspection_screen.dart';
import '../../tenancy/move_in_screen.dart';
import '../../tenant/data/tenant_setup.dart';
import '../../tenant/presentation/tenant_setup_screen.dart';

String workspaceMoney(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: paise % 100 == 0 ? 0 : 2,
).format(paise / 100);

void _dismissPrivateChildren(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route != null && route.isActive) {
    Navigator.of(context).popUntil((candidate) => candidate == route);
  }
}

class ParticipantWorkspaceScreen extends StatefulWidget {
  const ParticipantWorkspaceScreen({
    required this.repository,
    required this.role,
    required this.identity,
    this.issueWriter,
    this.photoReader,
    this.onLogout,
    this.onSwitchRole,
    this.onManagerSupport,
    this.onOwnerSetup,
    this.now,
    this.initialTab = 0,
    this.agreementId,
    this.tenantSetup,
    this.accountGateway,
    this.onAccountSignedOut,
    super.key,
  });
  final ParticipantRepository repository;
  final String role;
  final ParticipantIdentity identity;
  final ParticipantIssueWriter? issueWriter;
  final IssuePhotoReader? photoReader;
  final Future<void> Function()? onLogout;
  final VoidCallback? onSwitchRole;
  final VoidCallback? onManagerSupport;
  final VoidCallback? onOwnerSetup;
  final DateTime? now;
  final int initialTab;
  final String? agreementId;
  final TenantSetupGateway? tenantSetup;
  final AccountGateway? accountGateway;
  final VoidCallback? onAccountSignedOut;
  @override
  State<ParticipantWorkspaceScreen> createState() =>
      _ParticipantWorkspaceScreenState();
}

class _ParticipantWorkspaceScreenState
    extends State<ParticipantWorkspaceScreen> {
  final records = <String, List<ParticipantRecord>>{};
  final failures = <String>{};
  final subscriptions = <StreamSubscription<List<ParticipantRecord>>>[];
  int index = 0;
  bool closedIssues = false;
  int generation = 0;
  bool get owner => widget.role == 'owner';
  String get moneyCollection => owner ? 'payouts' : 'payments';
  List<ParticipantRecord> get agreements =>
      (records['agreements'] ?? const <ParticipantRecord>[])
          .where(
            (record) =>
                widget.agreementId == null || record.id == widget.agreementId,
          )
          .toList();

  @override
  void initState() {
    super.initState();
    index = widget.initialTab.clamp(0, widget.role == 'owner' ? 4 : 3);
    _listen();
  }

  void _listen() {
    final active = ++generation;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    subscriptions.clear();
    records.clear();
    failures.clear();
    for (final collection in ['agreements', moneyCollection, 'issues']) {
      subscriptions.add(
        widget.repository
            .watch(collection)
            .listen(
              (items) {
                if (!mounted || active != generation) return;
                setState(() {
                  records[collection] = items;
                  failures.remove(collection);
                });
              },
              onError: (Object error) {
                if (!mounted || active != generation) return;
                setState(() {
                  records.remove(collection);
                  failures.add(collection);
                });
              },
            ),
      );
    }
  }

  @override
  void didUpdateWidget(ParticipantWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      index = widget.initialTab.clamp(0, widget.role == 'owner' ? 4 : 3);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.identity.uid != widget.identity.uid ||
        oldWidget.role != widget.role) {
      _listen();
    }
  }

  @override
  void dispose() {
    generation++;
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _select(int value) => setState(() => index = value);
  void _explain(String title, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  MaterialPageRoute<void> _privateRoute({required WidgetBuilder builder}) {
    final repository = widget.repository;
    final uid = widget.identity.uid;
    return MaterialPageRoute<void>(
      builder: (context) => repository is SessionParticipantRepository
          ? SessionBoundScreen(
              users: repository.identities,
              initialUid: uid,
              expectedUid: uid,
              onSessionEnded: () => _dismissPrivateChildren(context),
              child: Builder(builder: builder),
            )
          : builder(context),
    );
  }

  Future<void> _newIssue() async {
    if (widget.issueWriter == null ||
        agreements.isEmpty ||
        failures.contains('agreements')) {
      _explain(
        'Home not linked',
        'No linked records yet. Ask your broker to link your verified account before reporting a problem.',
      );
      return;
    }
    await Navigator.of(context).push(
      _privateRoute(
        builder: (_) => ParticipantIssueScreen(
          agreements: agreements,
          writer: widget.issueWriter!,
          role: widget.role,
        ),
      ),
    );
    if (mounted) _select(owner ? 3 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final labels = owner
        ? ['Home', 'Properties', 'Money', 'Issues', 'Profile']
        : ['Home', 'Pay', 'Issues', 'Profile'];
    final icons = owner
        ? [
            Icons.home_outlined,
            Icons.apartment_outlined,
            Icons.account_balance_wallet_outlined,
            Icons.build_outlined,
            Icons.person_outline,
          ]
        : [
            Icons.home_outlined,
            Icons.account_balance_wallet_outlined,
            Icons.build_outlined,
            Icons.person_outline,
          ];
    final content = index == labels.length - 1
        ? _profile()
        : index == 0
        ? _home()
        : owner && index == 1
        ? _properties()
        : index == (owner ? 2 : 1)
        ? _money()
        : _issues();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                _WorkspaceHeader(
                  role: owner ? 'Owner' : 'Tenant',
                  onUpdates: () => _select(owner ? 3 : 2),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.heading.withValues(alpha: .05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: List.generate(
                  labels.length,
                  (position) => Expanded(
                    child: Semantics(
                      selected: index == position,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => _select(position),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: index == position
                                ? AppColors.primarySoft
                                : null,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icons[position],
                                size: 22,
                                color: index == position
                                    ? AppColors.primary
                                    : AppColors.muted,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                child: Text(
                                  labels[position],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: index == position
                                        ? AppColors.primary
                                        : AppColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    children: children,
  );
  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
      ),
    ),
  );
  Widget? _state(String collection) {
    if (failures.contains(collection)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Could not load your records. Check your connection and retry.',
          ),
          OutlinedButton(
            onPressed: () => setState(_listen),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    if (!records.containsKey(collection)) {
      return const Center(child: CircularProgressIndicator());
    }
    return null;
  }

  Widget _empty(String message) => _WorkspaceCard(
    child: Column(
      children: [
        const Icon(Icons.folder_outlined, color: AppColors.primary, size: 40),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _home() {
    final name = widget.identity.name.trim().split(' ').first;
    final state = _state('agreements');
    final moneyState = _state(moneyCollection);
    final money = records[moneyCollection] ?? const [];
    final date = widget.now ?? DateTime.now();
    final month = DateFormat('MMMM').format(date);
    final current = money.where((item) {
      final due = recordDate(item.data[owner ? 'scheduledAt' : 'dueDate']);
      return due?.year == date.year &&
          due?.month == date.month &&
          item.text('mode', '') != 'test' &&
          item.amount('amountPaise') != null &&
          !['cancelled', 'failed'].contains(item.text('status', ''));
    }).toList();
    final total = current.isEmpty
        ? null
        : current.fold<int>(
            0,
            (sum, item) => sum + item.amount('amountPaise')!,
          );
    final open = (records['issues'] ?? const <ParticipantRecord>[])
        .where(
          (item) =>
              !['closed', 'resolved'].contains(item.text('status', 'open')),
        )
        .length;
    return _list([
      _title(
        name.isEmpty
            ? (owner ? 'Welcome home' : 'Hi there')
            : (owner ? 'Namaste, $name' : 'Hi $name'),
      ),
      if (owner && widget.onManagerSupport != null)
        _WorkspaceRow(
          icon: Icons.support_agent,
          title: 'Our manager can do it for you',
          subtitle: 'Add a property, choose a plan or find a tenant',
          onTap: widget.onManagerSupport,
        ),
      if (owner && widget.onOwnerSetup != null)
        _WorkspaceRow(
          icon: Icons.add_home_outlined,
          title: 'Add a property',
          subtitle: 'Save your home details and request a plan',
          onTap: widget.onOwnerSetup,
        ),
      if (state != null)
        state
      else if (agreements.isEmpty)
        _empty(
          'No linked records yet. Your broker or team needs to link your verified account and home.',
        )
      else ...[
        if (!owner && widget.tenantSetup != null)
          for (final agreement in agreements)
            _WorkspaceRow(
              icon: Icons.fact_check_outlined,
              title: 'Confirm your home and rent share',
              subtitle: agreement.text('propertyAddress', 'Your linked home'),
              onTap: () => Navigator.of(context).push(
                _privateRoute(
                  builder: (_) => TenantSetupScreen(
                    agreementId: agreement.id,
                    gateway: widget.tenantSetup!,
                  ),
                ),
              ),
            ),
        if (owner)
          _WorkspaceCard(
            color: AppColors.primarySoft,
            child: Column(
              children: [
                Text(
                  'Your $month payouts',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  total == null ? 'Not scheduled yet' : workspaceMoney(total),
                  style: TextStyle(
                    fontSize: total == null ? 24 : 44,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  total == null
                      ? 'Payout amounts appear when the team records them.'
                      : 'Recorded payouts · ${current.length} ${current.length == 1 ? 'entry' : 'entries'}',
                  style: const TextStyle(color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
                if (moneyState != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: moneyState,
                  ),
              ],
            ),
          )
        else
          _WorkspaceCard(
            color: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your monthly rent share',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  personalShare(
                            agreements.first,
                            widget.identity,
                            'rentSharePaise',
                          ) ==
                          null
                      ? 'Share not linked yet'
                      : workspaceMoney(
                          personalShare(
                            agreements.first,
                            widget.identity,
                            'rentSharePaise',
                          )!,
                        ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Agreement share · payment status is shown in Pay',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                  ),
                  onPressed: () => _select(1),
                  child: const Text('See payments  ›'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (owner)
          Center(
            child: TextButton.icon(
              onPressed: () => _select(2),
              icon: const Icon(Icons.calendar_today_outlined, size: 17),
              label: const Text('See all months  ›'),
            ),
          ),
        if (open > 0) ...[
          const SizedBox(height: 12),
          _WorkspaceRow(
            icon: Icons.build_outlined,
            title:
                '$open ${open == 1 ? 'issue needs' : 'issues need'} attention',
            color: AppColors.warningSoft,
            onTap: () => _select(owner ? 3 : 2),
          ),
        ],
        const SizedBox(height: 12),
        _WorkspaceCard(
          child: Column(
            children: [
              if (owner)
                for (final agreement in agreements)
                  _WorkspaceRow(
                    icon: Icons.apartment_outlined,
                    title: agreement.text('propertyAddress', 'Linked property'),
                    subtitle: _agreementStatus(agreement),
                    onTap: () => _details(agreement, 'Property'),
                  )
              else ...[
                _WorkspaceRow(
                  icon: Icons.description_outlined,
                  title: 'My agreement',
                  subtitle: _dates(agreements.first),
                  onTap: () => _details(agreements.first, 'Agreement'),
                ),
                const Divider(height: 16),
                _WorkspaceRow(
                  icon: Icons.folder_outlined,
                  title: 'My documents',
                  subtitle: 'Use the private link your broker sent',
                  onTap: () => _explain(
                    'Your private documents',
                    'Open your broker’s document link to upload or replace the requested paper. For privacy, unrelated papers are not shown on this account.',
                  ),
                ),
                const Divider(height: 16),
                _WorkspaceRow(
                  icon: Icons.build_outlined,
                  title: 'Something broken?',
                  subtitle: 'Tell us about the problem',
                  onTap: _newIssue,
                ),
              ],
            ],
          ),
        ),
      ],
    ]);
  }

  String _agreementStatus(ParticipantRecord record) =>
      switch (record.text('status', '')) {
        'signed' => 'Signed',
        'signed_copy_received' => 'Signed agreement ready',
        'active' => 'Active',
        'review_requested' => 'Waiting for review',
        'reviewed' => 'Reviewed · signing is separate',
        'draft' => 'Draft · not signed',
        _ => record.text('status', 'Status not recorded').replaceAll('_', ' '),
      };
  String _dates(ParticipantRecord record) {
    final start = recordDate(record.data['startDateISO']);
    final end = recordDate(record.data['endDateISO']);
    return start == null || end == null
        ? _agreementStatus(record)
        : '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
  }

  Widget _properties() {
    final state = _state('agreements');
    return _list([
      _title('My properties'),
      if (widget.onOwnerSetup != null)
        _WorkspaceRow(
          icon: Icons.add_home_outlined,
          title: 'Add or finish a property',
          subtitle: 'Saved details, photos and plan requests',
          onTap: widget.onOwnerSetup,
        ),
      if (state != null)
        state
      else if (agreements.isEmpty)
        _empty('No linked records yet. Ask your broker to add your property.')
      else
        for (final agreement in agreements)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _WorkspaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WorkspaceRow(
                    icon: Icons.apartment_outlined,
                    title: agreement.text('propertyAddress', 'Linked property'),
                    subtitle: _agreementStatus(agreement),
                    onTap: () => _details(agreement, 'Property'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _AmountTile(
                          label: 'Agreement rent',
                          amount: agreement.amount('monthlyRentPaise'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AmountTile(
                          label: 'Agreement deposit',
                          amount: agreement.amount('securityDepositPaise'),
                          green: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Agreement totals, not proof of payment or your personal payout.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  if (agreement.text('propertyId').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _WorkspaceRow(
                      icon: Icons.photo_library_outlined,
                      title: 'Photo checks',
                      subtitle: 'Take photos and view property history',
                      onTap: () => Navigator.of(context).push(
                        _privateRoute(
                          builder: (context) => InspectionScreen(
                            role: widget.role,
                            propertyId: agreement.text('propertyId'),
                            agreementId: agreement.id,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
    ]);
  }

  Widget _money() {
    final state = _state(moneyCollection);
    final items = [...records[moneyCollection] ?? <ParticipantRecord>[]];
    items.sort(
      (first, second) =>
          (recordDate(second.data['createdAt']) ??
                  (second.amount('createdAtMs') == null
                      ? DateTime(1970)
                      : DateTime.fromMillisecondsSinceEpoch(
                          second.amount('createdAtMs')!,
                        )))
              .compareTo(
                recordDate(first.data['createdAt']) ??
                    (first.amount('createdAtMs') == null
                        ? DateTime(1970)
                        : DateTime.fromMillisecondsSinceEpoch(
                            first.amount('createdAtMs')!,
                          )),
              ),
    );
    return _list([
      _title(owner ? 'Money' : 'Payments'),
      if (!owner)
        for (final agreement in records['agreements'] ?? <ParticipantRecord>[])
          if (agreement.data['agreementCopy'] is Map &&
              agreement.data['revision'] is int)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  _privateRoute(
                    builder: (_) => RentPaymentScreen(
                      agreementId: agreement.id,
                      revision: agreement.data['revision'] as int,
                    ),
                  ),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  'Pay · ${agreement.text('propertyAddress')} · test',
                ),
              ),
            ),
      if (state != null)
        state
      else if (items.isEmpty)
        _empty(
          owner
              ? 'No payouts recorded yet. Scheduled and completed bank payouts will appear here.'
              : 'No payments recorded yet. No amount has been charged by this screen.',
        )
      else
        for (final item in items)
          _WorkspaceRow(
            icon: Icons.account_balance_wallet_outlined,
            title: item.text(
              'title',
              item.text('propertyAddress', owner ? 'Payout' : 'Payment'),
            ),
            subtitle:
                '${item.text('status', 'Not recorded').replaceAll('_', ' ')}${item.text('mode', '') == 'test' ? ' · TEST, no real money' : ''}',
            trailing: item.amount('amountPaise') == null
                ? 'Amount not recorded'
                : workspaceMoney(item.amount('amountPaise')!),
            onTap: () => _details(item, owner ? 'Payout' : 'Payment'),
          ),
      if (!owner) ...[
        const SizedBox(height: 20),
        _WorkspaceCard(
          color: AppColors.surfaceMuted,
          child: const Text(
            'Razorpay test checkout is available for linked agreements. Test payments never release keys or settle payouts. Only backend-verified captures appear as paid.',
          ),
        ),
      ],
    ]);
  }

  Widget _issues() {
    final state = _state('issues');
    final items = (records['issues'] ?? const <ParticipantRecord>[])
        .where(
          (item) =>
              ['closed', 'resolved'].contains(item.text('status', 'open')) ==
              closedIssues,
        )
        .toList();
    return _list([
      _title('Issues'),
      FilledButton.icon(
        onPressed: widget.issueWriter == null ? null : _newIssue,
        icon: const Icon(Icons.add),
        label: const Text('Tell us a problem'),
      ),
      const SizedBox(height: 18),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Open')),
          ButtonSegment(value: true, label: Text('Closed')),
        ],
        selected: {closedIssues},
        onSelectionChanged: (value) =>
            setState(() => closedIssues = value.single),
      ),
      const SizedBox(height: 18),
      if (state != null)
        state
      else if (items.isEmpty)
        _empty(
          closedIssues
              ? 'No closed issues yet.'
              : 'No open issues. Report a problem when you need help.',
        )
      else
        for (final item in items)
          _WorkspaceRow(
            icon: Icons.build_outlined,
            title: item.text(
              'title',
              item.text('category', 'Reported problem'),
            ),
            subtitle: item.text('status', 'open').replaceAll('_', ' '),
            onTap: () => Navigator.of(context).push(
              _privateRoute(
                builder: (_) =>
                    widget.issueWriter is FirebaseParticipantIssueWriter
                    ? RepairDetailScreen(
                        issueId: item.id,
                        photoReader: widget.photoReader,
                      )
                    : ParticipantIssueDetailScreen(
                        issue: item,
                        reader: widget.photoReader,
                      ),
              ),
            ),
          ),
    ]);
  }

  Widget _profile() => AccountProfilePanel(
    name: widget.identity.name,
    phone: widget.identity.phone,
    email: widget.identity.email,
    role: widget.role,
    gateway: widget.accountGateway,
    onSwitchRole: widget.onSwitchRole,
    onManagerSupport: widget.onManagerSupport,
    onSignedOut: widget.onAccountSignedOut,
    onLogout: widget.onLogout,
  );

  Future<void> _details(
    ParticipantRecord record,
    String title,
  ) => Navigator.of(context).push(
    _privateRoute(
      builder: (context) => _ParticipantRecordScope(
        repository: widget.repository,
        collection: title == 'Payment' || title == 'Payout'
            ? moneyCollection
            : 'agreements',
        recordId: record.id,
        title: title,
        builder: (context, record) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: _list([
            _title(record.text('propertyAddress', record.text('title', title))),
            _WorkspaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Status: ${record.text('status', 'Not recorded').replaceAll('_', ' ')}',
                  ),
                  if (record.data['description'] is String) ...[
                    const SizedBox(height: 16),
                    Text(record.text('description')),
                  ],
                  for (final field in {
                    'monthlyRentPaise': 'Agreement rent',
                    'securityDepositPaise': 'Agreement deposit',
                    'amountPaise': 'Recorded amount',
                  }.entries)
                    if (record.amount(field.key) != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${field.value}: ${workspaceMoney(record.amount(field.key)!)}',
                      ),
                    ],
                  const SizedBox(height: 12),
                  Text(
                    'Record reference: ${record.id}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (title == 'Agreement' || title == 'Property') ...[
              const SizedBox(height: 18),
              if (record.data['agreementCopy'] is Map &&
                  (record.data['agreementCopy'] as Map)['mode'] ==
                      'externally_signed')
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    _privateRoute(
                      builder: (_) => MoveInScreen(
                        agreementId: record.id,
                        role: widget.role,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Move-in and key record'),
                ),
              if (record.data['agreementCopy'] is Map &&
                  (record.data['agreementCopy'] as Map)['mode'] ==
                      'externally_signed') ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    _privateRoute(
                      builder: (_) => MoveInScreen(
                        agreementId: record.id,
                        role: widget.role,
                        initialPage: 'notice',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.output_outlined),
                  label: const Text('Move-out and deposit'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    _privateRoute(
                      builder: (_) => MoveInScreen(
                        agreementId: record.id,
                        role: widget.role,
                        initialPage: 'rent',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Rent follow-up'),
                ),
              ],
              if (record.data['agreementCopy'] is Map &&
                  (record.data['agreementCopy'] as Map)['revision'] ==
                      record.data['revision'])
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    _privateRoute(
                      builder: (_) => AgreementCopyScreen(
                        agreementId: record.id,
                        revision: record.data['revision'] as int,
                        role: widget.role,
                        onDashboard: () => Navigator.of(context).pop(),
                        demo:
                            (record.data['agreementCopy'] as Map)['mode'] ==
                            'demo',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(
                    (record.data['agreementCopy'] as Map)['mode'] == 'demo'
                        ? 'Read demo agreement copy'
                        : 'Signed agreement',
                  ),
                ),
              const Text(
                'Review and signing are separate. These totals do not confirm a payment.',
              ),
              if (_demo(record) != null)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    _privateRoute(
                      builder: (_) =>
                          DemoAgreementScreen(agreement: _demo(record)!),
                    ),
                  ),
                  child: const Text('Read demo terms · Not for signing'),
                ),
            ],
            if (title == 'Payment' &&
                record.text('mode', '') == 'test' &&
                record.text('intentId', '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      final receipt = await FirebaseRentPaymentGateway()
                          .reconcile(record.text('intentId'));
                      final bytes = await paymentReceipt(receipt);
                      await FilePicker.saveFile(
                        fileName: '${receipt.text('receiptNumber')}.pdf',
                        bytes: bytes,
                        type: FileType.custom,
                        allowedExtensions: ['pdf'],
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Receipt could not be verified. Check your connection and login, then retry.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download verified test receipt'),
                ),
              ),
          ]),
        ),
      ),
    ),
  );

  DemoAgreement? _demo(ParticipantRecord record) {
    try {
      final draft = AgreementDraft.fromMap(record.id, record.data);
      return draft.validationError == null ? DemoAgreement(draft) : null;
    } catch (_) {
      return null;
    }
  }
}

class _ParticipantRecordScope extends StatefulWidget {
  const _ParticipantRecordScope({
    required this.repository,
    required this.collection,
    required this.recordId,
    required this.title,
    required this.builder,
  });
  final ParticipantRepository repository;
  final String collection;
  final String recordId;
  final String title;
  final Widget Function(BuildContext, ParticipantRecord) builder;
  @override
  State<_ParticipantRecordScope> createState() =>
      _ParticipantRecordScopeState();
}

class _ParticipantRecordScopeState extends State<_ParticipantRecordScope> {
  late final records = widget.repository.watch(widget.collection);
  bool notified = false;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<ParticipantRecord>>(
    stream: records,
    builder: (context, snapshot) {
      if (!snapshot.hasData && !snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final matching = snapshot.hasError
          ? const <ParticipantRecord>[]
          : snapshot.data!
                .where((record) => record.id == widget.recordId)
                .toList();
      if (matching.length != 1) {
        if (!notified) {
          notified = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _dismissPrivateChildren(context);
          });
        }
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: const Center(
            child: Text(
              'This private record is no longer available. Reopen your account to check access.',
            ),
          ),
        );
      }
      notified = false;
      return widget.builder(context, matching.single);
    },
  );
}

class ParticipantIssueScreen extends StatefulWidget {
  const ParticipantIssueScreen({
    required this.agreements,
    required this.writer,
    this.pickPhoto,
    this.reviewPhoto,
    this.role = 'tenant',
    super.key,
  });
  final List<ParticipantRecord> agreements;
  final ParticipantIssueWriter writer;
  final Future<DocumentFile?> Function(bool camera)? pickPhoto;
  final Future<bool> Function(DocumentFile file)? reviewPhoto;
  final String role;
  @override
  State<ParticipantIssueScreen> createState() => _ParticipantIssueScreenState();
}

class _ParticipantIssueScreenState extends State<ParticipantIssueScreen> {
  final description = TextEditingController();
  final photos = <DocumentFile>[];
  final reportId = newRepairReportId();
  IssueInput? pending;
  late String agreementId = widget.agreements.first.id;
  String category = 'Water';
  String? error;
  String? savedId;
  bool busy = false;
  bool get editable => !busy && pending == null;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy) return;
    final input =
        pending ??
        IssueInput(
          agreementId: agreementId,
          category: category,
          description: description.text,
          reportId: reportId,
          photos: List.unmodifiable(photos),
        );
    if (input.error != null) {
      setState(() => error = input.error);
      return;
    }
    setState(() {
      busy = true;
      pending = input;
      error = null;
    });
    try {
      final result = await widget.writer.create(input);
      if (mounted) setState(() => savedId = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Sending was not confirmed. Keep this form open and retry the same report; retrying cannot create a duplicate.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addPhoto() async {
    if (!editable || photos.length >= 4) return;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(context, false),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted || !editable) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file =
          await (widget.pickPhoto?.call(camera) ??
              pickPrivateDocument(camera: camera));
      if (!mounted || file == null) return;
      file.validate();
      if (!file.contentType.startsWith('image/')) {
        throw const DocumentFailure('Choose a JPG or PNG photo, not a PDF.');
      }
      final accepted =
          await (widget.reviewPhoto?.call(file) ??
              reviewPrivateDocument(
                context,
                file,
                upload: true,
                selectionOnly: true,
                reviewTitle: 'Review selected photo',
                instructions:
                    'Nothing is sent until you press Send on the report. This photo will be shared privately with linked participants and TrustKeyper support.',
              ));
      if (mounted && accepted) setState(() => photos.add(file));
    } on DocumentFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not select this photo. Check camera/file permission and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.role == 'owner' ? 'Owner' : 'Tenant',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (savedId != null) ...[
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 64,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Issue sent',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your team can see this report. Reference: $savedId',
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      const Text(
                        'What is the problem?',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (widget.agreements.length > 1) ...[
                        DropdownButtonFormField<String>(
                          initialValue: agreementId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Your home',
                          ),
                          items: widget.agreements
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(
                                    item.text('propertyAddress', 'Linked home'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: !editable
                              ? null
                              : (value) => setState(() => agreementId = value!),
                        ),
                        const SizedBox(height: 20),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final option in IssueInput.categories)
                              SizedBox(
                                width: (constraints.maxWidth - 20) / 3,
                                child: Semantics(
                                  selected: category == option,
                                  button: true,
                                  child: Material(
                                    color: category == option
                                        ? AppColors.primary
                                        : AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: !editable
                                          ? null
                                          : () => setState(
                                              () => category = option,
                                            ),
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minHeight: 88,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              switch (option) {
                                                'Water' =>
                                                  Icons.water_drop_outlined,
                                                'Electric' =>
                                                  Icons.bolt_outlined,
                                                'Appliance' =>
                                                  Icons.kitchen_outlined,
                                                'Door / lock' =>
                                                  Icons
                                                      .door_front_door_outlined,
                                                _ => Icons.build_outlined,
                                              },
                                              color: category == option
                                                  ? Colors.white
                                                  : AppColors.muted,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              option,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.2,
                                                fontWeight: FontWeight.w600,
                                                color: category == option
                                                    ? Colors.white
                                                    : AppColors.heading,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      RepairPhotoSelection(
                        photos: photos,
                        enabled: editable,
                        onAdd: _addPhoto,
                        onRemove: (index) =>
                            setState(() => photos.removeAt(index)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: description,
                        enabled: editable,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: 'Tell us in a few words',
                          prefixIcon: Icon(Icons.edit_outlined),
                          hintText:
                              'For example: the kitchen tap has been leaking since yesterday.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Only your linked agreement participants and the team can see this report and its photos. A submitted photo is not proof that a repair is complete.',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : savedId == null
                              ? _send
                              : () => Navigator.pop(context),
                          child: Text(
                            savedId != null
                                ? 'Back to issues'
                                : busy
                                ? 'Sending…'
                                : 'Send',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.role, required this.onUpdates});
  final String role;
  final VoidCallback onUpdates;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        const Expanded(child: AppBrand(height: 30)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                role,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onUpdates,
              icon: const Icon(Icons.notifications_none),
              tooltip: 'Open issues',
            ),
          ),
        ),
      ],
    ),
  );
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: color == Colors.white
          ? Border.all(color: AppColors.border)
          : null,
    ),
    child: child,
  );
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primarySoft,
              child: Icon(icon, size: 21, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Flexible(
                child: Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (onTap != null)
              const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.label,
    required this.amount,
    this.green = false,
  });
  final String label;
  final int? amount;
  final bool green;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: green ? AppColors.successSoft : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 5),
        Text(
          amount == null ? 'Not recorded' : workspaceMoney(amount!),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ],
    ),
  );
}
