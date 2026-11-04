import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/data/private_documents.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../features/broker/presentation/private_documents_screen.dart';
import '../features/document_requests/data/document_request_repository.dart';
import '../features/document_requests/presentation/recipient_document_layout.dart';
import '../tk2/tk2_customer.dart';
import '../tk2/tk2_designs.dart';
import '../tk2/tk2_store.dart';
import '../tk2/tk2_widgets.dart';
import 'tkweb_auth.dart';
import 'tkweb_session.dart';

/// Tenant journey on the web, in order. Index = step number in the session.
const tkwTenantSteps = ['visit', 'block', 'docs', 'details', 'owner', 'agreement', 'sign', 'pay', 'keys', 'home'];

/// Token amount that blocks a house.
const tkwToken = 15000;

Route<void> _route(Widget page, [String? name]) => MaterialPageRoute<void>(
  builder: (_) => page,
  settings: RouteSettings(name: name),
);

/// The property link: the same customer page the broker previews in the app.
class TkwProperty extends StatelessWidget {
  const TkwProperty({required this.listingId, super.key});
  final String listingId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: TkwSession.instance,
    builder: (context, _) {
      final trip = TkwSession.instance.trips[listingId];
      final step = trip?['step'] as int?;
      return Tk2CustomerPage(
        store: Tk2Store.instance,
        id: listingId,
        preview: false,
        bookLabel: step == null ? null : 'See your visit',
        onBook: () => step == null
            ? tkwStartBooking(context, listingId)
            : Navigator.of(context).push(_route(TkwStep(listingId: listingId, index: step.clamp(0, tkwTenantSteps.length - 1)))),
      );
    },
  );
}

/// Day and time → (sign up) → pay.
void tkwStartBooking(BuildContext context, String listingId) {
  final nav = Navigator.of(context);
  nav.push(
    _route(
      Tk2BookVisit(
        store: Tk2Store.instance,
        id: listingId,
        onPicked: (at) {
          if (TkwSession.instance.signedIn) {
            nav.push(_route(TkwPay(listingId: listingId, at: at)));
            return;
          }
          nav.push(
            _route(
              TkwSignUp(
                allowEmail: false,
                subtitle: 'Your name and phone, so the broker can call you about the visit.',
                onDone: () {
                  // Back from paying goes to the time screen, not to the code.
                  nav.popUntil((r) => r.settings.name == 'book');
                  nav.push(_route(TkwPay(listingId: listingId, at: at)));
                },
              ),
            ),
          );
        },
      ),
      'book',
    ),
  );
}

/// Pay the visit fee (test payment) and book.
class TkwPay extends StatefulWidget {
  const TkwPay({required this.listingId, required this.at, super.key});
  final String listingId;
  final DateTime at;

  @override
  State<TkwPay> createState() => _TkwPayState();
}

class _TkwPayState extends State<TkwPay> {
  bool paying = false;

