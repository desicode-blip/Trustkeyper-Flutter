import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_deal.dart';
import 'tk2_deal_page.dart';
import 'tk2_money.dart';
import 'tk2_status.dart';
import 'tk2_store.dart';
import 'tk2_visits.dart';
import 'tk2_widgets.dart';

// The broker's notifications. Each one is worked out from the visits, deals
// and properties (nothing extra is stored but what was read and what is
// turned off), so a change on any phone or on the web shows up here.

/// One notification.
class Tk2Note {
  const Tk2Note({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
    required this.icon,
    this.tone = 'info',
    this.visitId,
    this.dealId,
    this.txnId,
    this.listingId,
  });

  final String id;

  /// visits · money · deals · houses
  final String kind;
  final int at;
  final String title, body;
  final IconData icon;

  /// ok · info · wait · need · mute
  final String tone;

  /// What opens on tap.
  final String? visitId, dealId, txnId, listingId;

  static const kinds = {'visits': 'Visits', 'money': 'Payments', 'deals': 'Moving in', 'houses': 'Properties'};
}

/// Every notification up to [now], newest first.
List<Tk2Note> tk2Notes(Tk2Store store, DateTime now) {
  final out = <Tk2Note>[];
  final ms = now.millisecondsSinceEpoch;
  String house(String id) => store.listing(id)?.publicTitle ?? 'A property';
  String when(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    return '${tk2Day(d, now: now)}, ${tk2Time(d)}';
  }

  // ---- visits
  for (final v in store.visits) {
    final name = v.customerName.isEmpty ? 'A customer' : v.customerName;
    final where = house(v.listingId);
    final money = Tk2Store.money(v.fee);
    out.add(
      Tk2Note(
        id: 'vb:${v.id}',
        kind: 'visits',
        at: v.createdAt,
        title: 'Visit booked',
        body: '$name · $where · ${when(v.at)}. ${v.fee > 0 ? '$money held for you.' : 'Free visit.'}',
        icon: Icons.event_available_outlined,
        tone: 'ok',
        visitId: v.id,
      ),
    );
    if (v.upcoming) {
      final soon = v.at - const Duration(hours: 2).inMilliseconds;
      if (ms >= soon && ms < v.at) {
        out.add(
          Tk2Note(
            id: 'vs:${v.id}',
            kind: 'visits',
            at: soon,
            title: 'Visit in 2 hours',
            body: '$name at ${tk2Time(DateTime.fromMillisecondsSinceEpoch(v.at))} · $where. Ask for the 4-digit code at the house.',
            icon: Icons.schedule,
            tone: 'wait',
            visitId: v.id,
          ),
        );
      }
      final late = v.at + const Duration(hours: 1).inMilliseconds;
      if (ms >= late) {
        out.add(
          Tk2Note(
            id: 'vc:${v.id}',
            kind: 'visits',
            at: late,
            title: 'Enter the visit code',
            body: v.fee > 0
                ? 'Ask $name for the code to get your $money. It works for 24 hours after the visit.'
                : 'Ask $name for the code to close the visit. It works for 24 hours after the visit.',
            icon: Icons.pin_outlined,
            tone: 'need',
            visitId: v.id,
          ),
        );
      }
      continue;
    }
    final (kind, title, body, icon, tone) = switch (v.status) {
      VisitStatus.done when v.fee > 0 => ('money', '$money is yours', 'Visit with $name done · $where.', Icons.account_balance_wallet_outlined, 'ok'),
      VisitStatus.done => ('visits', 'Visit done', '$name visited $where.', Icons.check, 'ok'),
      VisitStatus.noShow => (
        'visits',
        'Customer did not come',
        '$name · $where.${v.fee > 0 ? ' Half the fee, ${Tk2Store.money(v.brokerShare)}, is yours.' : ''}',
        Icons.person_off_outlined,
        'mute',
      ),
      VisitStatus.cancelled => (
        'visits',
        'Visit cancelled',
        'You cancelled $name\'s visit · $where.${v.fee > 0 ? ' $money goes back to them.' : ''}',
        Icons.close,
        'mute',
      ),
      VisitStatus.customerCancelled => (
        'visits',
        'Visit cancelled',
        '$name cancelled · $where.${v.fee > 0 ? ' ${Tk2Store.money(v.customerRefund)} went back to them.' : ''}',
        Icons.close,
        'mute',
      ),
      _ => ('visits', 'Visit cancelled', '$name cancelled late · $where. No refund for them.', Icons.close, 'mute'),
    };
    out.add(
      Tk2Note(
        id: 've:${v.id}',
        kind: kind,
        at: v.endedAt,
        title: title,
        body: body,
        icon: icon,
        tone: tone,
        visitId: v.id,
        txnId: v.fee > 0 ? 'v:${v.id}' : null,
      ),
    );
  }

  // ---- properties
  for (final l in store.listings) {
    if (store.sync?.addedByOwner(l.id) ?? false) {
      out.add(
        Tk2Note(
          id: 'ho:${l.id}',
          kind: 'houses',
          at: l.createdAt,
          title: 'Owner added a house',
          body: '${l.ownerName.isEmpty ? 'The owner' : l.ownerName} filled in ${l.publicTitle} from your link. Check it and share it.',
          icon: Icons.add_home_outlined,
          tone: 'ok',
          listingId: l.id,
        ),
      );
    }
    final off = store.inactive(l.id);
    if (off != null && off.due(now) && off.reason != Tk2Inactive.blocked) {
      out.add(
        Tk2Note(
          id: 'hr:${l.id}:${off.remindAt}',
          kind: 'houses',
          at: off.remindAt,
          title: 'This property might be available',
          body:
              '${l.publicTitle} · ${off.reason.toLowerCase()} since ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(off.rentStart ?? off.since))}. Check with the owner.',
          icon: Icons.refresh,
          tone: 'wait',
          listingId: l.id,
        ),
      );
    }
  }

  // ---- moving in
  for (final d in store.deals) {
    final tenant = d.nameOf(DealRole.tenant), owner = d.nameOf(DealRole.owner);
    Tk2Note note(String id, String kind, int at, String title, String body, IconData icon, {String tone = 'info', String? txn}) =>
        Tk2Note(id: '$id:${d.id}', kind: kind, at: at, title: title, body: body, icon: icon, tone: tone, dealId: d.id, txnId: txn);

    final tokenAt = d.t['tokenAt'] as int?;
    if (tokenAt != null) {
      out.add(
        note(
          'dt',
          'deals',
          tokenAt,
          'House blocked',
          '$tenant paid ${Tk2Store.money(d.token)} token for ${d.title}. It is off the market now.',
          Icons.lock_outline,
          tone: 'ok',
        ),
      );
    } else {
      out.add(note('ds', 'deals', d.createdAt, 'Token asked', '$tenant wants ${d.title}. They pay the token from your link.', Icons.home_outlined));
    }
    if (d.signedAt > 0) {
      out.add(
        note('dg', 'deals', d.signedAt, 'Agreement signed', '$tenant and $owner signed for ${d.title}. Tell the society now.', Icons.draw_outlined, tone: 'ok'),
      );
    }
    final movein = d.t['paidAt'] as int?;
    if (movein != null) {
      out.add(
        note(
          'dm',
          'money',
          movein,
          d.brokerage > 0 ? '${Tk2Store.money(d.brokerage)} brokerage received' : 'Move-in payment done',
          '$tenant paid ${Tk2Store.money(d.moveInTotal)} to move in · ${d.title}.',
          Icons.account_balance_wallet_outlined,
          tone: 'ok',
          txn: 'movein:${d.id}',
        ),
      );
    }
    final feeAt = d.o['feeAt'] as int?, ownerAt = d.o['paidAt'] as int?;
    if (feeAt != null && feeAt != ownerAt) {
      out.add(
        note(
          'df',
          'money',
          feeAt,
          'Agreement fee paid',
          '$owner paid their ${Tk2Store.money(Tk2Deal.feeShare)} · ${d.title}.',
          Icons.receipt_long_outlined,
          tone: 'ok',
          txn: 'fee:${d.id}',
        ),
      );
    }
    if (ownerAt != null && d.o['brokPaid'] == true) {
      out.add(
        note(
          'do',
          'money',
          ownerAt,
          d.ownerBrokerage > 0 ? '${Tk2Store.money(d.ownerBrokerage)} brokerage received' : 'Owner paid',
          '$owner paid before the keys · ${d.title}.',
          Icons.account_balance_wallet_outlined,
          tone: 'ok',
          txn: 'owner:${d.id}',
        ),
      );
    }
    if (d.handoverAt > 0) {
      out.add(note('dh', 'deals', d.handoverAt, 'Keys handed over', '${d.title} · $tenant now checks the house and keys.', Icons.key_outlined, tone: 'ok'));
    }
    final keysAt = d.t['keysAt'] as int?;
    if (keysAt != null && d.handedOver) {
      out.add(
        note(
          'dk',
          'deals',
          keysAt,
          'Tenant checked the house',
          '$tenant ticked every item and the keys · ${d.title}. ${Tk2Deal.repairDays} days to report repairs start now.',
          Icons.fact_check_outlined,
          tone: 'ok',
        ),
      );
    }
    for (final r in d.repairs) {
      out.add(note('dr${r.id}', 'deals', r.at, 'Repair reported', '$tenant: ${r.text} · ${d.title}.', Icons.build_outlined, tone: 'wait'));
      if (r.paid) {
        out.add(
          note(
            'dp${r.id}',
            'money',
            r.paidAt,
            '${Tk2Store.money(r.amount)} for a repair',
            '$owner paid for: ${r.text}.',
            Icons.account_balance_wallet_outlined,
            tone: 'ok',
            txn: 'repair:${d.id}:${r.id}',
          ),
        );
      }
    }
    final ended = d.b['endedAt'] as int?;
    if (d.ended != null) {
      out.add(
        note(
          'de',
          'deals',
          ended ?? d.lastAt,
          'The deal is off',
          '${d.ended == 'owner' ? owner : tenant} backed out · ${d.title} is back on the market.',
          Icons.do_not_disturb_on_outlined,
          tone: 'mute',
        ),
      );
    }
    if (d.ended == null && d.stage(now) == DealStage.living) {
      out.add(note('dl', 'deals', d.lastAt, 'Moved in', '$tenant has moved into ${d.title}. Everything is done.', Icons.celebration_outlined, tone: 'ok'));
    }
    // The broker's own steps, while they wait for him.
    final last = d.lastAt;
    for (final x in d.tasks(DealRole.broker, now).where((x) => !Tk2Deal.optional.contains(x.key))) {
      out.add(note('dy:${x.key}:$last', 'deals', last, 'Your turn: ${x.label}', '${d.title} · $tenant', Icons.arrow_forward, tone: 'need'));
    }
  }
  return out.where((n) => n.at > 0 && n.at <= ms).toList()..sort((a, b) => b.at.compareTo(a.at));
}

