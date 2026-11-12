import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_deal.dart';
import 'tk2_deal_screens.dart';
import 'tk2_invite.dart';
import 'tk2_link.dart';
import 'tk2_store.dart';

/// One finalised house, from token to moved in: the same page for the broker
/// (app), the tenant and the owner (web). It shows this person's next step,
/// who everyone is waiting for, and the ten stages.
class Tk2DealPage extends StatelessWidget {
  const Tk2DealPage({required this.store, required this.dealId, required this.role, this.onDocs, this.showBack = true, super.key});
  final Tk2Store store;
  final String dealId;
  final DealRole role;
  final bool showBack;

  /// Tenant and owner upload documents on the web app's own screens.
  final Future<void> Function(BuildContext context, Tk2Deal deal)? onDocs;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final d = store.deal(dealId);
      if (d == null) {
        return OnbPage(
          title: 'Not found',
          onBack: () => Navigator.of(context).maybePop(),
          children: const [OnbCentered(icon: Icons.search_off, title: 'This is no longer here', message: 'Ask your broker for a new link.')],
        );
      }
      final now = DateTime.now();
      final mine = d.tasks(role, now);
      final main = mine.where((x) => !Tk2Deal.optional.contains(x.key)).toList();
      final others = d.holders(now).where((r) => r != role).toList();
      return OnbPage(
        title: d.title,
        subtitle: switch (role) {
          DealRole.broker => 'Tenant ${d.nameOf(DealRole.tenant)} · Owner ${d.nameOf(DealRole.owner)}',
          DealRole.tenant => 'Your move-in, step by step',
          DealRole.owner => 'Your house is being rented to ${d.nameOf(DealRole.tenant)}',
        },
        showBack: showBack,
        onBack: () => Navigator.of(context).maybePop(),
        footer: [
          if (main.isNotEmpty)
            PrimaryButton(
              label: main.first.label,
              icon: Icons.chevron_right,
              onPressed: () => openDealTask(context, store, d, role, main.first.key, onDocs: onDocs),
            ),
        ],
        children: [
          if (d.ended != null) _Ended(d, role) else ..._next(context, d, main, others, now),
          const SizedBox(height: 22),
          const Text(
            'All steps',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
          ),
          const SizedBox(height: 10),
          for (final s in DealStage.values) _StageRow(store: store, deal: d, role: role, stage: s, now: now),
          if (role == DealRole.broker && d.ended == null && d.stage(now).index < DealStage.payment.index) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => showDealEnd(context, store, d),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('The deal is off'),
              ),
            ),
          ],
        ],
      );
    },
  );

  List<Widget> _next(BuildContext context, Tk2Deal d, List<DealTask> main, List<DealRole> others, DateTime now) => [
    if (main.isEmpty && others.isEmpty && d.stage(now) == DealStage.living)
      OnbCentered(
        icon: Icons.home_outlined,
        kind: 'ok',
        title: role == DealRole.tenant ? 'Welcome home!' : 'Moved in',
        message: 'Everything is done. The agreement, payments and handover record stay here.',
      )
    else if (main.isEmpty && others.isEmpty)
      OnbBanner(
        d.stage(now) == DealStage.repairs
            ? '${d.repairDaysLeft(now)} ${d.repairDaysLeft(now) == 1 ? 'day' : 'days'} left to report anything broken.'
            : 'Nothing to do right now.',
        kind: 'ok',
        icon: Icons.check_circle_outline,
      )
    else if (main.isEmpty)
      OnbBanner('Waiting for ${_names(d, others)}. We tell you when it is your turn.', kind: 'wait', icon: Icons.hourglass_top),
    if (role != DealRole.broker && d.redo(role).isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OnbBanner('The broker asked: ${d.redo(role)}', kind: 'need', icon: Icons.edit_note),
      ),
    // More than one thing to do: the rest sit under the main button's step.
    for (final x in main.skip(1))
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OnbRow(
          icon: Icons.arrow_forward,
          title: x.label,
          onTap: () => openDealTask(context, store, d, role, x.key, onDocs: onDocs),
        ),
      ),
    if (role == DealRole.tenant && d.tasks(role, now).any((x) => x.key == 'raise'))
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OnbRow(
          icon: Icons.build_outlined,
          title: 'Report something broken',
          subtitle: '${d.repairDaysLeft(now)} ${d.repairDaysLeft(now) == 1 ? 'day' : 'days'} left · the owner pays for old problems',
          onTap: () => openDealTask(context, store, d, role, 'raise'),
        ),
      ),
    if (d.tasks(role, now).any((x) => x.key == 'feeEarly'))
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OnbRow(
          icon: Icons.currency_rupee,
          title: 'Pay the ${Tk2Store.money(Tk2Deal.feeShare)} agreement fee now',
          subtitle: d.ownerBrokerage > 0 ? 'Or pay it with your brokerage after signing' : 'Or pay it after signing',
          onTap: () => openDealTask(context, store, d, role, 'feeEarly'),
        ),
      ),
    // The broker can remind whoever is holding things up.
    if (role == DealRole.broker)
      for (final r in others)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OnbRow(
            icon: Icons.notifications_active_outlined,
            tone: 'wait',
            title: 'Remind ${d.nameOf(r).split(' ').first}',
            subtitle: d.tasks(r, now).first.label,
            onTap: () => _nudge(context, d, r, d.tasks(r, now).first.label),
          ),
        ),
    // Demo build (no backend): play the other people's steps on this phone.
    if (store.sync == null)
      for (final r in others)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: () async {
              d.demoDo(r, DateTime.now());
              await store.saveDeal(d, r);
            },
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text("Demo: do the ${Tk2Deal.who(r)}'s step"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.border),
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
  ];

  static String _names(Tk2Deal d, List<DealRole> who) => who.map((r) => 'the ${Tk2Deal.who(r)}').join(' and ');

  Future<void> _nudge(BuildContext context, Tk2Deal d, DealRole to, String what) async {
    final phone = to == DealRole.tenant ? d.tenantPhone : d.ownerPhone;
    final link = tk2DealLink(d, to, store.listing(d.listingId));
    final first = d.nameOf(to).split(' ').first;
    final message = 'Hi $first, one step is waiting for you for ${d.title}: $what. Open here: $link';
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      // No number saved for this person: copy the reminder to paste anywhere.
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('Reminder copied. Paste it to $first.')));
      return;
    }
    await showTk2OwnerInvite(context, ownerName: d.nameOf(to), phone: phone, message: message, title: 'Remind $first');
  }
}

