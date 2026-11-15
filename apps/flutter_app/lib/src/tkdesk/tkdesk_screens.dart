import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../features/broker/data/broker_property_repository.dart';
import '../tk2/tk2_invite.dart';
import 'tkdesk_helpers.dart';
import 'tkdesk_lead.dart';
import 'tkdesk_match.dart';
import 'tkdesk_store.dart';
import 'tkdesk_web.dart';

/// Which desk section is open and which lead is selected (laptop layout).
class DeskController extends ChangeNotifier {
  /// 0 Today · 1 Tenants · 2 Homes · 3 Import · 4 Helpers · 10 = an app tab.
  int section = 0;
  String? tenantId;
  String? homeId;

  void go(int s) {
    section = s;
    notifyListeners();
  }

  void open(Lead l) {
    if (l.isTenant) {
      tenantId = l.id;
      section = 1;
    } else {
      homeId = l.id;
      section = 2;
    }
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Laptop shell: sidebar with the lead sections and the TK2 app tabs.
// ---------------------------------------------------------------------------

class DeskWide extends StatelessWidget {
  const DeskWide({required this.ctrl, required this.store, required this.appTab, required this.onAppTab, required this.appPages, super.key});
  final DeskController ctrl;
  final DeskStore store;
  final int appTab;
  final ValueChanged<int> onAppTab;
  final List<Widget> appPages;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, store]),
      builder: (context, _) {
        final s = ctrl.section;
        Widget item(IconData icon, String label, bool on, VoidCallback tap, {int? count}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          child: Material(
            color: on ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: on ? AppColors.primaryDark : AppColors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? AppColors.primaryDark : AppColors.body)),
                    ),
                    if (count != null && count > 0) _Badge('$count'),
                  ],
                ),
              ),
            ),
          ),
        );
        Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 16, 6),
          child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.muted)),
        );
        final sidebar = Container(
          width: 236,
          decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: AppColors.border))),
          child: ListView(
            padding: const EdgeInsets.only(top: 20, bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Image.asset('assets/images/trustkeyper-mark.png', width: 28, height: 28),
                    const SizedBox(width: 10),
                    const Text('TrustKeyper', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.heading)),
                  ],
                ),
              ),
              heading('Leads'),
              item(Icons.today_outlined, 'Today', s == 0, () => ctrl.go(0), count: store.readyTenants.length),
              item(Icons.person_search_outlined, 'Tenants', s == 1, () => ctrl.go(1)),
              item(Icons.home_work_outlined, 'Homes', s == 2, () => ctrl.go(2)),
              item(Icons.upload_file_outlined, 'Import leads', s == 3, () => ctrl.go(3)),
              item(Icons.smart_toy_outlined, 'AI helpers', s == 4, () => ctrl.go(4), count: store.helperNotices().length),
              heading('App'),
              for (final (i, icon, label) in [
                (0, Icons.home_outlined, 'Home'),
                (1, Icons.event_available_outlined, 'Visits'),
                (2, Icons.account_balance_wallet_outlined, 'Payments'),
                (3, Icons.person_outline, 'Profile'),
              ])
                item(icon, label, s == 10 && appTab == i, () {
                  onAppTab(i);
                  ctrl.go(10);
                }),
              const SizedBox(height: 18),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _SaveState(store: store)),
            ],
          ),
        );
        final Widget body = switch (s) {
          0 => DeskToday(store: store, ctrl: ctrl),
          1 => _Split(
            list: TenantList(store: store, selected: ctrl.tenantId, onOpen: ctrl.open),
            detail: ctrl.tenantId == null || store.byId(ctrl.tenantId!) == null
                ? const _Empty('Pick a tenant to see the homes that fit.')
                : TenantPage(key: ValueKey(ctrl.tenantId), store: store, lead: store.byId(ctrl.tenantId!)!, onOpen: ctrl.open),
          ),
          2 => _Split(
            list: HomeList(store: store, selected: ctrl.homeId, onOpen: ctrl.open),
            detail: ctrl.homeId == null || store.byId(ctrl.homeId!) == null
                ? const _Empty('Pick a home to see its details and the tenants it suits.')
                : HomePage(key: ValueKey(ctrl.homeId), store: store, lead: store.byId(ctrl.homeId!)!, onOpen: ctrl.open),
          ),
          3 => DeskImport(store: store),
          4 => DeskHelpers(store: store),
          _ => Container(
            color: AppColors.surfaceMuted,
            alignment: Alignment.topCenter,
            child: Container(
              width: 460,
              decoration: const BoxDecoration(color: Colors.white, border: Border.symmetric(vertical: BorderSide(color: AppColors.border))),
              child: IndexedStack(index: appTab, children: appPages),
            ),
          ),
        };
        return Scaffold(
          backgroundColor: AppColors.surfaceMuted,
          body: Row(children: [sidebar, Expanded(child: body)]),
        );
      },
    );
  }
}

/// Phone layout: the lead sections in one screen with tabs (opened from Home).
class DeskNarrow extends StatelessWidget {
  const DeskNarrow({required this.store, super.key});
  final DeskStore store;

