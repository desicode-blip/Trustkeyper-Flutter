import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_deal.dart';
import 'tk2_deal_page.dart';
import 'tk2_status.dart';
import 'tk2_store.dart';
import 'tk2_visits.dart';
import 'tk2_widgets.dart';

// The broker's money: every payment in his visits and deals, worked out from
// the visits and deals (nothing extra is stored). Screen: the Payments tab.

/// One payment, as the broker sees it.
class Tk2Txn {
  const Tk2Txn({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.from,
    required this.house,
    required this.paid,
    required this.yours,
    required this.state,
    required this.note,
    required this.split,
    required this.steps,
    this.visitId,
    this.dealId,
  });

  final String id;

  /// visit · token · movein · owner · fee · repair
  final String kind;
  final int at;
  final String title, from, house, note;

  /// What the payer paid, and what of it is (or will be) the broker's.
  final int paid, yours;

  /// received · held · refunded · others (went to the owner or TrustKeyper)
  final String state;

  /// Where the money went: label and amount (negative = taken off).
  final List<(String, int)> split;

  /// What happened, in order: label and time (null = not yet).
  final List<(String, int?)> steps;
  final String? visitId, dealId;

  static const kinds = {
    'visit': 'Visit fee',
    'token': 'Token',
    'movein': 'Move-in payment',
    'owner': 'Owner payment',
    'fee': 'Agreement fee',
    'repair': 'Repair',
  };

  String get kindName => kinds[kind]!;

  /// The number shown on the row: the broker's part, or what was paid when none of it is his.
  int get shown => yours > 0 ? yours : paid;

  String get stateName => switch (state) {
    'received' => 'Received',
    'held' => yours > 0 ? 'On hold' : 'Held safe',
    'refunded' => 'Refunded',
    _ => kind == 'fee' || kind == 'visit' ? 'To TrustKeyper' : 'To the owner',
  };

  /// Short ID people can quote on a call.
  String get ref => 'TK-${id.hashCode.toUnsigned(32).toRadixString(36).toUpperCase().padLeft(6, '0')}';
}

/// Money totals for the top of the Payments tab.
typedef Tk2MoneyTotals = ({int received, int month, int coming});

/// Every payment, newest first.
List<Tk2Txn> tk2Ledger(Tk2Store store) {
  final out = <Tk2Txn>[];
  for (final v in store.visits) {
    if (v.fee > 0) out.add(_visit(store, v));
  }
  for (final d in store.deals) {
    out.addAll(_deal(d));
  }
  return out..sort((a, b) => b.at.compareTo(a.at));
}

/// Received in all, received this month, and still coming (visit fees on hold
/// and brokerage not paid yet in open deals).
Tk2MoneyTotals tk2MoneyTotals(Tk2Store store, List<Tk2Txn> all, DateTime now) {
  var received = 0, month = 0, coming = 0;
  for (final x in all) {
    if (x.state == 'received') {
      received += x.yours;
      final at = DateTime.fromMillisecondsSinceEpoch(x.at);
      if (at.year == now.year && at.month == now.month) month += x.yours;
    }
    if (x.state == 'held') coming += x.yours;
  }
  for (final d in store.deals.where((d) => d.ended == null)) {
    if (d.t['paid'] != true) coming += d.brokerage;
    if (d.o['brokPaid'] != true) coming += d.ownerBrokerage;
  }
  return (received: received, month: month, coming: coming);
}

String _house(Tk2Store store, String listingId) => store.listing(listingId)?.publicTitle ?? 'A property';