  Future<void> _pay() async {
    setState(() => paying = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final s = TkwSession.instance;
    final visit = await Tk2Store.instance.bookVisit(listingId: widget.listingId, name: s.name, phone: s.contact, at: widget.at);
    s.trips[widget.listingId] = {'step': 0, 'visitId': visit.id, 'bookedAt': DateTime.now().millisecondsSinceEpoch};
    await s.save();
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    nav.push(_route(TkwStep(listingId: widget.listingId, index: 0)));
  }

  @override
  Widget build(BuildContext context) {
    final l = Tk2Store.instance.listing(widget.listingId)!;
    return OnbPage(
      title: 'Pay and book',
      subtitle: l.publicTitle,
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        PrimaryButton(
          label: l.visitFee == 0 ? 'Book visit' : 'Pay ${Tk2Store.money(l.visitFee)}',
          icon: Icons.lock_outline,
          iconBeforeLabel: true,
          loading: paying,
          onPressed: paying ? null : _pay,
        ),
      ],
      children: [
        // When · where · fee, each with its icon.
        OnbCard(
          child: Column(
            children: [
              _fact(Icons.event_outlined, 'When', '${tk2Day(widget.at)}, ${tk2Time(widget.at)}'),
              const Divider(height: 1, color: AppColors.border),
              _fact(
                Icons.location_on_outlined,
                'Where',
                tk2PublicAddress(l),
                action: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': tk2PublicAddress(l)}),
                    mode: LaunchMode.externalApplication,
                  ),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _fact(Icons.confirmation_number_outlined, 'Visit fee', l.visitFee == 0 ? 'Free' : Tk2Store.money(l.visitFee)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text('Good to know', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
        const SizedBox(height: 6),
        _rule(Icons.verified_user_outlined, 'Your payment is safe with us.'),
        _rule(Icons.replay, 'If the broker or owner cancels, you get a full refund. If you cancel, there is no refund.'),
        _rule(Icons.timer_outlined, 'Changed your mind? Cancel within 5 minutes for a full refund, minus a 2% platform fee.'),
        _rule(Icons.directions_walk, 'Please be on time. The agent waits 15 minutes, then the visit counts as cancelled.'),
        const SizedBox(height: 12),
        const OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined),
      ],
    );
  }
}

/// One line of the booking summary: icon, small label, the value.
Widget _fact(IconData icon, String label, String value, {Widget? action}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Badge(icon),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 16.5, height: 22 / 16.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
            ?action,
          ],
        ),
      ),
    ],
  ),
);

Widget _rule(IconData icon, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppColors.primaryDark),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.body),
        ),
      ),
    ],
  ),
);

/// One step of the tenant journey after booking. Back goes one step back and
/// shows that step as done.
class TkwStep extends StatefulWidget {
  const TkwStep({required this.listingId, required this.index, super.key});
  final String listingId;
  final int index;

  @override
  State<TkwStep> createState() => _TkwStepState();
}

class _TkwStepState extends State<TkwStep> {
  final s = TkwSession.instance;
  late final Map<String, dynamic> trip = s.trip(widget.listingId);
  late final email = TextEditingController(text: trip['email'] as String? ?? '');
  late final address = TextEditingController(text: trip['address'] as String? ?? '');
  late final work = TextEditingController(text: trip['work'] as String? ?? '');
  late final people = TextEditingController(text: trip['people'] as String? ?? '');
  final sign = TextEditingController();
  final Set<String> bad = {};
  bool busy = false;

  String get key => tkwTenantSteps[widget.index];
  bool get done => (trip['step'] as int? ?? 0) > widget.index;
  Tk2Listing get l => Tk2Store.instance.listing(widget.listingId)!;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (final c in [email, address, work, people, sign]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _moveIn => l.deposit + l.rent + (l.maintenanceIncluded ? 0 : l.maintenance) + l.brokerage;

  Future<void> _complete() async {
    if (done) return _goNext();
    // After the visit: ask if they liked it before blocking.
    if (key == 'visit') {
      await Navigator.of(context).push(_route(TkwLiked(listingId: widget.listingId, index: widget.index)));
      if (mounted) setState(() {});
      return;
    }
    if (key == 'details') {
      bad
        ..clear()
        ..addAll({if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email.text.trim())) 'email', if (address.text.trim().length < 8) 'address'});
      if (bad.isNotEmpty) return setState(() {});
      trip.addAll({'email': email.text.trim(), 'address': address.text.trim(), 'work': work.text.trim(), 'people': people.text.trim()});
    }
    if (key == 'sign' && sign.text.trim().length < 3) return setState(() => bad.add('sign'));
    if (key == 'home') {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    setState(() => busy = true);
    // Payments wait a moment like a real gateway would.
    if (key == 'block' || key == 'pay') await Future<void>.delayed(const Duration(milliseconds: 900));
    trip['step'] = widget.index + 1;
    await s.save();
    if (!mounted) return;
    setState(() => busy = false);
    _goNext();
  }