class _Ended extends StatelessWidget {
  const _Ended(this.d, this.role);
  final Tk2Deal d;
  final DealRole role;

  @override
  Widget build(BuildContext context) {
    final split = Tk2Deal.tokenSplit(d.token, d.ended!);
    final paid = d.t['tokenPaid'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnbBanner(
          d.ended == 'owner' ? 'The owner backed out. The deal is off.' : 'The tenant backed out. The deal is off.',
          kind: 'need',
          icon: Icons.cancel_outlined,
        ),
        if (paid) ...[
          const SizedBox(height: 12),
          OnbCard(
            child: Column(
              children: [
                OnbKeyValue('Token paid', Tk2Store.money(d.token)),
                if (split.tenant > 0) OnbKeyValue('Back to the tenant', Tk2Store.money(split.tenant), last: true),
                if (split.owner > 0) OnbKeyValue('To the owner', Tk2Store.money(split.owner)),
                if (split.broker > 0) OnbKeyValue('To the broker', Tk2Store.money(split.broker), last: true),
              ],
            ),
          ),
        ],
        if (role == DealRole.broker) ...[
          const SizedBox(height: 12),
          const OnbBanner('The house is back on the market. Shared links work again.', kind: 'info', icon: Icons.storefront_outlined),
        ],
      ],
    );
  }
}