  @override
  Widget build(BuildContext context) {
    void open(Lead l) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(l.title)),
          body: ListenableBuilder(
            listenable: store,
            builder: (c, _) => l.isTenant ? TenantPage(store: store, lead: l, onOpen: open) : HomePage(store: store, lead: l, onOpen: open),
          ),
        ),
      ),
    );
    final ctrl = DeskController();
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leads'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Today'), Tab(text: 'Tenants'), Tab(text: 'Homes'), Tab(text: 'Import'), Tab(text: 'AI helpers')],
          ),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) => TabBarView(
            children: [
              DeskToday(store: store, ctrl: ctrl, onOpen: open),
              TenantList(store: store, onOpen: open),
              HomeList(store: store, onOpen: open),
              DeskImport(store: store),
              DeskHelpers(store: store),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

class DeskToday extends StatelessWidget {
  const DeskToday({required this.store, required this.ctrl, this.onOpen, super.key});
  final DeskStore store;
  final DeskController ctrl;
  final ValueChanged<Lead>? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen ?? ctrl.open;
    final ready = store.readyTenants;
    final calls = store.needCall;
    final follow = store.followUps;
    final notices = store.helperNotices();
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        const _H1('Today'),
        Text(
          '${ready.length} tenants to call with homes that fit · ${calls.length} leads need a call for details · ${follow.length} follow-ups due',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        if (!store.cloud) _ConnectCloud(store: store),
        if (store.cloudError.isNotEmpty && store.teamPass.isNotEmpty) _Banner.warn(store.cloudError),
        if (store.cloud && store.backupDue) _Banner.info('Daily backup: keep a copy of everything on this laptop too.', action: ('Download backup', () => _backup(context, store))),
        for (final (what, job) in notices) _Banner.info('Time to add an AI helper: $what Hand out $job.', action: ('See jobs', () => ctrl.go(4))),
        const SizedBox(height: 8),
        _Section(
          title: 'Ready to call',
          hint: 'Tenants with homes that fit. Call them and talk through these homes.',
          empty: 'No tenant is ready yet. Import leads or fill in sizes below.',
          children: [for (final t in ready) _ReadyRow(store: store, t: t, onOpen: open)],
        ),
        _Section(
          title: 'Call to get details',
          hint: 'Only a number or a post so far. Call, ask the size (and budget or rent), and fill it in.',
          empty: 'Nothing waiting.',
          children: [for (final l in calls) _LeadRow(store: store, l: l, onOpen: open, missing: true)],
        ),
        _Section(
          title: 'Follow-ups due',
          empty: 'No follow-ups due today.',
          children: [for (final l in follow) _LeadRow(store: store, l: l, onOpen: open)],
        ),
      ],
    );
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({required this.store, required this.t, required this.onOpen});
  final DeskStore store;
  final Lead t;
  final ValueChanged<Lead> onOpen;

  @override
  Widget build(BuildContext context) {
    final rec = store.recommend(t);
    final top = rec.all.take(3).toList();
    return _Card(
      onTap: () => onOpen(t),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.heading)),
                const SizedBox(height: 4),
                Text(needLine(t), style: const TextStyle(color: AppColors.body)),
                const SizedBox(height: 8),
                _CallButtons(phone: t.phone, compact: true),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: top.isEmpty
                ? const Text('No home fits yet.', style: TextStyle(color: AppColors.muted))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in top)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: f.ok ? AppColors.successSoft : AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${f.home.title} · ${rupees(f.home.rent)}${f.ok ? '' : ' · close'}',
                            style: TextStyle(fontSize: 13, color: f.ok ? AppColors.success : AppColors.warning),
                          ),
                        ),
                      if (rec.matches.length > 3) Padding(padding: const EdgeInsets.only(top: 8), child: Text('+${rec.matches.length - 3} more', style: const TextStyle(color: AppColors.muted))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

class TenantList extends StatefulWidget {
  const TenantList({required this.store, required this.onOpen, this.selected, super.key});
  final DeskStore store;
  final ValueChanged<Lead> onOpen;
  final String? selected;

  @override
  State<TenantList> createState() => _TenantListState();
}

class _TenantListState extends State<TenantList> {
  String filter = 'Looking';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = store.tenants.where((t) {
      final ok = switch (filter) {
        'Looking' => t.active && t.ready,
        'Needs a call' => t.active && !t.ready,
        'Closed' => !t.active,
        _ => true,
      };
      return ok && _matches(t, q);
    }).toList();
    return _ListPane(
      title: 'Tenants',
      filters: const ['Looking', 'Needs a call', 'Closed', 'All'],
      filter: filter,
      onFilter: (f) => setState(() => filter = f),
      onSearch: (s) => setState(() => q = s),
      addLabel: 'Add tenant',
      onAdd: () => widget.onOpen(store.add(LeadKind.tenant)),
      children: [
        for (final t in all)
          _ListRow(
            selected: widget.selected == t.id,
            title: t.title,
            sub: t.ready ? needLine(t) : 'Needs a call · ${phoneText(t.phone)}',
            trailing: t.ready ? '${store.recommend(t).matches.length} fit' : '',
            onTap: () => widget.onOpen(t),
          ),
      ],
    );
  }
}

class HomeList extends StatefulWidget {
  const HomeList({required this.store, required this.onOpen, this.selected, super.key});
  final DeskStore store;
  final ValueChanged<Lead> onOpen;
  final String? selected;

  @override
  State<HomeList> createState() => _HomeListState();
}

class _HomeListState extends State<HomeList> {
  String filter = 'Active';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = store.homes.where((h) {
      final ok = switch (filter) {
        'Active' => h.status == HomeState.active && h.ready,
        'Needs a call' => h.status == HomeState.active && !h.ready,
        'Not active' => h.status == HomeState.inactive,
        'Cancelled' => h.status == HomeState.cancelled,
        _ => true,
      };
      return ok && _matches(h, q);
    }).toList();
    return _ListPane(
      title: 'Homes',
      filters: const ['Active', 'Needs a call', 'Not active', 'Cancelled', 'All'],
      filter: filter,
      onFilter: (f) => setState(() => filter = f),
      onSearch: (s) => setState(() => q = s),
      addLabel: 'Add home',
      onAdd: () => widget.onOpen(store.add(LeadKind.home)),
      children: [
        for (final h in all)
          _ListRow(
            selected: widget.selected == h.id,
            title: h.title,
            sub: h.ready ? homeLine(h) : 'Needs a call · ${phoneText(h.phone)}',
            trailing: h.id.startsWith('tk2:') ? 'In app' : '',
            onTap: () => widget.onOpen(h),
          ),
      ],
    );
  }
}