  void _goNext() => Navigator.of(context).push(_route(TkwStep(listingId: widget.listingId, index: widget.index + 1)));

  Future<void> _cancelVisit() async {
    final inTime = _visit?.inRefundWindow(DateTime.now()) ?? false;
    final sure = await onbConfirm(
      context,
      title: 'Cancel this visit?',
      message: inTime
          ? '${Tk2Store.money(Tk2Visit.refundAfterFee(l.visitFee))} comes back to you (2% platform fee).'
          : 'It has been more than 5 minutes since you booked, so the visit fee is not refunded.',
      yes: 'Keep visit',
      no: 'Cancel visit',
    );
    if (sure || !mounted) return;
    final visitId = trip['visitId'] as String?;
    if (visitId != null) await Tk2Store.instance.customerCancel(visitId);
    trip['cancelled'] = true;
    trip['refund'] = inTime ? Tk2Visit.refundAfterFee(l.visitFee) : 0;
    await s.save();
    if (mounted) setState(() {});
  }

  Uri _calendar(DateTime at) {
    String f(DateTime d) => '${d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': 'House visit · ${l.publicTitle}',
      'dates': '${f(at)}/${f(at.add(const Duration(hours: 1)))}',
      'details': 'Visit code: ${_visit?.code ?? ''}. Booked on TrustKeyper.',
      'location': l.area,
    });
  }

  Tk2Visit? get _visit => Tk2Store.instance.visits.where((v) => v.id == trip['visitId']).firstOrNull;

  @override
  Widget build(BuildContext context) {
    if (key == 'docs') {
      return TkwTenantDocs(
        listing: l,
        trip: trip,
        onExit: () => Navigator.of(context).maybePop(),
        onSent: () async {
          trip['step'] = widget.index + 1;
          await s.save();
          if (mounted) _goNext();
        },
      );
    }
    final (title, action, children) = switch (key) {
      'visit' => _visitStep(),
      'block' => ('Block this house', 'Pay ${Tk2Store.money(tkwToken)} and block', _blockStep()),
      'details' => ('Your details for rental agreement', 'Send my details', _detailsStep()),
      'owner' => ('Owner details', 'Demo: owner shared details', _ownerStep()),
      'agreement' => ('Rent agreement', 'Demo: broker approved', _agreementStep(final_: false)),
      'sign' => ('Sign the agreement', 'Sign', _signStep()),
      'pay' => ('Pay to move in', 'Pay ${Tk2Store.money(_moveIn)}', _payStep()),
      'keys' => ('Get your keys', 'Demo: I got the keys', _keysStep()),
      _ => ('Welcome home', 'Done', _homeStep()),
    };
    return OnbPage(
      title: title,
      step: key == 'visit' || key == 'home' ? null : 'Step ${widget.index} of ${tkwTenantSteps.length - 2}',
      subtitle: l.publicTitle,
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        if (action.isNotEmpty) PrimaryButton(label: done ? 'Continue' : action, icon: Icons.chevron_right, loading: busy, onPressed: busy ? null : _complete),
      ],
      children: [
        if (done && key != 'visit') ...[const OnbBanner('Done', kind: 'ok', icon: Icons.check_circle_outline), const SizedBox(height: 16)],
        ...children,
      ],
    );
  }

  (String, String, List<Widget>) _visitStep() {
    final v = _visit;
    if (trip['cancelled'] == true || v == null) {
      final refund = trip['refund'] as int? ?? Tk2Visit.refundAfterFee(l.visitFee);
      return (
        'Visit cancelled',
        '',
        [
          OnbCentered(
            icon: Icons.event_busy_outlined,
            title: 'Visit cancelled',
            message: refund > 0
                ? '${Tk2Store.money(refund)} comes back to you in 3–5 days.'
                : 'The visit fee is not refunded, as it was more than 5 minutes after booking.',
          ),
          const SizedBox(height: 24),
          OnbSecondaryButton(
            label: 'Book another time',
            onPressed: () async {
              final nav = Navigator.of(context);
              s.trips.remove(widget.listingId);
              await s.save();
              nav.popUntil((r) => r.isFirst);
            },
          ),
        ],
      );
    }
    final at = DateTime.fromMillisecondsSinceEpoch(v.at);
    final store = Tk2Store.instance;
    final address = tk2PublicAddress(l);
    return (
      'Your visit',
      'I visited the place',
      [
        // 1. Status
        Center(child: OnbPill(done ? 'Visit done' : 'Visit booked', 'ok', icon: Icons.check_circle_outline)),
        const SizedBox(height: 14),
        // 2. When
        _block(
          'When',
          Row(
            children: [
              const _Badge(Icons.event_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full date first ("Tue 3 Nov"), then time and "Tomorrow" when it helps.
                    Text(
                      tk2Day(at, now: DateTime(2000)),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
                    ),
                    Text(
                      [tk2Time(at), if (tk2Day(at) != tk2Day(at, now: DateTime(2000))) tk2Day(at)].join(' · '),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: ('Add to Google Calendar', Icons.calendar_month_outlined, () => launchUrl(_calendar(at), mode: LaunchMode.externalApplication)),
        ),
        // 3. Where
        _block(
          'Where',
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Badge(Icons.location_on_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      style: const TextStyle(fontSize: 17, height: 23 / 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                    ),
                    const SizedBox(height: 4),
                    const Text('The broker meets you at the gate.', style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          action: (
            'Open in Google Maps',
            Icons.map_outlined,
            () => launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}), mode: LaunchMode.externalApplication),
          ),
        ),
        // 4. Who
        _block(
          'Your broker',
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  tk2Initials(store.brokerName.isEmpty ? 'Broker' : store.brokerName),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.brokerName.isEmpty ? 'Your broker' : store.brokerName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                    ),
                    Text(store.brokerPhone.isEmpty ? 'Shows you the house' : store.brokerPhone, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          action: store.brokerPhone.isEmpty
              ? null
              : (
                  'Call ${store.brokerName.isEmpty ? 'broker' : store.brokerName.split(' ').first}',
                  Icons.call_outlined,
                  () => launchUrl(Uri.parse('tel:${store.brokerPhone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
                ),
        ),
        // 5. Code
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              const Text('Your visit code', style: TextStyle(fontSize: 15, color: AppColors.primaryDark)),
              const SizedBox(height: 4),
              Text(
                v.code.split('').join(' '),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tell this to the broker after you see the house.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.primaryDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // 6. Good to know
        const Text(
          'Good to know',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
        ),
        const SizedBox(height: 4),
        _rule(Icons.phone_in_talk_outlined, 'We call you and the broker 1 hour before the visit.'),
        _rule(Icons.badge_outlined, 'Gated society? The broker sends your gate pass on WhatsApp before the visit.'),
        _rule(Icons.directions_walk, 'Please be on time. We wait 15 minutes.'),
        if (!done) ...[
          const SizedBox(height: 8),
          // Small and out of the way: bottom right, under "Good to know".
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _cancelVisit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.border),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: const Text('Cancel visit'),
            ),
          ),
          const SizedBox(height: 10),
          const OnbBanner('Demo build: after the visit the broker types your code. Tap below to move ahead.', kind: 'wait', icon: Icons.science_outlined),
        ],
      ],
    );
  }

  /// A titled white card with an optional action row at the bottom.
  Widget _block(String label, Widget body, {(String, IconData, VoidCallback)? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(fontSize: 12.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                body,
              ],
            ),
          ),
          if (action != null) ...[
            const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: action.$3,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.$2, size: 20, color: AppColors.primaryDark),
                    const SizedBox(width: 8),
                    Text(
                      action.$1,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  List<Widget> _blockStep() => [
    const Text(
      'Pay a token amount and the house is kept for you. No one else can take it.',
      style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body),
    ),
    const SizedBox(height: 18),
    OnbCard(child: Column(children: [OnbKeyValue('House', l.publicTitle), OnbKeyValue('Token amount', Tk2Store.money(tkwToken), last: true)])),
    const SizedBox(height: 16),
    const Tk2NextSteps(done: 2),
    const SizedBox(height: 12),
    const OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined),
  ];

  List<Widget> _detailsStep() => [
    const OnbBanner('Documents received', kind: 'ok', icon: Icons.check_circle_outline),
    const SizedBox(height: 16),
    const Text(
      'A few more details for the agreement. The owner is asked for theirs at the same time.',
      style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: AppColors.muted),
    ),
    const SizedBox(height: 16),
    OnbTextField(
      label: 'Email *',
      controller: email,
      keyboard: TextInputType.emailAddress,
      error: bad.contains('email') ? 'Type a valid email' : null,
      onChanged: (_) => setState(() => bad.remove('email')),
    ),
    const SizedBox(height: 12),
    OnbTextField(
      label: 'Current address *',
      controller: address,
      maxLines: 3,
      capitalization: TextCapitalization.words,
      error: bad.contains('address') ? 'Type your current address' : null,
      onChanged: (_) => setState(() => bad.remove('address')),
    ),
    const SizedBox(height: 12),
    OnbTextField(label: 'Work: company or what you do', controller: work, capitalization: TextCapitalization.words),
    const SizedBox(height: 12),
    OnbTextField(label: 'How many people will live here', controller: people, keyboard: TextInputType.number),
  ];

  List<Widget> _ownerStep() => [
    const OnbCentered(
      icon: Icons.hourglass_top,
      kind: 'wait',
      loading: true,
      title: 'Waiting for the owner',
      message: 'We have asked the owner for their details. When both are in, the rent agreement is made for you, the owner and the broker.',
    ),
    const SizedBox(height: 24),
    const OnbBanner('Demo build: tap below to pretend the owner has shared their details.', kind: 'wait', icon: Icons.science_outlined),
  ];

  List<Widget> _agreementStep({required bool final_}) => [
    OnbBanner(
      final_ ? 'Final agreement' : 'Ready · the broker is checking it',
      kind: final_ ? 'ok' : 'wait',
      icon: final_ ? Icons.verified_outlined : Icons.hourglass_top,
    ),
    const SizedBox(height: 16),
    OnbCard(
      child: Column(
        children: [
          OnbKeyValue('Tenant', trip['fullName'] as String? ?? s.name),
          OnbKeyValue('House', '${l.property.rooms} · ${l.publicTitle}'),
          OnbKeyValue('Rent', '${Tk2Store.money(l.rent)} / month'),
          OnbKeyValue('Maintenance', l.maintenanceIncluded || l.maintenance == 0 ? 'Included' : '${Tk2Store.money(l.maintenance)} / month'),
          OnbKeyValue('Security deposit', Tk2Store.money(l.deposit)),
          const OnbKeyValue('Term', '11 months'),
          const OnbKeyValue('Notice', '1 month', last: true),
        ],
      ),
    ),
    const SizedBox(height: 14),
    _rule(Icons.edit_note, 'Only the broker can change the agreement. Talk to them for any change.'),
  ];

  List<Widget> _signStep() => [
    ..._agreementStep(final_: true),
    const SizedBox(height: 10),
    const Text('The owner signs too. Type your full name to sign.', style: TextStyle(fontSize: 15.5, color: AppColors.body)),
    const SizedBox(height: 12),
    OnbTextField(
      label: 'Your full name',
      controller: sign,
      capitalization: TextCapitalization.words,
      error: bad.contains('sign') ? 'Type your full name to sign' : null,
      onChanged: (_) => setState(() => bad.remove('sign')),
    ),
    const SizedBox(height: 12),
    const OnbBanner('Demo build: the real e-sign link comes on WhatsApp and email.', kind: 'wait', icon: Icons.science_outlined),
  ];

  List<Widget> _payStep() => [
    const OnbBanner('Signed by you and the owner', kind: 'ok', icon: Icons.draw_outlined),
    const SizedBox(height: 16),
    OnbCard(
      child: Column(
        children: [
          OnbKeyValue('Security deposit', Tk2Store.money(l.deposit)),
          OnbKeyValue('First month rent', Tk2Store.money(l.rent + (l.maintenanceIncluded ? 0 : l.maintenance))),
          if (l.brokerage > 0) OnbKeyValue('Brokerage', Tk2Store.money(l.brokerage)),
          OnbKeyValue('Total', Tk2Store.money(_moveIn), last: true),
        ],
      ),
    ),
    const SizedBox(height: 12),
    const OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined),
  ];

  List<Widget> _keysStep() => [
    const OnbBanner('Paid', kind: 'ok', icon: Icons.check_circle_outline),
    const SizedBox(height: 16),
    _rule(Icons.key_outlined, 'The broker meets you at the house and hands over the keys.'),
    _rule(Icons.receipt_long_outlined, 'Your agreement and receipts stay here.'),
  ];

  List<Widget> _homeStep() => const [
    OnbCentered(
      icon: Icons.home_outlined,
      kind: 'ok',
      title: 'Welcome home!',
      message: 'Your agreement and payment receipts are saved here. We will remind you before rent is due.',
    ),
  ];
}