Tk2Txn _visit(Tk2Store store, Tk2Visit v) {
  final name = v.customerName.isEmpty ? 'The customer' : v.customerName;
  final paid = ('Paid by $name', v.fee);
  final ended = v.endedAt;
  final (state, note, split, last) = switch (v.status) {
    VisitStatus.done => ('received', 'Visit done. $name showed the code, so the fee is yours.', [paid, ('Yours', v.fee)], ('Paid to you', ended)),
    VisitStatus.noShow => (
      'received',
      '$name did not come. You get half the fee for your time.',
      [paid, ('Yours (half)', v.brokerShare), ('Kept by TrustKeyper', v.fee - v.brokerShare)],
      ('Half paid to you', ended),
    ),
    VisitStatus.cancelled => ('refunded', 'You cancelled the visit, so all of it went back to $name.', [paid, ('Back to $name', v.fee)], ('Refunded', ended)),
    VisitStatus.customerCancelled => (
      'refunded',
      '$name cancelled within 5 minutes of booking and got 98% back.',
      [paid, ('Back to $name', v.customerRefund), ('Kept by TrustKeyper (2%)', v.fee - v.customerRefund)],
      ('Refunded', ended),
    ),
    VisitStatus.customerCancelledLate => (
      'others',
      '$name cancelled more than 5 minutes after booking. No refund, and the fee is not passed on.',
      [paid, ('Kept by TrustKeyper', v.fee)],
      ('Closed', ended),
    ),
    _ => ('held', 'TrustKeyper holds it. It is yours when you enter $name\'s visit code.', [paid, ('Yours after the visit', v.fee)], ('Paid to you', null)),
  };
  return Tk2Txn(
    id: 'v:${v.id}',
    kind: 'visit',
    at: state == 'held' ? v.createdAt : ended,
    title: 'Visit fee · $name',
    from: name,
    house: _house(store, v.listingId),
    paid: v.fee,
    yours: v.brokerShare > 0 ? v.brokerShare : (state == 'held' ? v.fee : 0),
    state: state,
    note: note,
    split: split,
    steps: [
      ('$name paid', v.createdAt),
      if (state == 'received' || state == 'held')
        ('Visit', state == 'received' || v.at < DateTime.now().millisecondsSinceEpoch ? v.at : null),
      last,
    ],
    visitId: v.id,
  );
}