bool _matches(Lead l, String q) {
  if (q.trim().isEmpty) return true;
  final s = q.toLowerCase();
  return l.f.values.any((v) => v.toString().toLowerCase().contains(s)) || (l.source['text'] ?? '').toString().toLowerCase().contains(s);
}

String needLine(Lead t) {
  final min = t.numOf('budgetMin'), max = t.numOf('budgetMax');
  final budget = max > 0 ? (min > 0 ? '${rupees(min)}–${rupees(max)}' : 'up to ${rupees(max)}') : 'budget not known';
  return [
    bhkText(t.bhk),
    budget + (t.yes('budgetRentOnly') ? ' + maint.' : ''),
    if (t.areas.isNotEmpty) t.areas.map(cap).join(', '),
    if (t.has('furnishing')) cap(t.str('furnishing')),
    if (t.has('who')) cap(t.str('who')),
  ].where((e) => e.isNotEmpty).join(' · ');
}

String homeLine(Lead h) {
  final maint = h.numOf('maint');
  return [
    bhkText(h.bhk),
    h.rent > 0 ? rupees(h.rent) + (h.yes('maintIncl') ? ' incl. maint.' : (maint > 0 ? ' + ${rupees(maint)}' : '')) : 'rent not known',
    if (h.has('furnishing')) cap(h.str('furnishing')),
    if (h.has('area') && h.has('society')) cap(h.str('area')),
  ].where((e) => e.isNotEmpty).join(' · ');
}

// ---------------------------------------------------------------------------
// Tenant page: the tenant fixed on the left, the homes that fit on the right.
// ---------------------------------------------------------------------------

class TenantPage extends StatelessWidget {
  const TenantPage({required this.store, required this.lead, required this.onOpen, super.key});
  final DeskStore store;
  final Lead lead;
  final ValueChanged<Lead> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = lead;
    final rec = store.recommend(t);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Fields(store: store, lead: t),
        _Notes(store: store, lead: t),
        _Origin(lead: t),
        _History(lead: t),
      ],
    );
    final homes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                !t.ready ? 'Add the size (BHK) to see homes' : (rec.matches.isEmpty ? 'No home fits yet' : '${rec.matches.length} ${rec.matches.length == 1 ? 'home fits' : 'homes fit'}'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send homes'),
              onPressed: rec.all.isEmpty
                  ? null
                  : () {
                      store.logSend(t, rec.all.length);
                      showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Coming soon'),
                          content: const Text('Sending homes to the tenant comes in the next version. For now, call the tenant and share these homes on the call.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
                        ),
                      );
                    },
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (t.ready) const Text('Best first. Green fits, orange is close, blue is to ask on the call.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        for (final f in rec.matches) _FitCard(store: store, fit: f, onOpen: onOpen),
        if (rec.near.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Text('Close, but one thing does not fit', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading)),
          ),
          for (final f in rec.near) _FitCard(store: store, fit: f, onOpen: onOpen),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final header = _PersonHeader(store: store, lead: t);
        if (c.maxWidth < 820) {
          return ListView(padding: const EdgeInsets.all(20), children: [header, const SizedBox(height: 16), homes, const SizedBox(height: 20), details]);
        }
        return Column(
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(28, 24, 28, 12), child: header),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 380,
                    child: ListView(padding: const EdgeInsets.fromLTRB(28, 4, 12, 40), children: [details]),
                  ),
                  Expanded(
                    child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 28, 40), children: [homes]),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FitCard extends StatelessWidget {
  const _FitCard({required this.store, required this.fit, required this.onOpen});
  final DeskStore store;
  final Fit fit;
  final ValueChanged<Lead> onOpen;

  @override
  Widget build(BuildContext context) {
    final h = fit.home;
    return _Card(
      onTap: () => onOpen(h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(h.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.heading))),
              if (h.id.startsWith('tk2:')) const _Badge('In app'),
              if (h.f['agent'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: _Badge('Agent')),
            ],
          ),
          const SizedBox(height: 4),
          Text(homeLine(h), style: const TextStyle(color: AppColors.body)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in fit.ticks) _Tag(x, AppColors.success, AppColors.successSoft, Icons.check),
              for (final x in fit.marks) _Tag(x, AppColors.warning, AppColors.warningSoft, Icons.error_outline),
              for (final x in fit.ask) _Tag('Ask on call: $x', AppColors.primaryDark, AppColors.primarySoft, Icons.call_outlined),
              for (final x in fit.blocks) _Tag(x, AppColors.error, AppColors.errorSoft, Icons.close),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  [if (h.personName.isNotEmpty) 'Owner: ${h.personName}', if (h.phone.isNotEmpty) phoneText(h.phone)].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
              _CallButtons(phone: h.phone, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home page
// ---------------------------------------------------------------------------

class HomePage extends StatelessWidget {
  const HomePage({required this.store, required this.lead, required this.onOpen, super.key});
  final DeskStore store;
  final Lead lead;
  final ValueChanged<Lead> onOpen;

  @override
  Widget build(BuildContext context) {
    final h = lead;
    final inApp = h.id.startsWith('tk2:');
    final fits = h.status == HomeState.active && h.ready ? tenantsFor(h, store.tenants) : <(Lead, Fit)>[];
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (inApp || h.listingId.isNotEmpty)
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open in app'),
            onPressed: () => context.push('/listing/${inApp ? h.id.substring(4) : h.listingId}'),
          )
        else
          FilledButton.icon(
            icon: const Icon(Icons.add_home_outlined, size: 18),
            label: const Text('Add to my properties'),
            onPressed: !h.ready ? null : () => _addToApp(context, store, h),
          ),
        if (!inApp)
          OutlinedButton.icon(
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Send link to owner'),
            onPressed: h.phone.isEmpty
                ? null
                : () => showTk2OwnerInvite(
                    context,
                    ownerName: h.personName,
                    phone: h.phone,
                    title: 'Send link to owner',
                    message: () async {
                      final link = await store.app.ownerLink(h.title, h.personName, h.phone);
                      final first = h.personName.split(' ').first;
                      return 'Hi${first.isEmpty ? '' : ' $first'}, this is ${store.app.brokerName.isEmpty ? 'TrustKeyper' : '${store.app.brokerName} from TrustKeyper'}. Please add your home\'s details and photos here, so I can show it to the right tenants: $link';
                    },
                  ),
          ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        _PersonHeader(store: store, lead: h),
        const SizedBox(height: 14),
        actions,
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, c) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (inApp) const _Banner.info('This property is in your app. Change its details there.'),
                _Fields(store: store, lead: h),
                _Notes(store: store, lead: h),
                _Origin(lead: h),
                _History(lead: h),
              ],
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  h.status != HomeState.active
                      ? 'Not active, so it is not matched'
                      : (!h.ready ? 'Add size and rent to match it' : '${fits.length} ${fits.length == 1 ? 'tenant fits' : 'tenants fit'}'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading),
                ),
                const SizedBox(height: 12),
                for (final (t, f) in fits)
                  _Card(
                    onTap: () => onOpen(t),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading)),
                        const SizedBox(height: 4),
                        Text(needLine(t), style: const TextStyle(color: AppColors.body)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [for (final x in f.marks) _Tag(x, AppColors.warning, AppColors.warningSoft, Icons.error_outline)]),
                      ],
                    ),
                  ),
              ],
            );
            if (c.maxWidth < 760) return Column(children: [left, const SizedBox(height: 20), right]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 380, child: left),
                const SizedBox(width: 24),
                Expanded(child: right),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Makes a TK2 property from a home lead: the house facts are saved through the