class _Badge extends StatelessWidget {
  const _Badge(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
    child: Icon(icon, color: AppColors.primaryDark),
  );
}

/// After the visit: did you like it? Yes → block the house. No → we tell the broker.
class TkwLiked extends StatefulWidget {
  const TkwLiked({required this.listingId, required this.index, super.key});
  final String listingId;

  /// Index of the visit step.
  final int index;

  @override
  State<TkwLiked> createState() => _TkwLikedState();
}

class _TkwLikedState extends State<TkwLiked> {
  bool? liked;
  bool showError = false;

  Future<void> _next() async {
    if (liked == null) return setState(() => showError = true);
    final s = TkwSession.instance;
    final trip = s.trip(widget.listingId);
    trip['liked'] = liked;
    if (liked!) trip['step'] = widget.index + 1;
    await s.save();
    if (!mounted) return;
    await Navigator.of(context).push(_route(liked! ? TkwStep(listingId: widget.listingId, index: widget.index + 1) : TkwNotLiked(listingId: widget.listingId)));
  }

  Widget _option(bool value, IconData icon, String title, String sub) {
    final on = liked == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: on ? AppColors.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: on ? AppColors.primary : (showError ? AppColors.error : AppColors.border), width: on ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() {
            liked = value;
            showError = false;
          }),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 28, color: AppColors.primaryDark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: const TextStyle(fontSize: 14.5, height: 20 / 14.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (on) const Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Tk2Store.instance.listing(widget.listingId)!;
    return OnbPage(
      title: 'Did you like it?',
      subtitle: l.publicTitle,
      onBack: () => Navigator.of(context).maybePop(),
      footer: [PrimaryButton(label: 'Continue', icon: Icons.chevron_right, onPressed: _next)],
      children: [
        _option(true, Icons.thumb_up_alt_outlined, 'Yes, I like it', 'Block it with a token so no one else takes it.'),
        _option(false, Icons.thumb_down_alt_outlined, 'No, not for me', 'We will ask the broker to show you other houses.'),
        if (showError) const Text('Pick one', style: TextStyle(fontSize: 14, color: AppColors.error)),
      ],
    );
  }
}