List<Tk2Txn> _deal(Tk2Deal d) {
  final tenant = d.nameOf(DealRole.tenant), owner = d.nameOf(DealRole.owner);
  final out = <Tk2Txn>[];
  Tk2Txn txn(
    String kind,
    int at,
    String title,
    String from,
    int paid,
    int yours,
    String state,
    String note,
    List<(String, int)> split,
    List<(String, int?)> steps, {
    String tail = '',
  }) => Tk2Txn(
    id: '$kind:${d.id}$tail',
    kind: kind,
    at: at,
    title: title,
    from: from,
    house: d.title,
    paid: paid,
    yours: yours,
    state: state,
    note: note,
    split: split,
    steps: steps,
    dealId: d.id,
  );

  final tokenAt = d.t['tokenAt'] as int? ?? d.createdAt;
  final endedAt = d.b['endedAt'] as int?;
  if (d.t['tokenPaid'] == true) {
    final split = d.ended == null ? null : Tk2Deal.tokenSplit(d.token, d.ended!);
    out.add(
      txn(
        'token',
        tokenAt,
        'Token · $tenant',
        tenant,
        d.token,
        split?.broker ?? 0,
        switch (d.ended) {
          'tenant' => 'received',
          'owner' => 'refunded',
          _ => 'held',
        },
        switch (d.ended) {
          'tenant' => '$tenant backed out before signing. The token is shared: half to $owner, half to you.',
          'owner' => '$owner backed out before signing, so all of it went back to $tenant.',
          _ => 'TrustKeyper keeps it safe. It is taken off $tenant\'s move-in payment.',
        },
        [
          ('Paid by $tenant', d.token),
          if (split == null) ('Taken off the move-in payment', d.token),
          if (split != null && split.tenant > 0) ('Back to $tenant', split.tenant),
          if (split != null && split.owner > 0) ('To $owner', split.owner),
          if (split != null && split.broker > 0) ('Yours', split.broker),
        ],
        [
          ('$tenant paid', tokenAt),
          (d.ended == null ? 'Used in the move-in payment' : 'The deal is off', d.ended == null ? d.t['paidAt'] as int? : endedAt ?? tokenAt),
        ],
      ),
    );
  }

  if (d.t['paid'] == true) {
    final at = d.t['paidAt'] as int? ?? tokenAt;
    out.add(
      txn(
        'movein',
        at,
        'Move-in payment · $tenant',
        tenant,
        d.moveInTotal,
        d.brokerage,
        d.brokerage > 0 ? 'received' : 'others',
        d.brokerage > 0 ? 'Your brokerage came with $tenant\'s move-in payment. The rest goes to $owner.' : '$tenant paid to move in. It goes to $owner.',
        [
          ('Security deposit · to $owner', d.deposit),
          ('First month rent · to $owner', d.rent),
          if (d.maintenance > 0) ('Maintenance · to $owner', d.maintenance),
          if (d.brokerage > 0) ('Brokerage · yours', d.brokerage),
          ('Agreement fee · half', Tk2Deal.feeShare),
          ('Token paid before', -d.token),
        ],
        [('$tenant paid', at), ('Keys handed over', d.handoverAt > 0 ? d.handoverAt : null)],
      ),
    );
  }

  final feeAt = d.o['feeAt'] as int?, ownerAt = d.o['paidAt'] as int?;
  final earlyFee = feeAt != null && feeAt != ownerAt;
  if (earlyFee) {
    out.add(
      txn(
        'fee',
        feeAt,
        'Agreement fee · $owner',
        owner,
        Tk2Deal.feeShare,
        0,
        'others',
        '$owner paid their half of the agreement fee early. It covers stamp paper, drafting and e-sign.',
        [('Paid by $owner', Tk2Deal.feeShare), ('To TrustKeyper', Tk2Deal.feeShare)],
        [('$owner paid', feeAt)],
      ),
    );
  }
  if (d.o['brokPaid'] == true && (d.ownerBrokerage > 0 || !earlyFee)) {
    final at = ownerAt ?? tokenAt;
    final fee = earlyFee ? 0 : Tk2Deal.feeShare;
    out.add(
      txn(
        'owner',
        at,
        'Owner payment · $owner',
        owner,
        d.ownerBrokerage + fee,
        d.ownerBrokerage,
        d.ownerBrokerage > 0 ? 'received' : 'others',
        d.ownerBrokerage > 0 ? '$owner paid your brokerage before the keys were handed over.' : '$owner paid their half of the agreement fee.',
        [if (d.ownerBrokerage > 0) ('Brokerage · yours', d.ownerBrokerage), if (fee > 0) ('Agreement fee · half', fee)],
        [('$owner paid', at)],
      ),
    );
  }

  for (final r in d.repairs.where((r) => r.paid)) {
    out.add(
      txn(
        'repair',
        r.paidAt,
        'Repair · ${r.text}',
        owner,
        r.amount,
        r.amount,
        'received',
        '$owner paid for the repair $tenant reported: ${r.text}.',
        [('Paid by $owner', r.amount), ('Yours · for the repair', r.amount)],
        [('$tenant reported it', r.at), ('Fixed', r.quote['done'] as int?), ('$owner paid', r.paidAt)],
        tail: ':${r.id}',
      ),
    );
  }
  return out;
}

String _signed(int v) => v < 0 ? '− ${Tk2Store.money(-v)}' : Tk2Store.money(v);

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${tk2DateOf(d)} · ${tk2Time(d)}';
}

(Color, Color, IconData) _look(Tk2Txn x) => switch (x.state) {
  'received' => (AppColors.successSoft, AppColors.success, Icons.south_west),
  'held' => (AppColors.warningSoft, AppColors.warning, Icons.lock_clock_outlined),
  'refunded' => (const Color(0xFFEEF1F5), AppColors.muted, Icons.undo),
  _ => (const Color(0xFFEEF1F5), AppColors.muted, Icons.north_east),
};

// --------------------------------------------------------------- screens