/// app's own store, then the app's rent screen opens (same flow as "Add property").
Future<void> _addToApp(BuildContext context, DeskStore store, Lead h) async {
  final furn = h.str('furnishing');
  final p = await store.app.saveProperty(
    BrokerProperty(
      id: '',
      address: BrokerProperty.compose(flat: h.str('flat'), society: h.str('society'), area: cap(h.str('area')), city: 'Hyderabad'),
      flat: [h.str('tower'), h.str('flat')].where((e) => e.isNotEmpty).join(' / '),
      society: h.str('society'),
      area: cap(h.str('area')),
      city: 'Hyderabad',
      rooms: bhkText(h.bhk),
      floor: h.numOf('floor').round(),
      totalFloors: h.numOf('floors').round(),
      furnishing: furn.startsWith('fully') ? 'Full' : (furn.startsWith('semi') ? 'Semi' : (furn.isEmpty ? 'Semi' : 'Empty')),
      sizeSqFt: h.numOf('sqft') > 0 ? h.numOf('sqft') : null,
      facing: h.has('facing') ? cap(h.str('facing')) : null,
      carParking: h.numOf('parking').round(),
    ),
  );
  store.linkListing(h, p.id);
  if (context.mounted) await context.push('/listing/${p.id}?new=1');
}

// ---------------------------------------------------------------------------
// Header, fields (edit in place), notes, origin, history
// ---------------------------------------------------------------------------

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.store, required this.lead});
  final DeskStore store;
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final inApp = l.id.startsWith('tk2:');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 4),
              Text(
                [l.isTenant ? (l.ready ? needLine(l) : 'Size not known yet') : homeLine(l), if (l.phone.isNotEmpty) phoneText(l.phone)].join(' · '),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              _CallButtons(phone: l.phone),
            ],
          ),
        ),
        if (!inApp) l.isTenant ? _TenantStatus(store: store, lead: l) : _HomeStateControl(store: store, lead: l),
      ],
    );
  }
}

class _TenantStatus extends StatelessWidget {
  const _TenantStatus({required this.store, required this.lead});
  final DeskStore store;
  final Lead lead;

  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    value: tenantStatuses.contains(lead.status) ? lead.status : 'new',
    underline: const SizedBox.shrink(),
    borderRadius: BorderRadius.circular(12),
    items: [for (final s in tenantStatuses) DropdownMenuItem(value: s, child: Text(cap(s)))],
    onChanged: (s) => s == null ? null : store.setStatus(lead, s),
  );
}

class _HomeStateControl extends StatelessWidget {
  const _HomeStateControl({required this.store, required this.lead});
  final DeskStore store;
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: HomeState.active, label: Text('Active')),
        ButtonSegment(value: HomeState.inactive, label: Text('Not active')),
        ButtonSegment(value: HomeState.cancelled, label: Text('Cancelled')),
      ],
      selected: {lead.status.isEmpty ? HomeState.active : lead.status},
      onSelectionChanged: (s) async {
        final to = s.first;
        if (to == HomeState.active) return store.setStatus(lead, to, off: {'reason': 'Back on the market'});
        final ask = to == HomeState.inactive ? _notActiveSurvey(context) : _cancelReason(context);
        final off = await ask;
        if (off != null) store.setStatus(lead, to, off: off);
      },
    );
  }
}