/// Did not like the house: the broker is told and sends more options.
class TkwNotLiked extends StatelessWidget {
  const TkwNotLiked({required this.listingId, super.key});
  final String listingId;

  @override
  Widget build(BuildContext context) {
    final store = Tk2Store.instance;
    final name = store.brokerName.isEmpty ? 'The broker' : store.brokerName;
    return OnbPage(
      title: 'Thanks for telling us',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst))],
      children: [
        OnbCentered(
          icon: Icons.mark_chat_read_outlined,
          title: 'We told $name',
          message: 'We have let $name know this house was not right for you. He will send you more houses. Call him now, or wait for his message.',
        ),
        if (store.brokerPhone.isNotEmpty) ...[
          const SizedBox(height: 24),
          OnbSecondaryButton(
            label: 'Call ${name.split(' ').first}',
            onPressed: () => launchUrl(Uri.parse('tel:${store.brokerPhone.replaceAll(RegExp(r'[^0-9+]'), '')}')),
          ),
        ],
      ],
    );
  }
}

/// Documents for the rent agreement: the main app's tenant document screen
/// (Aadhaar front and back, PAN, bank, LinkedIn), already signed in.
/// Demo build: files stay on this device; the backend uploads them later.
class TkwTenantDocs extends StatefulWidget {
  const TkwTenantDocs({required this.listing, required this.trip, required this.onExit, required this.onSent, super.key});
  final Tk2Listing listing;
  final Map<String, dynamic> trip;
  final VoidCallback onExit;
  final Future<void> Function() onSent;