/// The Payments tab: big totals, then every payment grouped by month,
/// property or type.
class Tk2Payments extends StatefulWidget {
  const Tk2Payments({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2Payments> createState() => _Tk2PaymentsState();
}

class _Tk2PaymentsState extends State<Tk2Payments> {
  static const _shows = {'all': 'All', 'received': 'Received', 'held': 'On hold', 'refunded': 'Refunded'};
  static const _views = {'month': 'By month', 'house': 'By property', 'kind': 'By type'};
  String show = 'all', view = 'month';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final now = DateTime.now();
      final all = tk2Ledger(widget.store);
      final totals = tk2MoneyTotals(widget.store, all, now);
      final list = all.where((x) => show == 'all' || x.state == show).toList();
      final groups = <String, List<Tk2Txn>>{};
      for (final x in list) {
        final d = DateTime.fromMillisecondsSinceEpoch(x.at);
        final key = switch (view) {
          'house' => x.house,
          'kind' => x.kindName,
          _ => '${_monthNames[d.month - 1]} ${d.year}',
        };
        groups.putIfAbsent(key, () => []).add(x);
      }
      return SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const Tk2Title('Payments'),
            const SizedBox(height: 16),
            _Hero(totals: totals, now: now),
            const SizedBox(height: 22),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _shows.entries) ...[
                    Tk2Chip(label: e.value, on: show == e.key, onTap: () => setState(() => show = e.key)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('${list.length} ${list.length == 1 ? 'payment' : 'payments'}', style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickView,
                  icon: const Icon(Icons.view_agenda_outlined, size: 18),
                  label: Text(_views[view]!),
                  style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (list.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  all.isEmpty ? 'No payments yet. Visit fees, brokerage and repairs show here as they come in.' : 'Nothing here. Try "All".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
                ),
              ),
            for (final g in groups.entries) ...[
              const SizedBox(height: 14),
              _GroupHead(title: g.key, items: g.value),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < g.value.length; i++)
                      Tk2TxnRow(
                        txn: g.value[i],
                        last: i == g.value.length - 1,
                        showHouse: view != 'house',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Tk2TxnDetail(store: widget.store, txn: g.value[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Future<void> _pickView() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Group payments',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
            ),
            for (final e in _views.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(e.value),
                trailing: e.key == view ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(sheet, e.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => view = picked);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.totals, required this.now});
  final Tk2MoneyTotals totals;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You have earned',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF)),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Tk2Store.money(totals.received),
            style: const TextStyle(fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        Text('${Tk2Store.money(totals.month)} in ${_monthNames[now.month - 1]}', style: const TextStyle(fontSize: 14.5, color: Color(0xE6FFFFFF))),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Coming to you',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
              Text(
                Tk2Store.money(totals.coming),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A filter chip (also used by notifications).
class Tk2Chip extends StatelessWidget {
  const Tk2Chip({required this.label, required this.on, required this.onTap, super.key});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: on,
    button: true,
    child: Material(
      color: on ? AppColors.primarySoft : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 1.5 : 1),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (on) ...[const Icon(Icons.check, size: 16, color: AppColors.primaryDark), const SizedBox(width: 4)],
              Text(
                label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: on ? AppColors.primaryDark : AppColors.heading),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.title, required this.items});
  final String title;
  final List<Tk2Txn> items;

  @override
  Widget build(BuildContext context) {
    final got = items.where((x) => x.state == 'received').fold(0, (s, x) => s + x.yours);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
            ),
          ),
          if (got > 0)
            Text(
              '+${Tk2Store.money(got)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.success),
            ),
        ],
      ),
    );
  }
}

