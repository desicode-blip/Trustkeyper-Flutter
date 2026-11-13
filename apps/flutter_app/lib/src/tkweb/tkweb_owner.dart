import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/broker/data/broker_property_repository.dart';
import '../features/broker/presentation/broker_property_screen.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_cloud.dart';
import '../tk2/tk2_listing.dart';
import '../tk2/tk2_store.dart';
import 'tkweb_auth.dart';
import 'tkweb_close.dart';
import 'tkweb_session.dart';

Route<void> _route(Widget page) => MaterialPageRoute<void>(builder: (_) => page);

/// Owner opens the broker's invite (WhatsApp link): what we ask, then sign up.
class TkwOwnerInvite extends StatefulWidget {
  const TkwOwnerInvite({required this.brokerName, required this.houseName, this.inviteId, super.key});
  final String brokerName;
  final String houseName;
  final String? inviteId;

  @override
  State<TkwOwnerInvite> createState() => _TkwOwnerInviteState();
}

class _TkwOwnerInviteState extends State<TkwOwnerInvite> {
  bool busy = false;
  bool submitted = false;
  String? error;

  Future<void> _begin() async {
    final nav = Navigator.of(context);
    final id = widget.inviteId;
    var brokerName = widget.brokerName;
    if (id != null) {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        final result = await Tk2Store.instance.sync!.claimInvite(id, TkwSession.instance.name);
        brokerName = result.brokerName;
        if (result.submitted) {
          if (!mounted) return;
          nav.popUntil((r) => r.isFirst);
          setState(() {
            busy = false;
            submitted = true;
          });
          return;
        }
      } catch (_) {
        if (!mounted) return;
        nav.popUntil((r) => r.isFirst);
        setState(() {
          busy = false;
          error = 'Use the phone number or email your broker sent this link to.';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => busy = false);
    nav.popUntil((r) => r.isFirst);
    nav.push(_route(TkwOwnerCount(brokerName: brokerName)));
  }

  void _start() {
    if (TkwSession.instance.signedIn && error == null) {
      _begin();
      return;
    }
    Navigator.of(context).push(_route(TkwSignUp(
      allowEmail: true,
      subtitle: 'Your name, and your phone or email. We send a code to check it is you.',
      onDone: _begin,
    )));
  }

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: const ApprovedLoginHero(),
    footer: PrimaryButton(
      label: 'Start',
      icon: Icons.chevron_right,
      loading: busy,
      onPressed: busy || submitted ? null : _start,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add your house', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.brokerName.isEmpty ? 'Your broker' : widget.brokerName,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
              TextSpan(
                text: widget.houseName.isEmpty
                    ? ' asked you to add your house on TrustKeyper. It takes about 5 minutes.'
                    : ' asked you to add ${widget.houseName} on TrustKeyper. It takes about 5 minutes.',
              ),
            ],
          ),
          style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
        ),
        if (error != null) ...[const SizedBox(height: 12), OnbBanner(error!, kind: 'need', icon: Icons.error_outline)],
        if (submitted) ...[const SizedBox(height: 12), const OnbBanner('Your house details were already sent.', kind: 'ok', icon: Icons.check_circle_outline)],
        const SizedBox(height: 18),
        for (final (icon, title, sub) in const [
          (Icons.home_work_outlined, 'About the house', 'Address, rooms, size, furnishing'),
          (Icons.currency_rupee, 'Rent and who can rent', 'Rent, deposit, tenants, pets'),
          (Icons.event_available_outlined, 'Visits and photos', 'When people can come and see it'),
          (Icons.key_outlined, 'Keys', 'Who has them, for visits'),
        ]) ...[OnbRow(icon: icon, title: title, subtitle: sub, chevron: false), const SizedBox(height: 10)],
        const SizedBox(height: 4),
        const OnbBanner(
          'Your flat number, phone and key details are only for your broker and TrustKeyper. Tenants never see them.',
          kind: 'ok',
          icon: Icons.lock_outline,
        ),
      ],
    ),
  );
}

/// Same "How many owners?" question as the main app's owner flow, then "Are you one of them?".
class TkwOwnerCount extends StatefulWidget {
  const TkwOwnerCount({required this.brokerName, super.key});
  final String brokerName;

  @override
  State<TkwOwnerCount> createState() => _TkwOwnerCountState();
}

