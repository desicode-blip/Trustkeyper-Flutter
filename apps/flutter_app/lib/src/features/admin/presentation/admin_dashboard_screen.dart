import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/session_bound_screen.dart';
import '../../tenant/data/tenant_setup.dart';
import '../../tenant/presentation/admin_tenant_setup_queue.dart';
import '../../account/data/account_gateway.dart';
import '../../account/presentation/account_restoration_queue.dart';
import '../../tenancy/move_out_screen.dart';
import '../../owner/presentation/manager_callback_screen.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_brand.dart';
import '../data/admin_repository.dart';
import 'admin_auth_screen.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/demo_agreement.dart';
import '../../broker/presentation/demo_agreement_screen.dart';
import '../../participants/data/participant_workspace.dart';
import '../../agreement_copies/admin_copy_upload_screen.dart';
import '../../agreement_copies/agreement_copy_screen.dart';
import '../../repairs/presentation/admin_repair_editor.dart';
import '../../inspections/inspection_screen.dart';

const _ink = Color(0xFF172231);
const _muted = Color(0xFF5E7087);
const _blue = Color(0xFF3160FF);
const _blueSoft = Color(0xFFEAF0FF);
const _line = Color(0xFFDCE2E9);
const _canvas = Color(0xFFF6F9FD);
const _red = Color(0xFFB3261E);
const _redSoft = Color(0xFFFDECEA);
const _green = Color(0xFF1E7A4C);
const _greenSoft = Color(0xFFE6F7EE);
const _amber = Color(0xFF9A5B00);
const _amberSoft = Color(0xFFFFF3E0);
const _purple = Color(0xFF6B3FE0);
const _purpleSoft = Color(0xFFF1EAFF);

enum AdminSection {
  dashboard('Dashboard', Icons.dashboard_outlined),
  signups('Sign-ups & logins', Icons.group_add_outlined),
  brokers('Brokers', Icons.badge_outlined),
  owners('Owners', Icons.real_estate_agent_outlined),
  tenants('Tenants', Icons.people_outline),
  properties('Properties', Icons.apartment_outlined),
  agreements('Agreements', Icons.description_outlined),
  documents('Documents', Icons.folder_copy_outlined),
  rentPayouts('Rent & payouts', Icons.payments_outlined),
  repairs('Repairs', Icons.home_repair_service_outlined),
  moveOuts('Move-outs', Icons.move_down_outlined),
  photoChecks('Photo checks', Icons.photo_library_outlined),
  callbacks('Owner callbacks', Icons.support_agent),
  settings('Settings', Icons.settings_outlined);