/// One payment in a list.
class Tk2TxnRow extends StatelessWidget {
  const Tk2TxnRow({required this.txn, required this.onTap, this.last = false, this.showHouse = true, super.key});
  final Tk2Txn txn;
  final VoidCallback onTap;
  final bool last, showHouse;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _look(txn);
    final d = DateTime.fromMillisecondsSinceEpoch(txn.at);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 22, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [tk2Day(d), if (showHouse) txn.house].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${txn.state == 'received' ? '+' : ''}${Tk2Store.money(txn.shown)}',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: txn.state == 'received' ? AppColors.success : (txn.state == 'held' ? AppColors.warning : AppColors.muted),
                    decoration: txn.state == 'refunded' ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(txn.stateName, style: TextStyle(fontSize: 13, color: fg)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything about one payment: how much, what for, where it went, when.
class Tk2TxnDetail extends StatelessWidget {
  const Tk2TxnDetail({required this.store, required this.txn, super.key});
  final Tk2Store store;
  final Tk2Txn txn;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _look(txn);
    final x = txn;
    final paidLine = x.split.first;
    final byPayer = paidLine.$1.startsWith('Paid by');
    final rest = x.split.skip(byPayer ? 1 : 0).toList();
    return OnbPage(
      title: x.kindName,
      subtitle: x.house,
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: fg),
              ),
              const SizedBox(height: 12),
              Text(
                '${x.state == 'received' ? '+' : ''}${Tk2Store.money(x.shown)}',
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: x.state == 'received' ? AppColors.success : AppColors.heading),
              ),
              const SizedBox(height: 6),
              Tk2Pill(
                x.stateName,
                kind: switch (x.state) {
                  'received' => 'ok',
                  'held' => 'wait',
                  _ => 'mute',
                },
              ),
              const SizedBox(height: 8),
              Text(_when(x.at), style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OnbBanner(x.note, kind: x.state == 'held' ? 'wait' : (x.state == 'received' ? 'ok' : 'mute'), icon: Icons.info_outline),
        const SizedBox(height: 18),
        _heading('Where the money went'),
        OnbCard(
          child: Column(
            children: [
              if (byPayer) _SplitRow(paidLine.$1, Tk2Store.money(paidLine.$2), strong: true, last: rest.isEmpty),
              for (var i = 0; i < rest.length; i++)
                _SplitRow(rest[i].$1, _signed(rest[i].$2), mine: rest[i].$1.toLowerCase().contains('yours'), last: byPayer && i == rest.length - 1),
              if (!byPayer) _SplitRow('Total paid', Tk2Store.money(x.paid), strong: true, last: true),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _heading('What happened'),
        OnbCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            children: [
              for (final s in x.steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        s.$2 == null ? Icons.radio_button_unchecked : Icons.check_circle,
                        size: 20,
                        color: s.$2 == null ? AppColors.border : AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.$1, style: const TextStyle(fontSize: 15.5, color: AppColors.heading)),
                      ),
                      Text(s.$2 == null ? 'Not yet' : _when(s.$2!), style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _heading('Details'),
        OnbCard(
          child: Column(
            children: [
              OnbKeyValue('Type', x.kindName),
              OnbKeyValue('Property', x.house),
              OnbKeyValue('From', x.from),
              OnbKeyValue('Date', _when(x.at)),
              OnbKeyValue('Reference', x.ref, last: true),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const OnbBanner('Test payment. No real money moves until online payments are switched on.', kind: 'mute', icon: Icons.science_outlined),
        if (x.visitId != null || x.dealId != null) ...[
          const SizedBox(height: 14),
          OnbRow(
            icon: x.visitId != null ? Icons.event_available_outlined : Icons.home_outlined,
            title: x.visitId != null ? 'Open the visit' : 'Open the move-in',
            onTap: () => _open(context),
          ),
        ],
      ],
    );
  }

  void _open(BuildContext context) {
    if (txn.dealId != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Tk2DealPage(store: store, dealId: txn.dealId!, role: DealRole.broker),
        ),
      );
      return;
    }
    final v = store.visits.where((v) => v.id == txn.visitId).firstOrNull;
    if (v != null) showTk2Visit(context, store, v);
  }

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
  );
}

/// One line of "Where the money went"; the broker's own share stands out.
class _SplitRow extends StatelessWidget {
  const _SplitRow(this.label, this.value, {this.mine = false, this.strong = false, this.last = false});
  final String label, value;
  final bool mine, strong, last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              height: 21 / 15.5,
              color: mine ? AppColors.success : (strong ? AppColors.heading : AppColors.muted),
              fontWeight: mine || strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: strong || mine ? FontWeight.w700 : FontWeight.w500, color: mine ? AppColors.success : AppColors.heading),
        ),
      ],
    ),
  );
}