  @override
  State<TkwTenantDocs> createState() => _TkwTenantDocsState();
}

class _TkwTenantDocsState extends State<TkwTenantDocs> {
  final files = <DocumentKind, DocumentFile>{};
  final code = TextEditingController();
  Map<String, dynamic>? bank;
  Map<String, dynamic>? linkedIn;
  bool busy = false;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  DocumentRequestInfo get _info {
    final session = TkwSession.instance;
    final store = Tk2Store.instance;
    return DocumentRequestInfo({
      'requestId': 'tkw-${widget.listing.id}',
      'type': RequestedPaper.all.name,
      'status': 'requested',
      'phone': session.contact,
      'partyName': session.name,
      'brokerName': store.brokerName.isEmpty ? 'Your broker' : store.brokerName,
      'address': widget.listing.publicTitle,
      'role': 'tenant',
      'verified': true,
      'version': 1,
      'expiresAtMs': DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
    });
  }

  Future<void> _pick(DocumentKind kind, bool camera) async {
    final file = await pickPrivateDocument(camera: camera);
    if (file == null || !mounted) return;
    // Photos get the main app's review step; PDFs go straight in.
    final ok = file.contentType == 'application/pdf' || await reviewPrivateDocument(context, file, upload: true, selectionOnly: true);
    if (ok && mounted) {
      setState(() {
        files[kind] = file;
        if (kind == DocumentKind.bankProof) bank = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => RecipientDocumentLayout(
    info: _info,
    loading: false,
    busy: busy,
    progress: null,
    error: null,
    otpSent: false,
    cooldown: 0,
    code: code,
    files: files,
    bankDetails: bank,
    linkedInDetails: linkedIn,
    initiallyEntered: true,
    onExit: widget.onExit,
    onRequestOtp: () async {},
    onVerify: () async {},
    onReload: () async {},
    onSignOut: () async => widget.onExit(),
    onSubmit: () async {
      setState(() => busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      widget.trip['docs'] = true;
      if (!mounted) return;
      setState(() => busy = false);
      await widget.onSent();
    },
    onPick: _pick,
    onRemove: (kind) async => setState(() => files.remove(kind)),
    onView: (kind) async {
      final file = files[kind];
      if (file != null) await reviewPrivateDocument(context, file, upload: false);
    },
    onBank: (value) => setState(() {
      bank = value;
      files.remove(DocumentKind.bankProof);
    }),
    onLinkedIn: (value) async => setState(() => linkedIn = value),
  );
}