  const AdminSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.repository,
    this.adminDisplayName,
  });

  final AdminRepository? repository;
  final String? adminDisplayName;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminRepository _repository =
      widget.repository ?? FirebaseAdminRepository();
  late final Stream<AdminData> _dataStream = _repository.watchData();
  final _searchController = TextEditingController();
  final Map<AdminSection, int> _filters = {};
  final Map<String, String> _settingsDraft = {};
  AdminSection _section = AdminSection.dashboard;
  String _query = '';
  bool _showPayouts = false;
  String? _repairId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _canvas,
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: _ink,
          displayColor: _ink,
          fontFamily: 'Roboto',
        ),
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: _blue, error: _red),
      ),
      child: StreamBuilder<AdminData>(
        stream: _dataStream,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const AdminData();
          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 980;
              return Scaffold(
                appBar: desktop
                    ? null
                    : AppBar(
                        backgroundColor: Colors.white,
                        foregroundColor: _ink,
                        title: Text(_section.label),
                        actions: [
                          _notificationButton(data),
                          const SizedBox(width: 8),
                        ],
                      ),
                drawer: desktop
                    ? null
                    : Drawer(child: _sidebar(data, mobile: true)),
                body: Row(
                  children: [
                    if (desktop) SizedBox(width: 236, child: _sidebar(data)),
                    Expanded(
                      child: Column(
                        children: [
                          if (desktop) _topBar(data),
                          Expanded(
                            child: snapshot.hasError
                                ? _errorState(snapshot.error)
                                : _content(data, loading: !snapshot.hasData),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _sidebar(AdminData data, {bool mobile = false}) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
                  child: Row(
                    children: [
                      AppBrand(height: 30),
                      SizedBox(width: 10),
                      Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final section in AdminSection.values)
                      _navItem(
                        section,
                        badge: switch (section) {
                          AdminSection.brokers => data.waitingBrokers,
                          AdminSection.agreements =>
                            data.agreementsNeedingAction,
                          AdminSection.documents => data.documentsWaiting,
                          AdminSection.rentPayouts => data.failedPayouts,
                          AdminSection.repairs => data.openRepairs,
                          AdminSection.moveOuts => data.moveOutsNeedingAction,
                          _ => 0,
                        },
                        closeDrawer: mobile,
                      ),
                  ],
                ),
              ),
              _navButton(
                icon: Icons.logout,
                label: 'Log out',
                onTap: () async {
                  await FirebaseAdminAuthGateway().signOut();
                  if (mounted) context.go('/admin/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    AdminSection section, {
    required int badge,
    required bool closeDrawer,
  }) {
    final selected = _section == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? _blueSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => _section = section);
            if (closeDrawer) Navigator.pop(context);
          },
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    section.icon,
                    size: 20,
                    color: selected ? const Color(0xFF1F4AD1) : _muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? const Color(0xFF1F4AD1)
                            : const Color(0xFF2B3A4D),
                      ),
                    ),
                  ),
                  if (badge > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, size: 20, color: _muted),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }

  Widget _topBar(AdminData data) {
    var name = widget.adminDisplayName?.trim() ?? '';
    if (name.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      name = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : user?.email?.split('@').first ?? 'Admin';
    }
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search name, phone, property, agreement ID',
                hintStyle: const TextStyle(
                  color: Color(0xFF8C99AB),
                  fontSize: 14.5,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF8C99AB),
                  size: 20,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                filled: true,
                fillColor: _canvas,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _line),
                ),
              ),
            ),
          ),
          const Spacer(),
          _notificationButton(data),
          const SizedBox(width: 18),
          CircleAvatar(
            radius: 17,
            backgroundColor: _blueSoft,
            foregroundColor: const Color(0xFF1F4AD1),
            child: Text(
              _initials(name),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Super admin',
                style: TextStyle(fontSize: 11.5, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notificationButton(AdminData data) {
    return Badge(
      isLabelVisible: data.notificationCount > 0,
      label: Text(
        data.notificationCount > 99 ? '99+' : '${data.notificationCount}',
      ),
      backgroundColor: _red,
      child: IconButton(
        tooltip: 'Needs attention',
        onPressed: () => setState(() => _section = AdminSection.dashboard),
        icon: const Icon(Icons.notifications_none, color: _ink),
      ),
    );
  }

  Widget _content(AdminData data, {required bool loading}) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: loading
                ? const Padding(
                    key: ValueKey('loading'),
                    padding: EdgeInsets.only(top: 150),
                    child: Center(
                      child: CircularProgressIndicator(color: _blue),
                    ),
                  )
                : KeyedSubtree(
                    key: ValueKey(_section),
                    child: switch (_section) {
                      AdminSection.dashboard => _dashboard(data),
                      AdminSection.signups => _signups(data),
                      AdminSection.brokers => _brokers(data),
                      AdminSection.owners => _owners(data),
                      AdminSection.tenants => _tenants(data),
                      AdminSection.properties => _properties(data),
                      AdminSection.agreements => _agreements(data),
                      AdminSection.documents => _documents(data),
                      AdminSection.rentPayouts => _rentAndPayouts(data),
                      AdminSection.repairs =>
                        _repairId == null
                            ? _repairs(data)
                            : AdminRepairEditor(
                                key: ValueKey(_repairId),
                                issueId: _repairId!,
                                onBack: () => setState(() => _repairId = null),
                                photoReader: FirebaseParticipantIssueWriter(
                                  uid: () =>
                                      FirebaseAuth.instance.currentUser?.uid ??
                                      '',
                                ),
                              ),
                      AdminSection.moveOuts => _moveOuts(data),
                      AdminSection.photoChecks => _photoChecks(data),
                      AdminSection.settings => _settings(data),
                      AdminSection.callbacks => AdminCallbackQueue(
                        owners: data.users
                            .where(
                              (user) =>
                                  user.hasRole('owner') &&
                                  !user.boolean('paused'),
                            )
                            .map(
                              (user) => {
                                'uid': user.id,
                                'name': user.displayName,
                              },
                            )
                            .toList(),
                        managers: data.users
                            .where(
                              (user) =>
                                  user.hasRole('admin') &&
                                  !user.boolean('paused'),
                            )
                            .map(
                              (user) => {
                                'uid': user.id,
                                'name': user.displayName,
                              },
                            )
                            .toList(),
                      ),
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard(AdminData data) {
    final actions = <_DashboardAction>[
      if (data.waitingBrokers > 0)
        _DashboardAction(
          '${data.waitingBrokers} broker approvals',
          'Check identity and business details',
          Icons.badge_outlined,
          AdminSection.brokers,
          _amber,
          _amberSoft,
        ),
      if (data.documentsWaiting > 0)
        _DashboardAction(
          '${data.documentsWaiting} documents to check',
          'Uploaded by owners and tenants',
          Icons.folder_copy_outlined,
          AdminSection.documents,
          _purple,
          _purpleSoft,
        ),
      if (data.failedPayouts > 0)
        _DashboardAction(
          '${data.failedPayouts} failed payouts',
          'Money is held safely until resolved',
          Icons.account_balance_outlined,
          AdminSection.rentPayouts,
          _red,
          _redSoft,
        ),
      if (data.openRepairs > 0)
        _DashboardAction(
          '${data.openRepairs} open repairs',
          'Triage, approve bills and close work',
          Icons.home_repair_service_outlined,
          AdminSection.repairs,
          _blue,
          _blueSoft,
        ),
    ];
    final rentCollected = data.livePayments
        .where((payment) => payment.status == 'paid')
        .fold<int>(0, (total, payment) => total + _amountPaise(payment));
    final payoutsToday = data.payouts
        .where(
          (payout) => _isToday(payout.date(const ['scheduledAt', 'paidAt'])),
        )
        .fold<int>(0, (total, payout) => total + _amountPaise(payout));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Dashboard', 'What needs attention across TrustKeyper today.'),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric('Needs action', '${data.notificationCount}', _red),
            _metric('Rent collected', _moneyShort(rentCollected), _blue),
            _metric('Payouts today', _moneyShort(payoutsToday), _green),
            _metric('Open repairs', '${data.openRepairs}', _amber),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Needs your attention',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              DateFormat('d MMMM yyyy').format(DateTime.now()),
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (actions.isEmpty)
          _empty(
            icon: Icons.task_alt,
            title: 'Nothing to do right now',
            message:
                'All approvals, documents, payouts and repairs are up to date.',
          )
        else
          _card(
            child: Column(
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  _dashboardAction(actions[index]),
                  if (index < actions.length - 1)
                    const Divider(height: 1, color: Color(0xFFEDF1F6)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _signups(AdminData data) {
    final filteredUsers = switch (_filterIndex) {
      1 => data.users.where((user) => user.hasRole('broker')).toList(),
      2 => data.users.where((user) => user.hasRole('owner')).toList(),
      3 => data.users.where((user) => user.hasRole('tenant')).toList(),
      4 =>
        data.users
            .where(
              (user) =>
                  user.strings('roles').isEmpty ||
                  !user.boolean('onboardingCompleted'),
            )
            .toList(),
      5 => data.users.where((user) => user.boolean('paused')).toList(),
      _ => data.users,
    };
    final users = _matched(filteredUsers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headingRow(
          'Sign-ups & logins',
          'Everyone who joined, how they came in, and when they last opened the app',
          _outlineButton(
            Icons.download_outlined,
            'Export',
            () => _export(users),
          ),
        ),
        const SizedBox(height: 18),
        _chips([
          'All',
          'Brokers',
          'Owners',
          'Tenants',
          'Not finished',
          'Paused',
        ]),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Person',
            'Role',
            'Came from',
            'Status',
            'Joined',
            'Last login',
            '',
          ],
          records: users,
          row: (user) => [
            _person(user),
            Text(_roles(user)),
            Text(user.text(const ['source', 'cameFrom'], fallback: 'Direct')),
            _status(user.boolean('paused') ? 'paused' : user.status),
            Text(_date(user.date(const ['createdAt']))),
            Text(_date(user.date(const ['lastLoginAt', 'updatedAt']))),
            _smallButton('View', () => _personDialog(user)),
          ],
          emptyTitle: 'No people yet',
        ),
      ],
    );
  }

  Widget _brokers(AdminData data) {
    final allBrokers = data.users
        .where((user) => user.hasRole('broker'))
        .toList();
    final brokers = _matched(switch (_filterIndex) {
      1 => allBrokers.where((broker) => broker.status == 'approved').toList(),
      2 => allBrokers.where((broker) => broker.status == 'rejected').toList(),
      _ =>
        allBrokers
            .where(
              (broker) =>
                  broker.status != 'approved' &&
                  broker.status != 'rejected' &&
                  !broker.boolean('paused'),
            )
            .toList(),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Brokers',
          'New brokers can look around, but cannot make agreements until you approve',
        ),
        const SizedBox(height: 18),
        _chips(['Waiting · ${data.waitingBrokers}', 'Approved', 'Rejected']),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Broker',
            'City',
            'RERA no.',
            'Checks',
            'Signed up',
            '',
          ],
          records: brokers,
          row: (broker) => [
            _person(broker),
            Text(broker.text(const ['city'])),
            Text(broker.text(const ['reraNumber', 'reraNo'])),
            _status(broker.status),
            Text(_date(broker.date(const ['createdAt']))),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (broker.status != 'approved')
                  _smallButton(
                    'Approve',
                    () => _approveBroker(broker),
                    primary: true,
                  ),
                if (broker.status != 'rejected')
                  _smallButton(
                    'Reject',
                    () => _rejectBroker(broker),
                    danger: true,
                  ),
                _smallButton('Call', () => _call(broker)),
              ],
            ),
          ],
          emptyTitle: 'No brokers found',
        ),
      ],
    );
  }

  Widget _owners(AdminData data) {
    final allOwners = data.users
        .where((user) => user.hasRole('owner'))
        .toList();
    final owners = _matched(switch (_filterIndex) {
      1 =>
        allOwners
            .where(
              (owner) => data.payouts.any(
                (payout) =>
                    _belongsTo(payout, owner.id) && payout.status == 'failed',
              ),
            )
            .toList(),
      2 =>
        allOwners
            .where(
              (owner) => data.documents.any(
                (document) =>
                    _belongsTo(document, owner.id) &&
                    document.status != 'approved',
              ),
            )
            .toList(),
      3 =>
        allOwners
            .where(
              (owner) => _propertiesForUser(data, owner.id).every(
                (property) =>
                    _names(property, const [
                      'tenantNames',
                      'tenants',
                      'tenantName',
                    ]) ==
                    '—',
              ),
            )
            .toList(),
      4 =>
        allOwners
            .where(
              (owner) => const {'direct', 'self', 'self sign-up'}.contains(
                owner.text(const [
                  'source',
                  'cameFrom',
                ], fallback: 'direct').toLowerCase(),
              ),
            )
            .toList(),
      _ => allOwners,
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Owners',
          '${owners.length} owners · ${data.properties.length} properties',
        ),
        const SizedBox(height: 18),
        _chips([
          'All',
          'Payout problem · ${data.failedPayouts}',
          'Documents missing · ${data.documentsWaiting}',
          'No tenant',
          'Self sign-up',
        ]),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Owner',
            'Homes',
            'Rent / month',
            'Last payout',
            'Documents',
            'Came from',
            '',
          ],
          records: owners,
          row: (owner) {
            final homes = _propertiesForUser(data, owner.id);
            final payouts = data.payouts
                .where((payout) => _belongsTo(payout, owner.id))
                .toList();
            final documents = data.documents
                .where((document) => _belongsTo(document, owner.id))
                .toList();
            return [
              _person(owner),
              Text('${homes.length}'),
              Text(
                _money(
                  homes.fold<int>(
                    0,
                    (total, home) => total + _amountPaise(home),
                  ),
                ),
              ),
              payouts.isEmpty ? const Text('—') : _status(payouts.first.status),
              _status(
                documents.any((document) => document.status != 'approved')
                    ? 'missing'
                    : 'approved',
              ),
              Text(
                owner.text(const ['source', 'cameFrom'], fallback: 'Direct'),
              ),
              _smallButton('View', () => _personDialog(owner)),
            ];
          },
          emptyTitle: 'No owners yet',
        ),
      ],
    );
  }

  Widget _tenants(AdminData data) {
    final allTenants = data.users
        .where((user) => user.hasRole('tenant'))
        .toList();
    final tenants = _matched(switch (_filterIndex) {
      1 =>
        allTenants
            .where(
              (tenant) => data.livePayments.any(
                (payment) =>
                    _belongsTo(payment, tenant.id) &&
                    const {
                      'late',
                      'overdue',
                      'failed',
                    }.contains(payment.status),
              ),
            )
            .toList(),
      2 =>
        allTenants
            .where(
              (tenant) =>
                  tenant.status == 'share_change_requested' ||
                  tenant.boolean('shareChangeRequested'),
            )
            .toList(),
      3 =>
        allTenants
            .where(
              (tenant) => _propertiesForUser(
                data,
                tenant.id,
              ).any((property) => !property.boolean('tenantConfirmed')),
            )
            .toList(),
      4 =>
        allTenants
            .where(
              (tenant) => !data.photoChecks.any(
                (photo) =>
                    _belongsTo(photo, tenant.id) && photo.status == 'approved',
              ),
            )
            .toList(),
      _ => allTenants,
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Tenants', '${tenants.length} tenants'),
        const SizedBox(height: 18),
        _chips([
          'All',
          'Late · ${data.lateRent}',
          'Share change request',
          'Home not confirmed',
          'Move-in photos not checked',
        ]),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Tenant',
            'Home',
            'Their rent',
            'This month',
            'Move-in photos',
            '',
          ],
          records: tenants,
          row: (tenant) {
            final homes = _propertiesForUser(data, tenant.id);
            final payments = data.livePayments
                .where((payment) => _belongsTo(payment, tenant.id))
                .toList();
            final photos = data.photoChecks
                .where((photo) => _belongsTo(photo, tenant.id))
                .toList();
            return [
              _person(tenant),
              Text(homes.isEmpty ? '—' : _propertyName(homes.first)),
              Text(
                payments.isEmpty ? '—' : _money(_amountPaise(payments.first)),
              ),
              payments.isEmpty
                  ? const Text('—')
                  : _status(payments.first.status),
              _status(
                photos.any((photo) => photo.status == 'approved')
                    ? 'confirmed'
                    : 'not checked',
              ),
              _smallButton('View', () => _personDialog(tenant)),
            ];
          },
          emptyTitle: 'No tenants yet',
        ),
      ],
    );
  }

  Widget _properties(AdminData data) {
    final filteredProperties = switch (_filterIndex) {
      1 =>
        data.properties
            .where(
              (property) =>
                  const {'rented', 'occupied'}.contains(property.status),
            )
            .toList(),
      2 =>
        data.properties
            .where(
              (property) => const {'empty', 'vacant'}.contains(property.status),
            )
            .toList(),
      3 =>
        data.properties
            .where(
              (property) =>
                  const {'listed', 'available'}.contains(property.status),
            )
            .toList(),
      4 =>
        data.properties
            .where(
              (property) => data.agreements.any(
                (agreement) =>
                    agreement.text(const ['propertyId'], fallback: '') ==
                        property.id &&
                    !const {
                      'signed',
                      'completed',
                      'cancelled',
                    }.contains(agreement.status),
              ),
            )
            .toList(),
      _ => data.properties,
    };
    final properties = _matched(filteredProperties);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Properties', '${properties.length} properties'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/admin/owner-property-checks'),
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('Owner setup · free checks and fee offers'),
        ),
        const SizedBox(height: 18),
        _chips(['All', 'Rented', 'Empty', 'Listed', 'Agreement pending']),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Property',
            'Owner',
            'Tenant',
            'Status',
            'Last photo check',
            '',
          ],
          records: properties,
          row: (property) {
            final owners = _names(property, const [
              'ownerNames',
              'owners',
              'ownerName',
            ]);
            final tenants = _names(property, const [
              'tenantNames',
              'tenants',
              'tenantName',
            ]);
            final photos = data.photoChecks
                .where(
                  (photo) =>
                      photo.text(const ['propertyId'], fallback: '') ==
                      property.id,
                )
                .toList();
            return [
              _propertyCell(property),
              Text(owners),
              Text(tenants),
              _status(property.status),
              Text(
                photos.isEmpty
                    ? '—'
                    : _date(
                        photos.first.date(const ['reviewedAt', 'createdAt']),
                      ),
              ),
              _smallButton('View', () => _propertyDialog(property, data)),
            ];
          },
          emptyTitle: 'No properties yet',
        ),
      ],
    );
  }

  Widget _agreements(AdminData data) {
    final agreements = _matched(data.agreements);
    const stages = [
      ('Draft', ['draft']),
      ('Team review', ['review_requested', 'under_review', 'reviewed']),
      ('Documents', ['documents', 'documents_pending']),
      ('Waiting replies', ['waiting', 'waiting_replies', 'sent']),
      ('Signing (our team)', ['signing', 'ready_to_sign']),
      ('Signed', ['signed', 'completed']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/admin/signing-requests'),
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Signing-only requests · uploaded agreements'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (routeContext) => SessionBoundScreen(
                    users: FirebaseAuth.instance.authStateChanges().map(
                      (user) => user?.uid,
                    ),
                    initialUid: uid,
                    expectedUid: uid,
                    child:
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .snapshots(),
                          builder: (context, profile) {
                            if (profile.hasError ||
                                profile.hasData &&
                                    (profile.data?.data()?['paused'] == true ||
                                        (profile.data?.data()?['roles']
                                                    as List?)
                                                ?.contains('admin') !=
                                            true)) {
                              return const Scaffold(
                                body: Center(
                                  child: Text(
                                    'Team access is no longer available.',
                                  ),
                                ),
                              );
                            }
                            if (!profile.hasData) {
                              return const Scaffold(
                                body: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return AdminTenantSetupQueue(
                              gateway: FirebaseTenantSetupGateway(),
                            );
                          },
                        ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Tenant home and share corrections'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('Account closures and restoration'),
            onPressed: () {
              final auth = FirebaseAuth.instance,
                  uid = FirebaseAuth.instance.currentUser?.uid;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionBoundScreen(
                    expectedUid: uid,
                    initialUid: uid,
                    users: auth.authStateChanges().map((user) => user?.uid),
                    child: uid == null
                        ? const Scaffold(
                            body: Center(child: Text('Log in again.')),
                          )
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .snapshots(),
                            builder: (context, profile) {
                              if (profile.hasError ||
                                  profile.hasData &&
                                      (profile.data?.data()?['paused'] ==
                                              true ||
                                          !(profile.data?.data()?['roles']
                                                      as List? ??
                                                  const [])
                                              .contains('admin'))) {
                                return const Scaffold(
                                  body: Center(
                                    child: Text(
                                      'Team access is no longer available.',
                                    ),
                                  ),
                                );
                              }
                              if (!profile.hasData) {
                                return const Scaffold(
                                  body: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return AccountRestorationQueue(
                                gateway: FirebaseAccountRestorationGateway(),
                              );
                            },
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        _headingRow(
          'Agreements',
          'Where every agreement is right now',
          _outlineButton(
            Icons.download_outlined,
            'Export',
            () => _export(agreements),
          ),
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final stage in stages)
                Container(
                  width: 224,
                  margin: const EdgeInsets.only(right: 12),
                  child: _pipelineColumn(
                    stage.$1,
                    agreements
                        .where(
                          (agreement) => stage.$2.contains(agreement.status),
                        )
                        .toList(),
                    data,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _documents(AdminData data) {
    final documents = _matched(switch (_filterIndex) {
      1 =>
        data.documents
            .where((document) => document.status == 'approved')
            .toList(),
      2 =>
        data.documents
            .where(
              (document) => const {
                'asked_again',
                'rejected',
                'changes_requested',
              }.contains(document.status),
            )
            .toList(),
      _ =>
        data.documents
            .where(
              (document) => const {
                'pending',
                'waiting',
                'uploaded',
              }.contains(document.status),
            )
            .toList(),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Documents to check',
          '${data.documentsWaiting} waiting · uploaded by owners and tenants',
        ),
        const SizedBox(height: 18),
        _chips(['Waiting · ${data.documentsWaiting}', 'OK', 'Asked again']),
        const SizedBox(height: 14),
        if (documents.isEmpty)
          _empty(
            icon: Icons.folder_copy_outlined,
            title: 'No documents waiting',
            message: 'New uploads will appear here for review.',
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: documents
                .map(
                  (document) =>
                      SizedBox(width: 360, child: _documentCard(document)),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _rentAndPayouts(AdminData data) {
    final source = _showPayouts ? data.payouts : data.payments;
    final filteredRecords = switch ((_showPayouts, _filterIndex)) {
      (false, 1) => source.where((record) => record.status == 'paid').toList(),
      (false, 2) =>
        source
            .where(
              (record) =>
                  const {'pending', 'due', 'created'}.contains(record.status),
            )
            .toList(),
      (false, 3) =>
        source
            .where(
              (record) => const {'late', 'overdue'}.contains(record.status),
            )
            .toList(),
      (false, 4) =>
        source.where((record) => record.status == 'failed').toList(),
      (true, 1) => source.where((record) => record.status == 'ready').toList(),
      (true, 2) =>
        source
            .where(
              (record) =>
                  const {'processing', 'requested'}.contains(record.status),
            )
            .toList(),
      (true, 3) => source.where((record) => record.status == 'paid').toList(),
      (true, 4) => source.where((record) => record.status == 'failed').toList(),
      _ => source,
    };
    final records = _matched(filteredRecords);
    final collected = data.livePayments
        .where((payment) => payment.status == 'paid')
        .fold<int>(0, (subtotal, payment) => subtotal + _amountPaise(payment));
    final total = data.livePayments.fold<int>(
      0,
      (subtotal, payment) => subtotal + _amountPaise(payment),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Rent & payouts',
          _showPayouts
              ? 'Payouts go out after our fee and approved repairs'
              : '${DateFormat('MMMM yyyy').format(DateTime.now())} · ${_moneyShort(collected)} collected of ${_moneyShort(total)}',
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _tab(
              'Rent from tenants',
              !_showPayouts,
              () => setState(() {
                _showPayouts = false;
                _filters[_section] = 0;
              }),
            ),
            _tab(
              'Payouts to owners & brokers',
              _showPayouts,
              () => setState(() {
                _showPayouts = true;
                _filters[_section] = 0;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _chips(
          _showPayouts
              ? const ['All', 'Ready', 'Processing', 'Paid', 'Failed']
              : const ['All', 'Paid', 'Due', 'Late', 'Failed'],
        ),
        const SizedBox(height: 16),
        if (!_showPayouts) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric('Collected', _moneyShort(collected), _green),
              _metric('Remaining', _moneyShort(total - collected), _blue),
              _metric(
                'Late · ${data.lateRent}',
                _moneyShort(
                  data.livePayments
                      .where(
                        (payment) =>
                            const {'late', 'overdue'}.contains(payment.status),
                      )
                      .fold(
                        0,
                        (total, payment) => total + _amountPaise(payment),
                      ),
                ),
                _red,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _recordTable(
          headers: _showPayouts
              ? const ['To', 'Amount', 'Date', 'Bank', 'Status', '']
              : const ['Tenant', 'Amount', 'Due', 'Status', 'Follow-up', ''],
          records: records,
          row: _showPayouts
              ? (record) => _payoutRow(record)
              : (record) => _rentRow(record),
          emptyTitle: _showPayouts ? 'No payouts yet' : 'No rent records yet',
        ),
      ],
    );
  }

  Widget _repairs(AdminData data) {
    final repairs = _matched(switch (_filterIndex) {
      1 =>
        data.issues
            .where((repair) => repair.status == 'waiting_owner')
            .toList(),
      2 =>
        data.issues
            .where(
              (repair) => const {'closed', 'resolved'}.contains(repair.status),
            )
            .toList(),
      3 => data.issues,
      _ =>
        data.issues
            .where(
              (repair) => !const {
                'closed',
                'resolved',
                'cancelled',
              }.contains(repair.status),
            )
            .toList(),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Repairs',
          'Tenants raise, we fix. Above ₹2,000 needs owner approval.',
        ),
        const SizedBox(height: 18),
        _chips(['Open · ${data.openRepairs}', 'Waiting owner', 'Fixed', 'All']),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Repair',
            'Property',
            'Reported by',
            'Cost',
            'Status',
            '',
          ],
          records: repairs,
          row: (repair) => [
            _titleCell(
              repair.text(const ['title'], fallback: 'Repair request'),
              _date(repair.date(const ['createdAt'])),
            ),
            Text(repair.text(const ['propertyAddress', 'propertyName'])),
            Text(repair.text(const ['reportedByName', 'createdByName'])),
            Text(
              _money(repair.integer(const ['finalBillPaise', 'estimatePaise'])),
            ),
            _status(repair.status),
            _smallButton('Manage', () => _repairDialog(repair)),
          ],
          emptyTitle: 'No repair requests',
        ),
      ],
    );
  }

  Widget _moveOuts(AdminData data) {
    final moveOuts = _matched(switch (_filterIndex) {
      1 =>
        data.moveOuts
            .where(
              (moveOut) => const {
                'inspection',
                'inspection_due',
                'notice_received',
              }.contains(moveOut.status),
            )
            .toList(),
      2 =>
        data.moveOuts
            .where(
              (moveOut) => const {
                'settlement',
                'deposit_settlement',
                'awaiting_decisions',
                'awaiting_settlement',
                'disputed',
              }.contains(moveOut.status),
            )
            .toList(),
      3 =>
        data.moveOuts
            .where((moveOut) => moveOut.status == 'completed')
            .toList(),
      _ =>
        data.moveOuts
            .where(
              (moveOut) =>
                  !const {'completed', 'cancelled'}.contains(moveOut.status),
            )
            .toList(),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Move-outs',
          'Track notice, inspection, dues and deposit settlement',
        ),
        const SizedBox(height: 18),
        _chips([
          'Needs action · ${data.moveOutsNeedingAction}',
          'Inspection',
          'Settlement',
          'Completed',
        ]),
        const SizedBox(height: 14),
        _recordTable(
          headers: const [
            'Property',
            'Tenant',
            'Move-out date',
            'Inspection',
            'Deposit',
            '',
          ],
          records: moveOuts,
          row: (moveOut) => [
            _titleCell(
              moveOut.text(const ['propertyAddress', 'propertyName']),
              moveOut.id,
            ),
            Text(moveOut.text(const ['tenantName'])),
            Text(
              _date(moveOut.date(const ['date', 'moveOutAt', 'scheduledAt'])),
            ),
            _status(
              moveOut.text(const [
                'inspectionStatus',
              ], fallback: moveOut.status),
            ),
            Text(
              _money(
                moveOut.integer(const ['depositPaise', 'securityDepositPaise']),
              ),
            ),
            _smallButton(
              'Open move-out',
              () => _advanceMoveOut(moveOut),
              primary: true,
            ),
          ],
          emptyTitle: 'No move-outs in progress',
        ),
      ],
    );
  }

  Widget _photoChecks(AdminData data) {
    final now = DateTime.now();
    final photos = _matched(switch (_filterIndex) {
      1 => data.photoChecks.where((photo) {
        final dueAt = photo.date(const ['dueAt', 'scheduledAt', 'nextDueAt']);
        return dueAt != null &&
            dueAt.isAfter(now.subtract(const Duration(days: 1))) &&
            dueAt.isBefore(now.add(const Duration(days: 8)));
      }).toList(),
      2 =>
        data.photoChecks
            .where((photo) => !photo.boolean('tenantConfirmed'))
            .toList(),
      3 => data.photoChecks,
      _ =>
        data.photoChecks
            .where(
              (photo) => const {
                'flagged',
                'needs_repair',
                'damaged',
              }.contains(photo.status),
            )
            .toList(),
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Photo checks', 'Flagged photos and checks that are due'),
        const SizedBox(height: 18),
        _chips(['Flagged', 'Due this week', 'Tenant not confirmed', 'All']),
        const SizedBox(height: 14),
        if (photos.isEmpty)
          _empty(
            icon: Icons.photo_library_outlined,
            title: 'No photo checks yet',
            message: 'Move-in, regular and move-out checks will appear here.',
          )
        else
          _card(
            child: Column(
              children: [
                for (var index = 0; index < photos.length; index++) ...[
                  _photoRow(photos[index]),
                  if (index < photos.length - 1)
                    const Divider(height: 1, color: Color(0xFFEDF1F6)),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _settings(AdminData data) {
    String value(String key, int fallback) => _settingsDraft.putIfAbsent(
      key,
      () => '${data.settings[key] ?? fallback}',
    );
    final fee = value('feePercent', 5);
    final due = value('rentDueDay', 5);
    final payout = value('payoutDay', 7);
    final repair = value('repairApprovalRupees', 2000);
    final linkDays = value('documentLinkDays', 7);
    final reminder = value('rentReminderDays', 1);
    final call = value('teamCallDays', 15);
    final photos = value('photoCheckMonths', 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Settings',
          'Rules the whole app follows · every change is saved with your name and time',
        ),
        const SizedBox(height: 18),
        _card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Money',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _settingRow(
                  'TrustKeyper fee',
                  'Set per owner in their contract',
                  'feePercent',
                  fee,
                  '%',
                ),
                _settingRow(
                  'Rent due day',
                  'Default for new agreements',
                  'rentDueDay',
                  due,
                  'day',
                ),
                _settingRow(
                  'Owner payout day',
                  'After fee and repairs',
                  'payoutDay',
                  payout,
                  'day',
                ),
                _settingRow(
                  'Repair approval above',
                  'Owner must approve',
                  'repairApprovalRupees',
                  repair,
                  '₹',
                ),
                const Divider(height: 34, color: _line),
                const Text(
                  'Links, reminders and team',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _settingRow(
                  'Document link works for',
                  'Then broker must send again',
                  'documentLinkDays',
                  linkDays,
                  'days',
                ),
                _settingRow(
                  'Rent reminder after',
                  'Days late before WhatsApp',
                  'rentReminderDays',
                  reminder,
                  'days',
                ),
                _settingRow(
                  'Team calls tenant after',
                  'Days late',
                  'teamCallDays',
                  call,
                  'days',
                ),
                _settingRow(
                  'Regular photo check',
                  'Every',
                  'photoCheckMonths',
                  photos,
                  'months',
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: _primaryButton(
                    Icons.save_outlined,
                    'Save settings',
                    () => _perform(
                      () => _repository.saveSettings({
                        'feePercent':
                            int.tryParse(_settingsDraft['feePercent'] ?? fee) ??
                            5,
                        'rentDueDay':
                            int.tryParse(_settingsDraft['rentDueDay'] ?? due) ??
                            5,
                        'payoutDay':
                            int.tryParse(
                              _settingsDraft['payoutDay'] ?? payout,
                            ) ??
                            7,
                        'repairApprovalRupees':
                            int.tryParse(
                              _settingsDraft['repairApprovalRupees'] ?? repair,
                            ) ??
                            2000,
                        'documentLinkDays':
                            int.tryParse(
                              _settingsDraft['documentLinkDays'] ?? linkDays,
                            ) ??
                            7,
                        'rentReminderDays':
                            int.tryParse(
                              _settingsDraft['rentReminderDays'] ?? reminder,
                            ) ??
                            1,
                        'teamCallDays':
                            int.tryParse(
                              _settingsDraft['teamCallDays'] ?? call,
                            ) ??
                            15,
                        'photoCheckMonths':
                            int.tryParse(
                              _settingsDraft['photoCheckMonths'] ?? photos,
                            ) ??
                            3,
                      }),
                      success: 'Settings saved with an audit entry.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _heading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: _muted)),
      ],
    );
  }

  Widget _headingRow(String title, String subtitle, Widget action) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _heading(title, subtitle)),
        const SizedBox(width: 16),
        action,
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Container(
      width: 214,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13.5, color: _muted)),
        ],
      ),
    );
  }

  Widget _dashboardAction(_DashboardAction action) {
    return InkWell(
      onTap: () => setState(() => _section = action.section),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: action.softColor,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(action.icon, color: action.color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(child: _titleCell(action.title, action.subtitle)),
            const Icon(Icons.chevron_right, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _blueSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _blue),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips(List<String> labels) {
    final selectedIndex = _filterIndex.clamp(0, labels.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: labels.indexed
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: entry.$1 == selectedIndex ? _ink : Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: entry.$1 == selectedIndex ? _ink : _line,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => setState(() {
                      _filters[_section] = entry.$1;
                    }),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      child: Text(
                        entry.$2,
                        style: TextStyle(
                          color: entry.$1 == selectedIndex
                              ? Colors.white
                              : _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _recordTable({
    required List<String> headers,
    required List<AdminRecord> records,
    required List<Widget> Function(AdminRecord) row,
    required String emptyTitle,
  }) {
    if (records.isEmpty) {
      return _empty(
        icon: Icons.inbox_outlined,
        title: emptyTitle,
        message: 'Live Firebase records will appear here.',
      );
    }
    final rows = records.map(row).toList();
    final widths = List<double>.generate(
      headers.length,
      (index) => index == 0 ? 220 : 156,
    );
    return _card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: widths.fold<double>(0, (total, width) => total + width),
          child: Column(
            children: [
              Container(
                color: const Color(0xFFFAFBFD),
                height: 44,
                child: Row(
                  children: headers.indexed
                      .map(
                        (entry) => SizedBox(
                          width: widths[entry.$1],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                entry.$2.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _muted,
                                  letterSpacing: .4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              for (final cells in rows)
                Container(
                  constraints: const BoxConstraints(minHeight: 62),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFEDF1F6))),
                  ),
                  child: Row(
                    children: cells.indexed
                        .map(
                          (entry) => SizedBox(
                            width: widths[entry.$1],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: entry.$2,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _person(AdminRecord record) {
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: _blueSoft,
          foregroundColor: const Color(0xFF1F4AD1),
          child: Text(
            _initials(record.displayName),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _titleCell(
            record.displayName,
            record.text(const ['phone', 'email']),
          ),
        ),
      ],
    );
  }

  Widget _propertyCell(AdminRecord property) {
    return _titleCell(
      _propertyName(property),
      [
        property.text(const ['city'], fallback: ''),
        property.text(const ['configuration', 'bhk'], fallback: ''),
      ].where((value) => value.isNotEmpty).join(' · '),
    );
  }

  Widget _titleCell(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: _muted),
          ),
        ],
      ],
    );
  }

  Widget _status(String raw) {
    final normalized = raw.toLowerCase().replaceAll('_', ' ');
    final (background, foreground) = switch (normalized) {
      'approved' ||
      'paid' ||
      'signed' ||
      'completed' ||
      'confirmed' ||
      'closed' ||
      'ok' => (_greenSoft, _green),
      'failed' ||
      'rejected' ||
      'late' ||
      'overdue' ||
      'missing' ||
      'paused' => (_redSoft, _red),
      'waiting' ||
      'pending' ||
      'uploaded' ||
      'not checked' ||
      'agreement pending' => (_amberSoft, _amber),
      'repair created' ||
      'signing' ||
      'scheduled' ||
      'rented' => (_blueSoft, const Color(0xFF1F4AD1)),
      _ => (const Color(0xFFEEF1F5), _muted),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        normalized.isEmpty ? 'pending' : _capitalize(normalized),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  Widget _smallButton(
    String label,
    VoidCallback onPressed, {
    bool primary = false,
    bool danger = false,
  }) {
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: primary
              ? Colors.white
              : danger
              ? _red
              : _ink,
          backgroundColor: primary ? _blue : Colors.white,
          side: BorderSide(
            color: primary
                ? _blue
                : danger
                ? const Color(0xFFF2C4C0)
                : _line,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _outlineButton(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ink,
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _primaryButton(IconData icon, String label, VoidCallback onPressed) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _blue : _line,
              width: selected ? 3 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? _blue : _muted,
          ),
        ),
      ),
    );
  }

  Widget _pipelineColumn(
    String title,
    List<AdminRecord> agreements,
    AdminData data,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _status('${agreements.length}'),
          ],
        ),
        const SizedBox(height: 10),
        if (agreements.isEmpty)
          Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: const Text('No agreements', style: TextStyle(color: _muted)),
          )
        else
          for (final agreement in agreements)
            InkWell(
              onTap: () => _agreementDialog(agreement, data),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _titleCell(
                  agreement.text(const [
                    'propertyAddress',
                    'propertyName',
                  ], fallback: 'Agreement ${agreement.id}'),
                  agreement.text(const [
                    'adminStep',
                    'status',
                  ], fallback: 'Open agreement'),
                ),
              ),
            ),
      ],
    );
  }

  Widget _documentCard(AdminRecord document) {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _purpleSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: _purple,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _titleCell(
                    document.text(const [
                      'documentType',
                      'type',
                    ], fallback: 'Document'),
                    document.displayName,
                  ),
                ),
                _status(document.status),
              ],
            ),
            if (document.text(const [
              'issue',
              'reviewReason',
            ], fallback: '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                document.text(const ['issue', 'reviewReason']),
                style: const TextStyle(color: _red),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _smallButton(
                  'OK',
                  () => _perform(
                    () => _repository.reviewDocument(document.id, 'approved'),
                    success: 'Document marked OK.',
                  ),
                  primary: true,
                ),
                const SizedBox(width: 8),
                _smallButton(
                  'Ask again',
                  () => _askDocumentAgain(document),
                  danger: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rentRow(AdminRecord payment) => [
    _titleCell(
      payment.text(const ['tenantName', 'payerName'], fallback: 'Tenant'),
      payment.text(const ['propertyAddress', 'propertyName']),
    ),
    Text(_money(_amountPaise(payment))),
    Text(_date(payment.date(const ['dueAt']))),
    _status(
      payment.text(const ['mode'], fallback: '') == 'test'
          ? '${payment.status} · TEST'
          : payment.status,
    ),
    Text(payment.text(const ['lastFollowUp'], fallback: '—')),
    Wrap(
      spacing: 6,
      children: [
        if (payment.text(const ['mode'], fallback: '') == 'test')
          _smallButton('Test receipt', () => _testPaymentDialog(payment))
        else
          _smallButton(
            'Remind',
            () => _rentFollowUp(payment, 'reminder_queued'),
          ),
        if (payment.text(const ['mode'], fallback: '') != 'test' &&
            const {'late', 'overdue'}.contains(payment.status))
          _smallButton(
            'Notice',
            () => _rentFollowUp(payment, 'notice_queued'),
            danger: true,
          ),
      ],
    ),
  ];

  Future<void> _testPaymentDialog(AdminRecord payment) => showDialog<void>(
    context: context,
    builder: (_) => _AdminDialog(
      title: 'Razorpay TEST payment',
      subtitle:
          'No real money, bank payout or key release. Excluded from live rent totals.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detail('Tenant', payment.text(const ['payerName'])),
          _detail('Property', payment.text(const ['propertyAddress'])),
          _detail('Status', payment.status.replaceAll('_', ' ')),
          _detail('Test amount', _money(_amountPaise(payment))),
          _detail('Receipt', payment.text(const ['receiptNumber'])),
          _detail('Payment', payment.text(const ['paymentId'])),
          _detail('Order', payment.text(const ['orderId'])),
          _detail('Delivery', payment.text(const ['deliveryStatus'])),
          const Text(
            'Only backend-verified gateway captures are recorded. Review reconciliation-required records separately; this view cannot change balances.',
          ),
        ],
      ),
    ),
  );

  List<Widget> _payoutRow(AdminRecord payout) => [
    _titleCell(
      payout.text(const [
        'recipientName',
        'ownerName',
        'brokerName',
      ], fallback: 'Recipient'),
      payout.text(const ['recipientRole', 'description']),
    ),
    Text(_money(_amountPaise(payout))),
    Text(_date(payout.date(const ['scheduledAt', 'paidAt']))),
    Text(_bank(payout)),
    _status(payout.status),
    _smallButton(
      payout.status == 'failed' ? 'Fix' : 'View',
      () => _payoutDialog(payout),
      danger: payout.status == 'failed',
    ),
  ];

  Widget _photoRow(AdminRecord photo) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _canvas,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.image_outlined, color: _muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _titleCell(
              photo.text(const ['title', 'label'], fallback: 'Property photo'),
              '${photo.text(const ['propertyAddress', 'propertyName'])} · ${_date(photo.date(const ['createdAt']))}',
            ),
          ),
          _status(photo.status),
          const SizedBox(width: 12),
          _smallButton(
            'View',
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => InspectionScreen(
                  propertyId: photo.path.split('/')[1],
                  agreementId: photo.text(const ['agreementId']).isEmpty
                      ? null
                      : photo.text(const ['agreementId']),
                ),
              ),
            ),
            primary: true,
          ),
          const SizedBox(width: 8),
          _smallButton(
            'Make repair',
            () => _perform(
              () => _repository.createRepairFromPhoto(photo),
              success: 'Repair created from photo.',
            ),
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _settingRow(
    String title,
    String subtitle,
    String settingKey,
    String initialValue,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: _titleCell(title, subtitle)),
          SizedBox(
            width: 130,
            child: TextFormField(
              key: ValueKey('setting-$settingKey'),
              initialValue: initialValue,
              onChanged: (value) => _settingsDraft[settingKey] = value,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                suffixText: unit,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _line),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42, color: _red),
            const SizedBox(height: 12),
            const Text(
              'Could not load admin data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveBroker(AdminRecord broker) async {
    final confirmed = await _confirm(
      'Approve ${broker.displayName}?',
      'They will be able to create and manage agreements.',
      'Approve',
    );
    if (confirmed) {
      await _perform(
        () => _repository.approveBroker(broker.id),
        success: '${broker.displayName} approved.',
      );
    }
  }

  Future<void> _rejectBroker(AdminRecord broker) async {
    final reason = await _choiceDialog(
      title: 'Reject ${broker.displayName}?',
      subtitle: 'They will get a WhatsApp and email with the reason.',
      choices: const [
        'Fake details',
        'Not a broker',
        'Duplicate account',
        'Other',
      ],
      destructive: true,
    );
    if (reason == null) return;
    await _perform(
      () => _repository.rejectBroker(broker.id, reason, ''),
      success: 'Broker rejected and notification queued.',
    );
  }

  Future<void> _personDialog(AdminRecord person) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AdminDialog(
        title: person.displayName,
        subtitle:
            '${_roles(person)} · ${person.text(const ['phone', 'email'])}',
        child: Column(
          children: [
            _detail(
              'Status',
              person.boolean('paused') ? 'Paused' : _capitalize(person.status),
            ),
            _detail('Email', person.text(const ['email'])),
            _detail('Phone', person.text(const ['phone'])),
            _detail('City', person.text(const ['city'])),
            _detail('RERA no.', person.text(const ['reraNumber', 'reraNo'])),
            _detail(
              'Came from',
              person.text(const ['source', 'cameFrom'], fallback: 'Direct'),
            ),
            _detail('Joined', _date(person.date(const ['createdAt']))),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                _smallButton('Call', () => _call(person)),
                _smallButton('WhatsApp', () => _whatsApp(person)),
                _smallButton(
                  person.boolean('paused') ? 'Resume account' : 'Pause account',
                  () async {
                    Navigator.pop(dialogContext);
                    await _perform(
                      () => _repository.setUserPaused(
                        person.id,
                        !person.boolean('paused'),
                      ),
                      success: person.boolean('paused')
                          ? 'Account resumed.'
                          : 'Account paused.',
                    );
                  },
                  danger: !person.boolean('paused'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _propertyDialog(AdminRecord property, AdminData data) async {
    final agreements = data.agreements
        .where(
          (agreement) =>
              agreement.text(const ['propertyId'], fallback: '') == property.id,
        )
        .toList();
    final payments = data.livePayments
        .where(
          (payment) =>
              payment.text(const ['propertyId'], fallback: '') == property.id,
        )
        .toList();
    await showDialog<void>(
      context: context,
      builder: (context) => _AdminDialog(
        title: _propertyName(property),
        subtitle: [
          property.text(const ['city'], fallback: ''),
          property.text(const ['configuration', 'bhk'], fallback: ''),
        ].where((value) => value.isNotEmpty).join(' · '),
        child: Column(
          children: [
            _detail('Status', _capitalize(property.status)),
            _detail(
              'Owners',
              _names(property, const ['ownerNames', 'owners', 'ownerName']),
            ),
            _detail(
              'Tenants',
              _names(property, const ['tenantNames', 'tenants', 'tenantName']),
            ),
            _detail('Rent', _money(_amountPaise(property))),
            _detail(
              'Agreement',
              agreements.isEmpty
                  ? 'Not started'
                  : _capitalize(agreements.first.status),
            ),
            _detail(
              'Rent this month',
              payments.isEmpty
                  ? 'No record'
                  : _capitalize(payments.first.status),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _agreementDialog(AdminRecord agreement, AdminData data) async {
    const steps = [
      ('request_received', 'Request received'),
      ('reviewed', 'Demo terms reviewed · Not signed'),
    ];
    final current = agreement.text(const [
      'adminStep',
    ], fallback: agreement.status);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AdminDialog(
        title:
            '${agreement.text(const ['propertyAddress', 'propertyName'], fallback: 'Agreement')} · agreement',
        subtitle:
            'ID ${agreement.id} · broker ${agreement.text(const ['brokerName'], fallback: agreement.text(const ['brokerUid']))}',
        width: 660,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Team review · non-signable demo agreement',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (['reviewed', 'signed_copy_received'].contains(agreement.status))
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminCopyUploadScreen(
                        agreementId: agreement.id,
                        revision: agreement.integer(const ['revision']),
                        property: agreement.text(const ['propertyAddress']),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload completed agreement PDF'),
              ),
            if (agreement.data['agreementCopy'] is Map)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AgreementCopyScreen(
                        agreementId: agreement.id,
                        revision: agreement.integer(const ['revision']),
                        demo:
                            (agreement.data['agreementCopy'] as Map)['mode'] ==
                            'demo',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('Open published private copy'),
              ),
            for (final step in steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _stepReached(current, step.$1, steps)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: _stepReached(current, step.$1, steps)
                      ? _green
                      : _muted,
                ),
                title: Text(
                  step.$2,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: current == step.$1
                    ? _status('current')
                    : ![
                        'review_requested',
                        'under_review',
                      ].contains(agreement.status)
                    ? null
                    : _smallButton('Record review', () async {
                        Navigator.pop(dialogContext);
                        await _perform(
                          () => _repository.setAgreementStep(
                            agreement.id,
                            step.$1,
                            revision: agreement.integer(const ['revision']),
                          ),
                          success: '${step.$2} recorded.',
                        );
                      }),
              ),
            const SizedBox(height: 10),
            if ([
              'review_requested',
              'under_review',
              'reviewed',
            ].contains(agreement.status))
              _smallButton('Return to broker for corrections', () async {
                Navigator.pop(dialogContext);
                final reason = await _choiceDialog(
                  title: 'What should the broker correct?',
                  subtitle:
                      'The saved terms return to a private draft. A new saved revision is required for another review.',
                  choices: const [
                    'Check the property address.',
                    'Check owner and tenant details.',
                    'Correct the rent or deposit shares.',
                    'Check the dates, lock-in and notice.',
                    'Review the separate brokerage amounts.',
                  ],
                  destructive: false,
                );
                if (reason != null) {
                  await _perform(
                    () => _repository.returnAgreementDraft(
                      agreement.id,
                      reason,
                      revision: agreement.integer(const ['revision']),
                    ),
                    success: 'Draft returned with a correction reason.',
                  );
                }
              }),
            TextButton(
              onPressed: () {
                try {
                  final draft = AgreementDraft.fromMap(
                    agreement.id,
                    agreement.data,
                  );
                  final demo = DemoAgreement(draft);
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DemoAgreementScreen(agreement: demo),
                    ),
                  );
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This record is incomplete. Ask the broker to save a complete draft.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Read demo terms · Not for signing'),
            ),
            const Text(
              'Demo review is not legal signing. After external signing, publish the actual completed original using the private upload action. Never classify a demo PDF as an executed legal agreement. Money movement remains separate.',
              style: TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askDocumentAgain(AdminRecord document) async {
    final reason = await _choiceDialog(
      title: 'Ask ${document.displayName} again?',
      subtitle: 'They get a WhatsApp and email request with a new upload link.',
      choices: const [
        'Blurry',
        'Cut off',
        'Wrong document',
        'Name does not match',
      ],
      destructive: true,
    );
    if (reason == null) return;
    await _perform(
      () => _repository.reviewDocument(
        document.id,
        'asked_again',
        reason: reason,
      ),
      success: 'New upload request queued.',
    );
  }

  Future<void> _rentFollowUp(AdminRecord payment, String action) async {
    await _perform(
      () => _repository.recordRentFollowUp(payment.id, action),
      success: action == 'notice_queued'
          ? 'Payment notice recorded.'
          : 'Reminder recorded.',
    );
  }

  Future<void> _payoutDialog(AdminRecord payout) async {
    final action = await _choiceDialog(
      title: payout.status == 'failed'
          ? 'Payout failed · ${_money(_amountPaise(payout))}'
          : 'Payout · ${_money(_amountPaise(payout))}',
      subtitle:
          '${payout.text(const ['recipientName', 'ownerName'], fallback: 'Recipient')} · ${_bank(payout)} · ${payout.text(const ['failureReason', 'bankReply'], fallback: 'Money movement is handled only by the approved payment backend.')}',
      choices: const [
        'Remind owner to update bank',
        'Retry same bank',
        'Hold and call owner',
      ],
      destructive: false,
    );
    if (action == null) return;
    await _perform(
      () => _repository.requestPayoutAction(payout.id, action),
      success:
          'Payout action requested. No transfer was initiated from this client.',
    );
  }

  Future<void> _repairDialog(AdminRecord repair) async {
    setState(() => _repairId = repair.id);
  }

  Future<void> _advanceMoveOut(AdminRecord moveOut) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MoveOutScreen(
          agreementId: moveOut.text(const [
            'agreementId',
          ], fallback: moveOut.id),
          role: 'admin',
          initialPage: 'report',
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _choiceDialog({
    required String title,
    required String subtitle,
    required List<String> choices,
    required bool destructive,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _AdminDialog(
        title: title,
        subtitle: subtitle,
        child: Column(
          children: choices
              .map(
                (choice) => ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  title: Text(choice),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, choice),
                  textColor: destructive ? _red : _ink,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(label, style: const TextStyle(color: _muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _perform(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success), backgroundColor: _green));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not complete the action: $error'),
          backgroundColor: _red,
        ),
      );
    }
  }

  Future<void> _call(AdminRecord person) async {
    final phone = person
        .text(const ['phone'], fallback: '')
        .replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _whatsApp(AdminRecord person) async {
    final phone = person
        .text(const ['phone'], fallback: '')
        .replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) return;
    await launchUrl(
      Uri.parse('https://wa.me/$phone'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _export(List<AdminRecord> records) async {
    final csv = records
        .map((record) => '${record.id},${record.displayName},${record.status}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: 'id,name,status\n$csv'));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard.')));
  }

  List<AdminRecord> _matched(List<AdminRecord> records) {
    if (_query.isEmpty) return records;
    return records
        .where(
          (record) => '${record.id} ${record.data.values.join(' ')}'
              .toLowerCase()
              .contains(_query),
        )
        .toList();
  }

  int get _filterIndex => _filters[_section] ?? 0;
}

class _AdminDialog extends StatelessWidget {
  const _AdminDialog({
    required this.title,
    required this.subtitle,
    required this.child,
    this.width = 520,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(subtitle, style: const TextStyle(color: _muted)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardAction {
  const _DashboardAction(
    this.title,
    this.subtitle,
    this.icon,
    this.section,
    this.color,
    this.softColor,
  );
  final String title;
  final String subtitle;
  final IconData icon;
  final AdminSection section;
  final Color color;
  final Color softColor;
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'A';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String _roles(AdminRecord user) {
  final roles = user.strings('roles');
  return roles.isEmpty ? 'User' : roles.map(_capitalize).join(', ');
}

String _capitalize(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return '—';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String _date(DateTime? date) =>
    date == null ? '—' : DateFormat('d MMM yyyy').format(date);

String _money(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(paise / 100);

String _moneyShort(int paise) {
  final rupees = paise / 100;
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)} L';
  if (rupees >= 1000) return '₹${(rupees / 1000).toStringAsFixed(1)} K';
  return _money(paise);
}

int _amountPaise(AdminRecord record) {
  final paise = record.integer(const [
    'amountPaise',
    'monthlyRentPaise',
    'rentPaise',
    'totalPaise',
  ]);
  if (paise != 0) return paise;
  return record.integer(const ['amount', 'monthlyRent', 'rent']) * 100;
}

String _propertyName(AdminRecord property) => property.text(const [
  'propertyAddress',
  'propertyName',
  'name',
  'address',
], fallback: 'Property ${property.id}');

String _names(AdminRecord record, List<String> keys) {
  for (final key in keys) {
    final value = record.data[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) {
      final names = value
          .map(
            (item) => item is Map ? item['name']?.toString() : item?.toString(),
          )
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) return names;
    }
  }
  return '—';
}

bool _belongsTo(AdminRecord record, String userId) {
  return record.strings('participantUids').contains(userId) ||
      record.text(const [
            'userId',
            'ownerUid',
            'tenantUid',
            'recipientUid',
          ], fallback: '') ==
          userId;
}

List<AdminRecord> _propertiesForUser(AdminData data, String userId) =>
    data.properties.where((property) => _belongsTo(property, userId)).toList();

String _bank(AdminRecord payout) {
  final bank = payout.text(const ['bankName'], fallback: 'Bank');
  final last4 = payout.text(const [
    'bankAccountLast4',
    'accountLast4',
  ], fallback: '—');
  return '$bank · $last4';
}

bool _isToday(DateTime? date) {
  if (date == null) return false;
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

bool _stepReached(String current, String step, List<(String, String)> steps) {
  final currentIndex = steps.indexWhere((item) => item.$1 == current);
  final stepIndex = steps.indexWhere((item) => item.$1 == step);
  return currentIndex >= 0 && stepIndex <= currentIndex;
}