class _TkwOwnerCountState extends State<TkwOwnerCount> {
  int owners = 1;
  bool? me;
  bool bad = false;

  void _next() {
    if (me == null) return setState(() => bad = true);
    final store = Tk2Store.instance;
    Navigator.of(context).push(
      _route(
        BrokerPropertyScreen(
          repository: Tk2PropertyRepository(store),
          showStepLabel: false,
          askThings: false,
          firstStage: 3,
          initialName: 'My house',
          heading: 'Your house',
          doneLabel: 'Next: rent',
          onSelected: (BrokerProperty p) {
            TkwSession.instance.owner(p.id)
              ..['owners'] = owners
              ..['ownerIsMe'] = me;
            TkwSession.instance.save();
            Navigator.of(context).push(
              _route(
                Tk2ListingForm(
                  store: store,
                  id: p.id,
                  isNew: true,
                  ownerMode: true,
                  onDone: () => Navigator.of(context).push(_route(TkwOwnerKeys(houseId: p.id, brokerName: widget.brokerName))),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Owner details',
    subtitle: 'Who is giving the house on rent?',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Next', icon: Icons.chevron_right, onPressed: _next)],
    children: [
      const SizedBox(height: 8),
      Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
          child: const Icon(Icons.people_outline, size: 36, color: AppColors.primaryDark),
        ),
      ),
      const SizedBox(height: 16),
      const Center(
        child: Text(
          'How many owners?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
        ),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text('Everyone whose name is on the house documents.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
      ),
      const SizedBox(height: 18),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _round(Icons.remove, owners > 1 ? () => setState(() => owners--) : null),
          Container(
            width: 96,
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primary, width: 1.6),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                '$owners',
                key: ValueKey(owners),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
            ),
          ),
          _round(Icons.add, owners < 9 ? () => setState(() => owners++) : null, filled: true),
        ],
      ),
      const SizedBox(height: 32),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(bad ? 12 : 0),
        decoration: BoxDecoration(
          color: bad ? AppColors.errorSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: bad ? AppColors.error : Colors.transparent, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              owners == 1 ? 'Are you the owner?' : 'Are you one of the owners?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final v in const [true, false]) ...[
                  Expanded(
                    child: _choice(
                      v ? 'Yes' : 'No',
                      me == v,
                      () => setState(() {
                        me = v;
                        bad = false;
                      }),
                    ),
                  ),
                  if (v) const SizedBox(width: 12),
                ],
              ],
            ),
            if (bad) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: AppColors.error),
                  SizedBox(width: 6),
                  Text('Choose one', style: TextStyle(fontSize: 14.5, color: AppColors.error)),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _round(IconData icon, VoidCallback? onTap, {bool filled = false}) => Material(
    color: onTap == null ? const Color(0xFFE6EAF0) : (filled ? AppColors.primary : const Color(0xFFE6EAF0)),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: 56, height: 56, child: Icon(icon, color: filled && onTap != null ? Colors.white : AppColors.muted)),
    ),
  );

  Widget _choice(String label, bool on, VoidCallback onTap) => Material(
    color: on ? AppColors.primary : AppColors.surfaceMuted,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.heading),
          ),
        ),
      ),
    ),
  );
}

/// Keys: who has them, and how we get them when a visit is booked.
/// (Documents are asked later, when a tenant blocks the house.)
class TkwOwnerKeys extends StatefulWidget {
  const TkwOwnerKeys({required this.houseId, required this.brokerName, super.key});
  final String houseId;
  final String brokerName;

  @override
  State<TkwOwnerKeys> createState() => _TkwOwnerKeysState();
}

class _TkwOwnerKeysState extends State<TkwOwnerKeys> {
  static const choices = [
    ('Me', 'tk2-key-me'),
    ('Another property broker', 'tk2-key-broker'),
    ('Security', 'tk2-key-security'),
    ('Someone else', 'tk2-key-other'),
  ];
  late final Map<String, dynamic> a = TkwSession.instance.owner(widget.houseId);
  late String? who = switch (a['keys'] as String?) {
    'Another broker' => 'Another property broker',
    final v => v,
  };
  late final name = TextEditingController(text: a['keyName'] as String? ?? '');
  late final phone = TextEditingController(text: a['keyPhone'] as String? ?? '');
  late final note = TextEditingController(text: a['keyNote'] as String? ?? '');
  String dial = '+91';
  final Set<String> bad = {};
  bool sending = false;
  String? sendError;

