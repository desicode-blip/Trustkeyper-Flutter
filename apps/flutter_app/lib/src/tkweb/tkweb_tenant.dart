import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_customer.dart';
import '../tk2/tk2_store.dart';
import '../tk2/tk2_widgets.dart';
import 'tkweb_auth.dart';
import 'tkweb_session.dart';

/// Tenant journey on the web, in order. Index = step number in the session.
const tkwTenantSteps = ['visit', 'block', 'details', 'owner', 'agreement', 'sign', 'pay', 'keys', 'home'];

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
        onBook: () => step == null ? tkwStartBooking(context, listingId) : Navigator.of(context).push(_route(TkwStep(listingId: listingId, index: step.clamp(0, tkwTenantSteps.length - 1)))),
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
    final s = TkwSession.instance;
    return OnbPage(
      title: 'Pay and book',
      subtitle: l.publicTitle,
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        PrimaryButton(label: l.visitFee == 0 ? 'Book visit' : 'Pay ${Tk2Store.money(l.visitFee)}', icon: Icons.lock_outline, iconBeforeLabel: true, loading: paying, onPressed: paying ? null : _pay),
      ],
      children: [
        OnbCard(
          child: Column(
            children: [
              OnbKeyValue('Visit', '${tk2Day(widget.at)}, ${tk2Time(widget.at)}'),
              OnbKeyValue('Name', s.name),
              OnbKeyValue('Phone', s.contact),
              OnbKeyValue('Visit fee', l.visitFee == 0 ? 'Free' : Tk2Store.money(l.visitFee), last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _rule(Icons.verified_user_outlined, 'TrustKeyper keeps the fee safe and pays the broker only after your visit.'),
        _rule(Icons.replay, 'If the broker or owner is not available, you get it all back.'),
        _rule(Icons.timer_outlined, 'You can cancel within 5 minutes of booking (2% is kept). After that it is not refunded.'),
        _rule(Icons.directions_walk, 'We wait 15 minutes. If you are later than that, the visit is cancelled and not refunded.'),
        const SizedBox(height: 12),
        const OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined),
      ],
    );
  }
}

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
  late final fullName = TextEditingController(text: trip['fullName'] as String? ?? s.name);
  late final email = TextEditingController(text: trip['email'] as String? ?? '');
  late final address = TextEditingController(text: trip['address'] as String? ?? '');
  late final work = TextEditingController(text: trip['work'] as String? ?? '');
  late final people = TextEditingController(text: trip['people'] as String? ?? '');
  final sign = TextEditingController();
  final Set<String> bad = {};
  bool busy = false;
  Timer? ticker;

  String get key => tkwTenantSteps[widget.index];
  bool get done => (trip['step'] as int? ?? 0) > widget.index;
  Tk2Listing get l => Tk2Store.instance.listing(widget.listingId)!;

  @override
  void initState() {
    super.initState();
    if (key == 'visit') ticker = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    ticker?.cancel();
    for (final c in [fullName, email, address, work, people, sign]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _moveIn => l.deposit + l.rent + (l.maintenanceIncluded ? 0 : l.maintenance) + l.brokerage;

  Future<void> _complete() async {
    if (done) return _goNext();
    if (key == 'details') {
      bad
        ..clear()
        ..addAll({
          if (fullName.text.trim().length < 3) 'fullName',
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email.text.trim())) 'email',
          if (address.text.trim().length < 8) 'address',
          if (trip['aadhaar'] != true) 'aadhaar',
        });
      if (bad.isNotEmpty) return setState(() {});
      trip.addAll({'fullName': fullName.text.trim(), 'email': email.text.trim(), 'address': address.text.trim(), 'work': work.text.trim(), 'people': people.text.trim()});
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
    final sure = await onbConfirm(
      context,
      title: 'Cancel this visit?',
      message: '${Tk2Store.money(Tk2Visit.refundAfterFee(l.visitFee))} comes back to you (2% is kept).',
      yes: 'Keep visit',
      no: 'Cancel visit',
    );
    if (sure || !mounted) return;
    final visitId = trip['visitId'] as String?;
    if (visitId != null) await Tk2Store.instance.customerCancel(visitId);
    trip['cancelled'] = true;
    await s.save();
    if (mounted) setState(() {});
  }

  Future<void> _upload(String what) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (file == null) return;
      trip[what] = true;
      bad.remove(what);
      await s.save();
      if (mounted) setState(() {});
    } catch (_) {}
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
    final (title, action, children) = switch (key) {
      'visit' => _visitStep(),
      'block' => ('Block this house', 'Pay ${Tk2Store.money(tkwToken)} and block', _blockStep()),
      'details' => ('Your details', 'Send my details', _detailsStep()),
      'owner' => ('Owner details', 'Demo: owner shared details', _ownerStep()),
      'agreement' => ('Rent agreement', 'Demo: broker approved', _agreementStep(final_: false)),
      'sign' => ('Sign the agreement', 'Sign', _signStep()),
      'pay' => ('Pay to move in', 'Pay ${Tk2Store.money(_moveIn)}', _payStep()),
      'keys' => ('Get your keys', 'Demo: I got the keys', _keysStep()),
      _ => ('Welcome home', 'Done', _homeStep()),
    };
    return OnbPage(
      title: title,
      subtitle: key == 'visit' || key == 'home' ? l.publicTitle : 'Step ${widget.index} of ${tkwTenantSteps.length - 2} · ${l.publicTitle}',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [if (action.isNotEmpty) PrimaryButton(label: done ? 'Continue' : action, icon: Icons.chevron_right, loading: busy, onPressed: busy ? null : _complete)],
      children: [
        if (done && key != 'visit') ...[const OnbBanner('Done', kind: 'ok', icon: Icons.check_circle_outline), const SizedBox(height: 16)],
        ...children,
      ],
    );
  }

  (String, String, List<Widget>) _visitStep() {
    final v = _visit;
    if (trip['cancelled'] == true || v == null) {
      return (
        'Visit cancelled',
        '',
        [
          OnbCentered(icon: Icons.event_busy_outlined, title: 'Visit cancelled', message: '${Tk2Store.money(Tk2Visit.refundAfterFee(l.visitFee))} comes back to you in 3–5 days.'),
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
    final left = Tk2Visit.cancelWindow.inSeconds - DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(trip['bookedAt'] as int? ?? 0)).inSeconds;
    return (
      'Your visit',
      'I saw the house · I want it',
      [
        if (!done) ...[const Center(child: Tk2SuccessTick()), const SizedBox(height: 18)],
        Text(
          done ? 'Visit done' : 'Visit booked!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.heading),
        ),
        const SizedBox(height: 6),
        Text(
          '${tk2Day(at)}, ${tk2Time(at)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16.5, color: AppColors.muted),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              const Text('Your visit code', style: TextStyle(fontSize: 15, color: AppColors.primaryDark)),
              const SizedBox(height: 6),
              Text(
                v.code.split('').join(' '),
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 4, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 6),
              const Text('Tell this to the broker after you see the house.', style: TextStyle(fontSize: 14, color: AppColors.primaryDark)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OnbSecondaryButton(
          label: 'Add to Google Calendar',
          onPressed: () => launchUrl(_calendar(at), mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: 14),
        _rule(Icons.phone_in_talk_outlined, 'We call you and the broker 1 hour before the visit.'),
        _rule(Icons.directions_walk, 'Please be on time. We wait 15 minutes.'),
        if (!done && left > 0) ...[
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: _cancelVisit,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.close, size: 18),
              label: Text('Cancel visit · ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left'),
            ),
          ),
        ],
        if (!done) ...[const SizedBox(height: 10), const OnbBanner('Demo build: after the visit the broker types your code. Tap below to move ahead.', kind: 'wait', icon: Icons.science_outlined)],
      ],
    );
  }

  List<Widget> _blockStep() => [
    const Text(
      'Pay a token amount and the house is kept for you. No one else can take it.',
      style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body),
    ),
    const SizedBox(height: 18),
    OnbCard(child: Column(children: [OnbKeyValue('House', l.publicTitle), OnbKeyValue('Token amount', Tk2Store.money(tkwToken), last: true)])),
    const SizedBox(height: 16),
    const Tk2NextSteps(done: 1),
    const SizedBox(height: 12),
    const OnbBanner('Demo build: test payment. No money moves.', kind: 'wait', icon: Icons.science_outlined),
  ];

  List<Widget> _detailsStep() => [
    const OnbBanner('House blocked for you', kind: 'ok', icon: Icons.lock_outline),
    const SizedBox(height: 16),
    const Text(
      'For the rent agreement. The owner is asked for theirs at the same time.',
      style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: AppColors.muted),
    ),
    const SizedBox(height: 8),
    OnbTextField(
      label: 'Full name (as on Aadhaar) *',
      controller: fullName,
      capitalization: TextCapitalization.words,
      error: bad.contains('fullName') ? 'Type your full name' : null,
      onChanged: (_) => setState(() => bad.remove('fullName')),
    ),
    const SizedBox(height: 12),
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
    const SizedBox(height: 16),
    _uploadRow('aadhaar', 'Aadhaar card', 'Front and back', need: bad.contains('aadhaar')),
  ];

  Widget _uploadRow(String k, String title, String sub, {bool need = false}) {
    final has = trip[k] == true;
    return OnbRow(
      icon: has ? Icons.check : Icons.upload_file_outlined,
      title: title,
      subtitle: has
          ? 'Added · tap to change'
          : need
          ? 'Add this to continue'
          : sub,
      tone: has
          ? 'ok'
          : need
          ? 'need'
          : 'info',
      onTap: () => _upload(k),
    );
  }

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
    OnbBanner(final_ ? 'Final agreement' : 'Ready · the broker is checking it', kind: final_ ? 'ok' : 'wait', icon: final_ ? Icons.verified_outlined : Icons.hourglass_top),
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
    OnbCentered(icon: Icons.home_outlined, kind: 'ok', title: 'Welcome home!', message: 'Your agreement and payment receipts are saved here. We will remind you before rent is due.'),
  ];
}