bool tk2NoteUnread(Tk2Store store, Tk2Note n) => n.at > store.notesReadBefore && !store.notesRead.contains(n.id);

/// For the bell: unread, not turned off.
int tk2UnreadNotes(Tk2Store store, DateTime now) => tk2Notes(store, now).where((n) => !store.notesMuted.contains(n.kind) && tk2NoteUnread(store, n)).length;

(Color, Color) _tone(String tone) => switch (tone) {
  'ok' => (AppColors.successSoft, AppColors.success),
  'wait' => (AppColors.warningSoft, AppColors.warning),
  'need' => (AppColors.errorSoft, AppColors.error),
  'mute' => (const Color(0xFFEEF1F5), AppColors.muted),
  _ => (AppColors.primarySoft, AppColors.primaryDark),
};

String _ago(int at, DateTime now) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  final gap = now.difference(d);
  if (gap.inMinutes < 1) return 'Now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '${gap.inHours} h';
  return tk2Day(d, now: now);
}

// --------------------------------------------------------------- screens

/// The bell: every notification, by kind, today and earlier.
class Tk2Notifications extends StatefulWidget {
  const Tk2Notifications({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2Notifications> createState() => _Tk2NotificationsState();
}

class _Tk2NotificationsState extends State<Tk2Notifications> {
  String show = 'all';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final now = DateTime.now();
      final all = tk2Notes(store, now);
      final list = all.where((n) => show == 'all' || n.kind == show).toList();
      final unread = list.where((n) => tk2NoteUnread(store, n)).length;
      bool today(Tk2Note n) {
        final d = DateTime.fromMillisecondsSinceEpoch(n.at);
        return d.year == now.year && d.month == now.month && d.day == now.day;
      }

      final groups = {'Today': list.where(today).toList(), 'Earlier': list.where((n) => !today(n)).toList()};
      return Scaffold(
        backgroundColor: AppColors.surfaceMuted,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceMuted,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_ios_new), onPressed: () => Navigator.of(context).maybePop()),
          title: const Text(
            'Notifications',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.heading),
          ),
          actions: [
            IconButton(
              tooltip: 'Notification settings',
              icon: const Icon(Icons.settings_outlined, color: AppColors.heading),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Tk2NoteSettings(store: store))),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in {'all': 'All', ...Tk2Note.kinds}.entries) ...[
                    Tk2Chip(label: e.value, on: show == e.key, onTap: () => setState(() => show = e.key)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  unread == 0 ? 'All read' : '$unread unread',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.muted),
                ),
                const Spacer(),
                if (unread > 0)
                  TextButton(
                    onPressed: () => store.readAllNotes(),
                    child: const Text('Mark all as read', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            if (list.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: const Column(
                  children: [
                    Icon(Icons.notifications_none, size: 40, color: AppColors.primaryDark),
                    SizedBox(height: 10),
                    Text(
                      'Nothing yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Bookings, payments and move-in steps show here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            for (final g in groups.entries)
              if (g.value.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                  child: Text(
                    g.key,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.muted),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.heading.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < g.value.length; i++)
                        _NoteRow(
                          note: g.value[i],
                          unread: tk2NoteUnread(store, g.value[i]),
                          last: i == g.value.length - 1,
                          now: now,
                          onTap: () => _open(g.value[i]),
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

  Future<void> _open(Tk2Note n) async {
    final store = widget.store;
    await store.readNote(n.id);
    if (!mounted) return;
    final txn = n.txnId == null ? null : tk2Ledger(store).where((x) => x.id == n.txnId).firstOrNull;
    if (txn != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Tk2TxnDetail(store: store, txn: txn),
        ),
      );
    } else if (n.dealId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Tk2DealPage(store: store, dealId: n.dealId!, role: DealRole.broker),
        ),
      );
    } else if (n.visitId != null) {
      final v = store.visits.where((v) => v.id == n.visitId).firstOrNull;
      if (v != null) await showTk2Visit(context, store, v);
    } else if (n.listingId != null) {
      final l = store.listing(n.listingId!);
      if (l == null) return;
      if (n.id.startsWith('hr:') && store.inactive(l.id) != null) {
        await showTk2Reminder(context, store, l);
      } else {
        await context.push('/p/${l.id}?d=b');
      }
    }
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.unread, required this.last, required this.now, required this.onTap});
  final Tk2Note note;
  final bool unread, last;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tone(note.tone);
    return Semantics(
      label: unread ? 'Unread' : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                child: Icon(note.icon, size: 23, color: fg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            style: TextStyle(fontSize: 16.5, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: AppColors.heading),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(_ago(note.at, now), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      note.body,
                      style: const TextStyle(fontSize: 14.5, height: 20 / 14.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which kinds of notification ring the phone and count on the bell.
class Tk2NoteSettings extends StatelessWidget {
  const Tk2NoteSettings({required this.store, super.key});
  final Tk2Store store;

  static const _about = {
    'visits': 'New bookings, visits in 2 hours, codes to enter, cancellations',
    'money': 'Visit fees, brokerage and repair payments received',
    'deals': 'Token paid, signing, keys, repairs and your next steps',
    'houses': 'Owner added a house, houses that may be free again',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => OnbPage(
      title: 'Notification settings',
      subtitle: 'Turned off: no alerts on your phone and no count on the bell. They still show in the list.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        OnbCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final e in Tk2Note.kinds.entries)
                SwitchListTile(
                  value: !store.notesMuted.contains(e.key),
                  onChanged: (on) => store.muteNotes(e.key, off: !on),
                  title: Text(
                    e.value,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
                  subtitle: Text(_about[e.key]!, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const OnbBanner('Phone alerts start once the app is connected to TrustKeyper online.', kind: 'mute', icon: Icons.info_outline),
      ],
    ),
  );
}