  @override
  void dispose() {
    for (final c in [name, phone, note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _needsPerson => who != null && who != 'Me';

  void _pick(String c) => setState(() {
    who = c;
    bad.clear();
  });

  Future<void> _send() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    bad
      ..clear()
      ..addAll({
        if (who == null) 'who',
        if (who == 'Me' && note.text.trim().isEmpty) 'note',
        if (_needsPerson && name.text.trim().length < 2) 'name',
        if (_needsPerson && !PhoneCountry.valid(dial, digits)) 'phone',
      });
    if (bad.isNotEmpty) return setState(() {});
    a
      ..['keys'] = who
      ..['keyName'] = _needsPerson ? name.text.trim() : ''
      ..['keyPhone'] = _needsPerson ? PhoneCountry.format(dial, digits) : ''
      ..['keyNote'] = note.text.trim();
    setState(() {
      sending = true;
      sendError = null;
    });
    final session = TkwSession.instance;
    try {
      await session.save();
      await Tk2Store.instance.sync?.submitOwnerListing(widget.houseId, a, name: session.name, contact: session.contact);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        sending = false;
        sendError = 'We could not send the house details. Try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => sending = false);
    Navigator.of(context).push(_route(TkwOwnerDone(houseId: widget.houseId, brokerName: widget.brokerName)));
  }

  /// Fields for the picked option, shown inside its own card.
  List<Widget> _details(String c) => switch (c) {
    'Me' => [
      OnbTextField(
        label: 'How do we collect the keys?',
        controller: note,
        maxLines: 3,
        capitalization: TextCapitalization.sentences,
        error: bad.contains('note') ? 'Tell us how to collect the keys' : null,
        onChanged: (_) => setState(() => bad.remove('note')),
      ),
      const SizedBox(height: 6),
      const Text('When a visit is booked. For example: call me 1 hour before, I live nearby.', style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
    ],
    _ => [
      OnbTextField(
        label: switch (c) {
          'Another property broker' => "Broker's name",
          'Security' => "Security guard's name",
          _ => 'Their name',
        },
        controller: name,
        capitalization: TextCapitalization.words,
        error: bad.contains('name') ? 'Type their name' : null,
        onChanged: (_) => setState(() => bad.remove('name')),
      ),
      const SizedBox(height: 12),
      ApprovedPhoneField(
        controller: phone,
        dialCode: dial,
        onDialCodeChanged: (d) => setState(() => dial = d),
        error: bad.contains('phone') ? (dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number') : null,
      ),
      if (c == 'Security' || c == 'Someone else') ...[
        const SizedBox(height: 12),
        OnbTextField(label: 'How to collect the keys (optional)', controller: note, maxLines: 3, capitalization: TextCapitalization.sentences),
      ],
    ],
  };

  Widget _option(String c, String svg) {
    final on = who == c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: on ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? AppColors.primary : AppColors.border, width: on ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/design/$svg.svg',
                      width: 24,
                      height: 24,
                      colorFilter: const ColorFilter.mode(AppColors.primaryDark, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.heading),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: on ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.check_circle, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: on
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _details(c)),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Keys',
    subtitle: 'Who has the keys? We need them when someone visits.',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [
      if (sendError != null) OnbBanner(sendError!, kind: 'need', icon: Icons.error_outline),
      PrimaryButton(label: 'Send to ${widget.brokerName.isEmpty ? 'broker' : widget.brokerName.split(' ').first}', icon: Icons.chevron_right, loading: sending, onPressed: sending ? null : _send),
    ],
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(bad.contains('who') ? 12 : 0),
        decoration: BoxDecoration(
          color: bad.contains('who') ? AppColors.errorSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: bad.contains('who') ? AppColors.error : Colors.transparent, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (c, svg) in choices) _option(c, svg),
            if (bad.contains('who')) const Text('Choose who has the keys', style: TextStyle(fontSize: 14.5, color: AppColors.error)),
          ],
        ),
      ),
      const SizedBox(height: 6),
      const OnbBanner(
        'Documents like Aadhaar and bank details are asked later, only when a tenant blocks your house.',
        kind: 'info',
        icon: Icons.description_outlined,
      ),
    ],
  );
}