/// Three short questions before a home goes Not active.
Future<Map<String, dynamic>?> _notActiveSurvey(BuildContext context) {
  const reasons = ['Rented through us', 'Rented by someone else', 'Owner paused it', 'Owner not reachable', 'Other'];
  String? reason;
  DateTime? freeFrom;
  var unknown = false;
  final note = TextEditingController();
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Mark not active'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Why is it not available?', style: TextStyle(fontWeight: FontWeight.w600)),
              RadioGroup<String>(
                groupValue: reason,
                onChanged: (v) => set(() => reason = v),
                child: Column(children: [for (final r in reasons) RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: r, title: Text(r))]),
              ),
              const SizedBox(height: 8),
              const Text('2. When might it be free again?', style: TextStyle(fontWeight: FontWeight.w600)),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: c,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 1100)),
                        initialDate: DateTime.now().add(const Duration(days: 300)),
                      );
                      if (d != null) set(() => (freeFrom, unknown) = (d, false));
                    },
                    child: Text(freeFrom == null ? 'Pick a date' : '${freeFrom!.day}/${freeFrom!.month}/${freeFrom!.year}'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text("Don't know"), selected: unknown, onSelected: (v) => set(() => (unknown, freeFrom) = (v, null))),
                ],
              ),
              const SizedBox(height: 8),
              const Text('3. Anything to remember? (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              TextField(controller: note, maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: reason == null
                ? null
                : () => Navigator.pop(c, {
                    'reason': reason,
                    // Don't know: check again in 10 months (same as the app's reminder).
                    'freeFrom': (freeFrom ?? DateTime.now().add(const Duration(days: 300))).toIso8601String().substring(0, 10),
                    'freeFromKnown': freeFrom != null,
                    'note': note.text.trim(),
                  }),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> _cancelReason(BuildContext context) {
  const reasons = ['Owner sold it', 'Owner does not want to rent', 'Wrong or fake post', 'Duplicate of another home', 'Other'];
  String? reason;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Cancel permanently'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('It leaves every list and is never matched again. The record is kept.'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: reason,
                onChanged: (v) => set(() => reason = v),
                child: Column(children: [for (final r in reasons) RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: r, title: Text(r))]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Back')),
          FilledButton(onPressed: reason == null ? null : () => Navigator.pop(c, {'reason': reason}), child: const Text('Cancel permanently')),
        ],
      ),
    ),
  );
}

class _Fields extends StatelessWidget {
  const _Fields({required this.store, required this.lead});
  final DeskStore store;
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<LeadField>>{};
    for (final f in fieldsFor(lead.kind)) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }
    final readOnly = lead.id.startsWith('tk2:');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead.isHome && lead.status != HomeState.active && lead.off != null)
          _Banner.warn('${lead.status == HomeState.cancelled ? 'Cancelled' : 'Not active'}: ${lead.off!['reason'] ?? ''}${(lead.off!['note'] ?? '').toString().isEmpty ? '' : ' · ${lead.off!['note']}'}${lead.off!['freeFrom'] == null ? '' : ' · check again ${lead.off!['freeFrom']}'}'),
        for (final g in groups.entries)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(g.key, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
                const SizedBox(height: 4),
                for (final f in g.value) _FieldRow(store: store, lead: lead, field: f, readOnly: readOnly),
              ],
            ),
          ),
      ],
    );
  }
}

