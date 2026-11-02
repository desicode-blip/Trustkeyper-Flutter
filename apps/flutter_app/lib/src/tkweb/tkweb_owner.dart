import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/broker/data/broker_property_repository.dart';
import '../features/broker/presentation/broker_property_screen.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_listing.dart';
import '../tk2/tk2_store.dart';
import 'tkweb_auth.dart';
import 'tkweb_session.dart';

Route<void> _route(Widget page) => MaterialPageRoute<void>(builder: (_) => page);

/// Owner opens the broker's invite (WhatsApp link): what we ask, then sign up.
class TkwOwnerInvite extends StatelessWidget {
  const TkwOwnerInvite({required this.brokerName, required this.houseName, super.key});
  final String brokerName;
  final String houseName;

  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: const ApprovedLoginHero(),
    footer: PrimaryButton(
      label: 'Start',
      icon: Icons.chevron_right,
      onPressed: () {
        final nav = Navigator.of(context);
        void begin() => nav.push(_route(TkwOwnerCount(brokerName: brokerName)));
        if (TkwSession.instance.signedIn) return begin();
        nav.push(
          _route(
            TkwSignUp(
              allowEmail: true,
              subtitle: 'Your name, and your phone or email. We send a code to check it is you.',
              onDone: () {
                nav.popUntil((r) => r.isFirst);
                begin();
              },
            ),
          ),
        );
      },
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
                text: brokerName.isEmpty ? 'Your broker' : brokerName,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
              TextSpan(text: houseName.isEmpty ? ' asked you to add your house on TrustKeyper. It takes about 5 minutes.' : ' asked you to add $houseName on TrustKeyper. It takes about 5 minutes.'),
            ],
          ),
          style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        for (final (icon, title, sub) in const [
          (Icons.home_work_outlined, 'About the house', 'Address, rooms, size, furnishing'),
          (Icons.currency_rupee, 'Rent and who can rent', 'Rent, deposit, tenants, pets'),
          (Icons.event_available_outlined, 'Visits and photos', 'When people can come and see it'),
          (Icons.key_outlined, 'Keys', 'Who has them, for visits'),
        ]) ...[OnbRow(icon: icon, title: title, subtitle: sub, chevron: false), const SizedBox(height: 10)],
        const SizedBox(height: 4),
        const OnbBanner('Your flat number, phone and key details are only for your broker and TrustKeyper. Tenants never see them.', kind: 'ok', icon: Icons.lock_outline),
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
        child: Text('Everyone whose name is on the house papers.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
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
/// (Papers are asked later, when a tenant blocks the house.)
class TkwOwnerKeys extends StatefulWidget {
  const TkwOwnerKeys({required this.houseId, required this.brokerName, super.key});
  final String houseId;
  final String brokerName;

  @override
  State<TkwOwnerKeys> createState() => _TkwOwnerKeysState();
}

class _TkwOwnerKeysState extends State<TkwOwnerKeys> {
  static const choices = ['Me', 'Another broker', 'Security', 'Someone else'];
  late final Map<String, dynamic> a = TkwSession.instance.owner(widget.houseId);
  late String? who = a['keys'] as String?;
  late final name = TextEditingController(text: a['keyName'] as String? ?? '');
  late final phone = TextEditingController(text: a['keyPhone'] as String? ?? '');
  late final note = TextEditingController(text: a['keyNote'] as String? ?? '');
  String dial = '+91';
  final Set<String> bad = {};

  @override
  void dispose() {
    for (final c in [name, phone, note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _needsPerson => who != null && who != 'Me';

  /// "Me": ask how we collect the keys for a visit.
  Future<void> _askHowFromMe() async {
    final draft = TextEditingController(text: note.text);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.of(sheet).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'How do we get the keys?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
            ),
            const SizedBox(height: 4),
            const Text(
              'When a visit is booked, how should the broker collect the keys from you?',
              style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            OnbTextField(label: 'For example: call me 1 hour before, I live nearby', controller: draft, maxLines: 3, capitalization: TextCapitalization.sentences),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Save', onPressed: () => Navigator.pop(sheet, draft.text.trim())),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      note.text = saved;
      bad.remove('note');
    });
  }

  void _pick(String c) {
    setState(() {
      who = c;
      bad.clear();
    });
    if (c == 'Me' && note.text.trim().isEmpty) _askHowFromMe();
  }

  void _send() {
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
    TkwSession.instance.save();
    Navigator.of(context).push(_route(TkwOwnerDone(brokerName: widget.brokerName)));
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Keys',
    subtitle: 'Who has the keys? We need them when someone visits.',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Send to ${widget.brokerName.isEmpty ? 'broker' : widget.brokerName.split(' ').first}', icon: Icons.chevron_right, onPressed: _send)],
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: who == c ? AppColors.primarySoft : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: who == c ? AppColors.primary : AppColors.border, width: who == c ? 1.6 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _pick(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(switch (c) {
                            'Me' => Icons.person_outline,
                            'Another broker' => Icons.handshake_outlined,
                            'Security' => Icons.shield_outlined,
                            _ => Icons.people_outline,
                          }, color: AppColors.primaryDark),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c,
                              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.heading),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: who == c ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: const Icon(Icons.check_circle, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (bad.contains('who')) const Text('Choose who has the keys', style: TextStyle(fontSize: 14.5, color: AppColors.error)),
          ],
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (who == 'Me') ...[
              const SizedBox(height: 6),
              OnbRow(
                icon: note.text.trim().isEmpty ? Icons.edit_note : Icons.check,
                title: 'How we get the keys from you',
                subtitle: note.text.trim().isEmpty ? (bad.contains('note') ? 'Tell us how to collect them' : 'Tap to tell us') : note.text.trim(),
                tone: note.text.trim().isNotEmpty
                    ? 'ok'
                    : bad.contains('note')
                    ? 'need'
                    : 'info',
                onTap: _askHowFromMe,
              ),
            ],
            if (_needsPerson) ...[
              const SizedBox(height: 8),
              Text(switch (who) {
                'Another broker' => 'The other broker',
                'Security' => 'The security guard',
                _ => 'The person with the keys',
              }, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
              const SizedBox(height: 10),
              OnbTextField(
                label: 'Name',
                controller: name,
                capitalization: TextCapitalization.words,
                error: bad.contains('name') ? 'Type their name' : null,
                onChanged: (_) => setState(() => bad.remove('name')),
              ),
              const SizedBox(height: 12),
              ApprovedPhoneField(
                controller: phone,
                dialCode: dial,
                onDialCodeChanged: (c) => setState(() => dial = c),
                error: bad.contains('phone') ? (dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number') : null,
              ),
              if (who == 'Security' || who == 'Someone else') ...[
                const SizedBox(height: 12),
                OnbTextField(
                  label: who == 'Security' ? 'How to collect the keys from security (optional)' : 'Anything we should know (optional)',
                  controller: note,
                  maxLines: 3,
                  capitalization: TextCapitalization.sentences,
                ),
              ],
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      const OnbBanner('Papers like Aadhaar and bank details are asked later, only when a tenant blocks your house.', kind: 'info', icon: Icons.description_outlined),
    ],
  );
}

class TkwOwnerDone extends StatelessWidget {
  const TkwOwnerDone({required this.brokerName, super.key});
  final String brokerName;

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'All done',
    showBack: false,
    footer: [OnbSecondaryButton(label: 'Back to start', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst))],
    children: [
      OnbCentered(
        icon: Icons.check,
        kind: 'ok',
        title: 'Thank you, ${TkwSession.instance.name.split(' ').first}!',
        message: '${brokerName.isEmpty ? 'Your broker' : brokerName} can now share your house with tenants. We message you on WhatsApp when someone books a visit.',
      ),
      const SizedBox(height: 24),
      const OnbBanner('When a tenant blocks your house, we ask for a few more details to make the rent agreement. You sign it online.', kind: 'info', icon: Icons.description_outlined),
    ],
  );
}