/// Owner is done. "Done" closes the tab; documents can be added now if they like.
class TkwOwnerDone extends StatefulWidget {
  const TkwOwnerDone({required this.houseId, required this.brokerName, super.key});
  final String houseId;
  final String brokerName;

  @override
  State<TkwOwnerDone> createState() => _TkwOwnerDoneState();
}

class _TkwOwnerDoneState extends State<TkwOwnerDone> {
  bool closeTried = false;

  Map<String, dynamic> get a => TkwSession.instance.owner(widget.houseId);

  Future<void> _done() async {
    tkwCloseTab();
    // Browsers only close tabs a script opened; otherwise say it is safe to close.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => closeTried = true);
  }

  @override
  Widget build(BuildContext context) {
    final docs = a['docsSent'] == true;
    return OnbPage(
      title: 'All done',
      showBack: false,
      footer: [
        PrimaryButton(label: 'Done', onPressed: _done),
        if (!docs && !Tk2Cloud.on) ...[
          const SizedBox(height: 10),
          OnbSecondaryButton(
            label: 'Upload documents now',
            onPressed: () async {
              await Navigator.of(context).push(_route(TkwOwnerDocs(houseId: widget.houseId, brokerName: widget.brokerName)));
              if (mounted) setState(() {});
            },
          ),
        ],
      ],
      children: [
        OnbCentered(
          icon: Icons.check,
          kind: 'ok',
          title: 'Thank you, ${TkwSession.instance.name.split(' ').first}!',
          message: '${widget.brokerName.isEmpty ? 'Your broker' : widget.brokerName} can now share your house with tenants.'
              '${Tk2Cloud.on ? '' : ' We message you on WhatsApp when someone books a visit.'}',
        ),
        const SizedBox(height: 24),
        if (!Tk2Cloud.on) docs
            ? const OnbBanner(
                'Documents received. We use them to make the rent agreement when a tenant blocks your house.',
                kind: 'ok',
                icon: Icons.check_circle_outline,
              )
            : const OnbBanner(
                'When a tenant blocks your house, we need a few documents for the rent agreement. Add them now to save time later, or we will ask then.',
                kind: 'info',
                icon: Icons.description_outlined,
              ),
        if (closeTried) ...[
          const SizedBox(height: 12),
          const OnbBanner('You are all set. You can close this tab now.', kind: 'ok', icon: Icons.check_circle_outline),
        ],
      ],
    );
  }
}

/// Documents for the rent agreement: Aadhaar of every owner, bank, old agreement.
class TkwOwnerDocs extends StatefulWidget {
  const TkwOwnerDocs({required this.houseId, required this.brokerName, super.key});
  final String houseId;
  final String brokerName;

  @override
  State<TkwOwnerDocs> createState() => _TkwOwnerDocsState();
}

class _TkwOwnerDocsState extends State<TkwOwnerDocs> {
  late final Map<String, dynamic> a = TkwSession.instance.owner(widget.houseId);
  late final int owners = (a['owners'] as int? ?? 1).clamp(1, 9);
  final Set<String> bad = {};

  Future<void> _upload(String k) async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f == null) return;
      a[k] = true;
      bad.remove(k);
      await TkwSession.instance.save();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _send() {
    bad
      ..clear()
      ..addAll({
        for (var i = 0; i < owners; i++)
          if (a['aadhaar$i'] != true) 'aadhaar$i',
        if (a['bank'] != true) 'bank',
      });
    if (bad.isNotEmpty) return setState(() {});
    a['docsSent'] = true;
    a['docsSentAt'] = DateTime.now().millisecondsSinceEpoch;
    TkwSession.instance.save();
    Navigator.of(context).pop();
  }

  Widget _row(String k, String title, String sub) {
    final has = a[k] == true;
    final need = bad.contains(k);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OnbRow(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Documents',
    subtitle: 'For the rent agreement. Only your broker and TrustKeyper see these.',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Send documents', icon: Icons.chevron_right, onPressed: _send)],
    children: [
      for (var i = 0; i < owners; i++) _row('aadhaar$i', owners == 1 ? 'Aadhaar card' : 'Aadhaar card · owner ${i + 1}', 'Front and back'),
      _row('bank', 'Bank details for the rent', 'A cancelled cheque or passbook page'),
      _row('oldAgreement', 'Old or current rent agreement', 'Optional · only if it was rented before'),
    ],
  );
}