/// One detail: click the value to change it; it saves when you press Enter or
/// click away. Preferences have a "Must have" switch.
class _FieldRow extends StatefulWidget {
  const _FieldRow({required this.store, required this.lead, required this.field, required this.readOnly});
  final DeskStore store;
  final Lead lead;
  final LeadField field;
  final bool readOnly;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool editing = false;
  late final ctrl = TextEditingController();
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus && editing) _commit();
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  Lead get l => widget.lead;
  LeadField get f => widget.field;

  String show() {
    final v = l.f[f.key];
    if (!l.has(f.key) && v != false) return '';
    return switch (f.type) {
      FieldType.money => rupees(toNum(v)),
      FieldType.bhk => bhkText(toNum(v)),
      FieldType.yesNo => l.yes(f.key) ? 'Yes' : 'No',
      FieldType.list => listOf(v).map(cap).join(', '),
      FieldType.phone => phoneText(v.toString()),
      FieldType.choice => cap(v.toString()),
      _ => v.toString(),
    };
  }

  void _commit() {
    final s = ctrl.text.trim();
    Object? value = s;
    if (s.isNotEmpty) {
      switch (f.type) {
        case FieldType.money:
          final n = toNum(s);
          value = n > 0 && n < 1000 ? n * 1000 : n;
        case FieldType.number || FieldType.bhk:
          value = toNum(s);
        case FieldType.list:
          value = listOf(s);
        default:
          value = s;
      }
    }
    widget.store.edit(l, f.key, value);
    setState(() => editing = false);
  }

  Future<void> _pick() async {
    if (widget.readOnly) return;
    if (f.type == FieldType.choice) {
      final box = context.findRenderObject() as RenderBox;
      final pos = box.localToGlobal(Offset(box.size.width - 220, box.size.height));
      final v = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 220, pos.dy),
        items: [
          for (final c in f.choices) PopupMenuItem(value: c, child: Text(cap(c))),
          const PopupMenuItem(value: '', child: Text('Not known', style: TextStyle(color: AppColors.muted))),
        ],
      );
      if (v != null) widget.store.edit(l, f.key, v);
      return;
    }
    if (f.type == FieldType.yesNo) {
      final cur = l.has(f.key) ? l.yes(f.key) : null;
      widget.store.edit(l, f.key, cur == null ? true : (cur ? false : null));
      return;
    }
    if (f.type == FieldType.date) {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 400)),
        lastDate: now.add(const Duration(days: 800)),
        initialDate: DateTime.tryParse(l.str(f.key)) ?? now,
      );
      if (d != null) widget.store.edit(l, f.key, d.toIso8601String().substring(0, 10));
      return;
    }
    final v = l.f[f.key];
    ctrl.text = v == null
        ? ''
        : switch (f.type) {
            FieldType.list => listOf(v).join(', '),
            FieldType.money || FieldType.number || FieldType.bhk => toNum(v) == 0 ? '' : (toNum(v) % 1 == 0 ? toNum(v).toInt().toString() : toNum(v).toString()),
            _ => v.toString(),
          };
    setState(() => editing = true);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final value = show();
    final must = l.must.contains(f.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: f.type == FieldType.longText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(width: 132, child: Text(f.label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(
            child: editing
                ? TextField(
                    controller: ctrl,
                    focusNode: focus,
                    maxLines: f.type == FieldType.longText ? 4 : 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      hintText: f.type == FieldType.list ? 'Comma between areas' : (f.type == FieldType.money ? 'e.g. 45000 or 45k' : null),
                    ),
                    onSubmitted: (_) => _commit(),
                  )
                : InkWell(
                    onTap: _pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      child: Text(
                        value.isEmpty ? (widget.readOnly ? '–' : 'Add') : value,
                        style: TextStyle(fontSize: 14, color: value.isEmpty ? AppColors.primary : AppColors.heading, fontWeight: value.isEmpty ? FontWeight.w500 : FontWeight.w400),
                      ),
                    ),
                  ),
          ),
          if (f.pref && !widget.readOnly)
            Tooltip(
              message: must ? 'Must have: homes that do not fit are left out' : 'Mark as must have',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => widget.store.toggleMust(l, f.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: must ? AppColors.heading : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: must ? AppColors.heading : AppColors.border),
                  ),
                  child: Text('Must', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: must ? Colors.white : AppColors.muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Notes extends StatefulWidget {
  const _Notes({required this.store, required this.lead});
  final DeskStore store;
  final Lead lead;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _add() {
    widget.store.addNote(widget.lead, ctrl.text);
    ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lead.id.startsWith('tk2:')) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Call notes', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'What did they say?',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add),
            ),
            onSubmitted: (_) => _add(),
          ),
          for (final n in widget.lead.notes.reversed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${_when(n['t'] as int)} · ${n['text']}', style: const TextStyle(fontSize: 13, color: AppColors.body)),
            ),
        ],
      ),
    );
  }
}