/// One line of the ten-stage tracker.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.store, required this.deal, required this.role, required this.stage, required this.now});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;
  final DealStage stage;
  final DateTime now;

  /// What can be opened to read at this stage (null = nothing yet).
  VoidCallback? _open(BuildContext context) => switch (stage) {
    DealStage.draft ||
    DealStage.approval ||
    DealStage.signing when deal.version > 0 => () => dealPush(context, DealAgreement(store: store, deal: deal, role: role)),
    DealStage.payment when deal.t['paid'] == true => () => dealPush(context, DealReceipt(deal: deal, role: role)),
    DealStage.handover when deal.handoverAt > 0 => () => dealPush(context, DealRecord(store: store, deal: deal, role: role)),
    DealStage.repairs when deal.handoverAt > 0 => () => dealPush(context, DealRepairs(store: store, deal: deal, role: role)),
    DealStage.society when deal.societySteps.isNotEmpty => () => dealPush(context, DealSociety(store: store, deal: deal, role: role)),
    _ => null,
  };

  String _sub() {
    final state = deal.stageState(stage, now);
    if (deal.ended != null) return state == 'done' ? 'Done' : '';
    if (state == 'done') return 'Done';
    if (state == 'later') return '';
    final who = [
      for (final r in DealRole.values)
        if (deal.tasks(r, now).any((x) => x.stage == stage && !Tk2Deal.optional.contains(x.key))) r == role ? 'you' : 'the ${Tk2Deal.who(r)}',
    ];
    if (stage == DealStage.repairs && who.isEmpty) return '${deal.repairDaysLeft(now)} days left';
    return who.isEmpty ? 'In progress' : 'Waiting for ${who.join(' and ')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = deal.ended != null && deal.stageState(stage, now) != 'done' ? 'later' : deal.stageState(stage, now);
    final open = _open(context);
    final sub = _sub();
    final color = switch (state) {
      'done' => AppColors.success,
      'now' => AppColors.primary,
      _ => AppColors.disabled,
    };
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: state == 'done' ? AppColors.successSoft : (state == 'now' ? AppColors.primarySoft : AppColors.surfaceMuted),
              ),
              child: state == 'done'
                  ? const Icon(Icons.check, size: 18, color: AppColors.success)
                  : Text(
                      '${stage.index + 1}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dealStageNames[stage]!,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: state == 'now' ? FontWeight.w700 : FontWeight.w500,
                      color: state == 'later' ? AppColors.disabled : AppColors.heading,
                    ),
                  ),
                  if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 13.5, color: state == 'now' ? AppColors.primaryDark : AppColors.muted)),
                ],
              ),
            ),
            if (open != null) const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Small card for lists of deals (broker home, web landing).
class Tk2DealCard extends StatelessWidget {
  const Tk2DealCard({required this.deal, required this.role, required this.onTap, super.key});
  final Tk2Deal deal;
  final DealRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mine = deal.tasks(role, now).where((x) => !Tk2Deal.optional.contains(x.key)).toList();
    final others = deal.holders(now).where((r) => r != role).toList();
    final stage = deal.stage(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OnbRow(
        icon: deal.ended != null
            ? Icons.cancel_outlined
            : (mine.isNotEmpty ? Icons.priority_high : (stage == DealStage.living ? Icons.home_outlined : Icons.hourglass_top)),
        tone: deal.ended != null ? 'mute' : (mine.isNotEmpty ? 'need' : (stage == DealStage.living ? 'ok' : 'wait')),
        title: role == DealRole.broker ? '${deal.title} · ${deal.nameOf(DealRole.tenant).split(' ').first}' : deal.title,
        subtitle: deal.ended != null
            ? 'The deal is off'
            : mine.isNotEmpty
            ? mine.first.label
            : others.isNotEmpty
            ? '${dealStageNames[stage]} · waiting for ${others.map((r) => 'the ${Tk2Deal.who(r)}').join(' and ')}'
            : 'Step ${stage.index + 1} of 10 · ${dealStageNames[stage]}',
        onTap: onTap,
      ),
    );
  }
}

/// Call a person from a deal.
void dealCall(String phone) => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'));