class _Origin extends StatelessWidget {
  const _Origin({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final s = lead.source;
    if (s.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Where it came from', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
          const SizedBox(height: 6),
          Text(
            [s['type'], s['group'], if ((s['by'] ?? '').toString().isNotEmpty) 'file by ${s['by']}', 'added ${_when(lead.at)}'].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if ((s['text'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(s['text'].toString(), style: const TextStyle(fontSize: 13, color: AppColors.body)),
          ],
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    if (lead.history.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        title: Text('Changes (${lead.history.length})', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading, fontSize: 14)),
        children: [
          for (final h in lead.history.reversed)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_when(h['t'] as int)} · ${fieldFor(lead.kind, h['k'].toString())?.label ?? h['k']}: ${h['o'] ?? '–'} → ${h['n'] ?? '–'}${h['by'] == null ? '' : ' (${h['by']})'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _when(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

class DeskImport extends StatefulWidget {
  const DeskImport({required this.store, super.key});
  final DeskStore store;

  @override
  State<DeskImport> createState() => _DeskImportState();
}

class _DeskImportState extends State<DeskImport> {
  static const makers = ['Claude', 'ChatGPT', 'Gemini', 'A person', 'Other'];
  String by = 'Claude';
  String file = '';
  final paste = TextEditingController();
  List<Lead> rows = [];
  List<String> rejected = [];
  final Set<int> off = {};

  @override
  void dispose() {
    paste.dispose();
    super.dispose();
  }

  void _read(String text, String name) {
    final p = widget.store.parse(text, by);
    setState(() {
      file = name;
      rows = p.leads;
      rejected = p.rejected;
      off.clear();
    });
  }

  Future<void> _pickFile() async {
    final f = await _pickText(['json', 'csv', 'txt']);
    if (f != null) _read(f.$2, f.$1);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final chosen = [
      for (var i = 0; i < rows.length; i++)
        if (!off.contains(i)) rows[i],
    ];
    final newOnes = rows.where((l) => store.existing(l) == null).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        const _H1('Import leads'),
        const Text(
          'A lead file from our group reading or from another AI tool (TK Lead Format, or a CSV with the sheet\'s column names). Nothing is added until you press Import, and nothing you typed is ever overwritten: a lead that is already here only gets its empty details filled.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Who made this file?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: by,
                    items: [for (final m in makers) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => by = v ?? by),
                  ),
                  const Spacer(),
                  FilledButton.icon(icon: const Icon(Icons.folder_open, size: 18), label: const Text('Choose a file'), onPressed: _pickFile),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: paste, maxLines: 4, decoration: const InputDecoration(hintText: 'Or paste the file\'s text here')),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(onPressed: () => _read(paste.text, 'pasted text'), child: const Text('Read pasted text')),
              ),
            ],
          ),
        ),
        if (rows.isNotEmpty || rejected.isNotEmpty) ...[
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$file: ${rows.where((l) => l.isTenant).length} tenants, ${rows.where((l) => l.isHome).length} homes · $newOnes new · ${rows.length - newOnes} already here · ${rows.where((l) => !l.ready).length} need a call · ${rejected.length} rejected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final r in rejected.take(10)) Text(r, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                const SizedBox(height: 8),
                for (var i = 0; i < rows.length; i++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: !off.contains(i),
                    onChanged: (v) => setState(() => v == true ? off.remove(i) : off.add(i)),
                    title: Text('${rows[i].isTenant ? 'Tenant' : 'Home'} · ${rows[i].title}${store.existing(rows[i]) == null ? '' : ' (already here)'}'),
                    subtitle: Text(rows[i].isTenant ? (rows[i].ready ? needLine(rows[i]) : 'Needs a call') : (rows[i].ready ? homeLine(rows[i]) : 'Needs a call')),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () {
                          final (a, f, s) = store.importLeads(chosen, by: by, file: file, rejected: rejected.length);
                          setState(() {
                            rows = [];
                            rejected = [];
                            paste.clear();
                          });
                          _toast(context, 'Imported: $a new, $f filled in, $s already complete.');
                        },
                  child: Text('Import ${chosen.length}'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Backup', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 4),
              const Text('Download everything typed on this desk (leads, notes, every change), or bring a downloaded file back.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(onPressed: () => _backup(context, store), child: const Text('Download everything')),
                  OutlinedButton(
                    onPressed: () async {
                      final f = await _pickText(['json']);
                      if (f == null) return;
                      try {
                        final n = store.restore(f.$2);
                        if (context.mounted) _toast(context, 'Restored. $n leads came back.');
                      } catch (e) {
                        if (context.mounted) _toast(context, 'That file could not be read.');
                      }
                    },
                    child: const Text('Restore from file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lets the person choose a text file; returns (name, text).
Future<(String, String)?> _pickText(List<String> exts) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: exts);
  if (file == null) return null;
  final bytes = <int>[];
  await for (final chunk in file.readAsByteStream()) {
    bytes.addAll(chunk);
  }
  return (file.name, utf8.decode(bytes, allowMalformed: true));
}

void _backup(BuildContext context, DeskStore store) {
  final d = DateTime.now();
  final name = 'trustkeyper-desk-backup-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
  final text = store.exportAll();
  if (downloadText(name, text)) {
    store.markBackedUp();
    _toast(context, 'Saved $name to your Downloads.');
  } else {
    Clipboard.setData(ClipboardData(text: text));
    store.markBackedUp();
    _toast(context, 'Copied the backup. Paste it somewhere safe.');
  }
}

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ---------------------------------------------------------------------------
// AI helpers
// ---------------------------------------------------------------------------

class DeskHelpers extends StatelessWidget {
  const DeskHelpers({required this.store, super.key});
  final DeskStore store;

  @override
  Widget build(BuildContext context) {
    final notices = store.helperNotices();
    final stats = store.sourceStats();
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        const _H1('AI helpers'),
        const Text(
          'Jobs we can hand to AI tools from other companies (ChatGPT, Gemini and others). Every job returns the same lead file, and nothing reaches the desk until someone imports it.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        for (final (what, job) in notices) _Banner.info('Now: $what Hand out $job.'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('When to add another AI tool', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 6),
              for (final t in helperTriggers) Padding(padding: const EdgeInsets.only(top: 4), child: Text('•  $t')),
            ],
          ),
        ),
        for (final j in helperJobs)
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Job ${j.no}: ${j.title}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading))),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy prompt'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: j.prompt));
                        _toast(context, 'Copied. Paste it into the AI tool with the material.');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('When: ${j.when}', style: const TextStyle(color: AppColors.body)),
                Text('Give it: ${j.give}', style: const TextStyle(color: AppColors.body)),
                const Text('Then: save its answer as a .json file and import it here.', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Which helper is worth it', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 8),
              if (stats.isEmpty) const Text('No imports yet.', style: TextStyle(color: AppColors.muted)),
              if (stats.isNotEmpty)
                Table(
                  columnWidths: const {0: FlexColumnWidth(2)},
                  children: [
                    for (final r in [
                      ['Made by', 'Files', 'New leads', 'Already here', 'Rejected', 'Ready to match'],
                      for (final e in stats.entries) [e.key, '${e.value['files']}', '${e.value['added']}', '${e.value['duplicates']}', '${e.value['rejected']}', '${e.value['ready']}'],
                    ])
                      TableRow(children: [for (final c in r) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(c))]),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

class _SaveState extends StatelessWidget {
  const _SaveState({required this.store});
  final DeskStore store;

  @override
  Widget build(BuildContext context) {
    final last = store.lastBackup == 0 ? 'never' : _when(store.lastBackup);
    final synced = store.lastSync == null ? '' : ' · synced ${_when(store.lastSync!.millisecondsSinceEpoch)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: store.cloud ? AppColors.successSoft : AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(store.cloud ? 'Saved to the cloud' : 'Saved on this laptop only', style: TextStyle(fontWeight: FontWeight.w600, color: store.cloud ? AppColors.success : AppColors.warning)),
          const SizedBox(height: 2),
          Text('Backup file: $last$synced', style: const TextStyle(fontSize: 12, color: AppColors.body)),
          Wrap(
            children: [
              TextButton(style: TextButton.styleFrom(padding: EdgeInsets.zero), onPressed: () => _backup(context, store), child: const Text('Download backup')),
              if (store.teamCloud) TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 10)), onPressed: store.refresh, child: const Text('Refresh')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Connects this laptop to the team storage (one team password).
class _ConnectCloud extends StatefulWidget {
  const _ConnectCloud({required this.store});
  final DeskStore store;

  @override
  State<_ConnectCloud> createState() => _ConnectCloudState();
}

class _ConnectCloudState extends State<_ConnectCloud> {
  final pass = TextEditingController();
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      busy = true;
      error = '';
    });
    final ok = await widget.store.connect(pass.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = ok ? '' : widget.store.cloudError;
    });
    if (ok) _toast(context, 'Connected. Everything you type is now saved to the cloud.');
  }

  @override
  Widget build(BuildContext context) => _Card(
    color: AppColors.warningSoft,
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Saved on this laptop only. Type the team password once: everything is then saved to the team\'s cloud, and the team\'s leads come in.',
            style: TextStyle(color: AppColors.warning),
          ),
        ),
        SizedBox(
          width: 200,
          child: TextField(
            controller: pass,
            obscureText: true,
            decoration: InputDecoration(isDense: true, hintText: 'Team password', errorText: error.isEmpty ? null : error, fillColor: Colors.white, filled: true),
            onSubmitted: (_) => _go(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: busy ? null : _go, child: Text(busy ? 'Connecting…' : 'Connect')),
      ],
    ),
  );
}

class _CallButtons extends StatelessWidget {
  const _CallButtons({required this.phone, this.compact = false});
  final String phone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return const SizedBox.shrink();
    final full = d.length == 10 ? '91$d' : d;
    final style = compact ? OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)) : null;
    return Wrap(
      spacing: 6,
      children: [
        OutlinedButton.icon(style: style, icon: const Icon(Icons.call_outlined, size: 16), label: const Text('Call'), onPressed: () => launchUrl(Uri.parse('tel:+$full'))),
        OutlinedButton.icon(
          style: style,
          icon: const Icon(Icons.chat_outlined, size: 16),
          label: const Text('WhatsApp'),
          onPressed: () => launchUrl(Uri.parse('https://wa.me/$full'), mode: LaunchMode.externalApplication),
        ),
      ],
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({required this.list, required this.detail});
  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 340,
        decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: AppColors.border))),
        child: list,
      ),
      Expanded(child: detail),
    ],
  );
}

class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.title,
    required this.filters,
    required this.filter,
    required this.onFilter,
    required this.onSearch,
    required this.addLabel,
    required this.onAdd,
    required this.children,
  });
  final String title;
  final List<String> filters;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onSearch;
  final String addLabel;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 14, 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.heading))),
            TextButton.icon(icon: const Icon(Icons.add, size: 18), label: Text(addLabel), onPressed: onAdd),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: 'Search name, number, area, society'),
          onChanged: onSearch,
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final f in filters)
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(f), selected: f == filter, onSelected: (_) => onFilter(f))),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
        child: Text('${children.length} shown', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ),
      Expanded(child: ListView(children: children)),
    ],
  );
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, required this.sub, required this.onTap, this.trailing = '', this.selected = false});
  final String title;
  final String sub;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primarySoft : Colors.white,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEFF2F6)))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading)),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
            if (trailing.isNotEmpty) _Badge(trailing),
          ],
        ),
      ),
    ),
  );
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({required this.store, required this.l, required this.onOpen, this.missing = false});
  final DeskStore store;
  final Lead l;
  final ValueChanged<Lead> onOpen;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final need = l.isTenant ? ['Size (BHK)', if (!l.has('budgetMax')) 'budget'] : [if (l.bhk <= 0) 'Size (BHK)', if (l.rent <= 0) 'rent'];
    return _Card(
      onTap: () => onOpen(l),
      child: Row(
        children: [
          Icon(l.isTenant ? Icons.person_outline : Icons.home_outlined, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading)),
                Text(
                  missing ? 'Ask: ${need.join(', ')}${(l.source['text'] ?? '').toString().isEmpty ? '' : ' · "${_short(l.source['text'].toString())}"'}' : (l.isTenant ? needLine(l) : homeLine(l)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          _CallButtons(phone: l.phone, compact: true),
          const SizedBox(width: 6),
          TextButton(onPressed: () => onOpen(l), child: const Text('Add details')),
        ],
      ),
    );
  }
}

String _short(String s) => s.length > 90 ? '${s.substring(0, 90)}…' : s;

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.empty, required this.children, this.hint = ''});
  final String title;
  final String hint;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading)),
            const SizedBox(width: 8),
            _Badge('${children.length}'),
          ],
        ),
        if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2, bottom: 6), child: Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
        const SizedBox(height: 6),
        if (children.isEmpty) Text(empty, style: const TextStyle(color: AppColors.muted)),
        ...children,
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap, this.color = Colors.white});
  final Widget child;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: child,
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner.warn(this.text) : warn = true, action = null;
  const _Banner.info(this.text, {this.action}) : warn = false;
  final String text;
  final bool warn;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: warn ? AppColors.warningSoft : AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Icon(warn ? Icons.info_outline : Icons.lightbulb_outline, size: 18, color: warn ? AppColors.warning : AppColors.primaryDark),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: warn ? AppColors.warning : AppColors.primaryDark))),
        if (action != null) TextButton(onPressed: action!.$2, child: Text(action!.$1)),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.body)),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.fg, this.bg, this.icon);
  final String text;
  final Color fg;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

class _H1 extends StatelessWidget {
  const _H1(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.heading)),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Text(text, style: const TextStyle(color: AppColors.muted)));
}
