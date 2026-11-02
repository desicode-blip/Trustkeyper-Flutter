import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
          (Icons.description_outlined, 'Papers', 'Aadhaar, old agreement, bank, keys'),
        ]) ...[OnbRow(icon: icon, title: title, subtitle: sub, chevron: false), const SizedBox(height: 10)],
        const SizedBox(height: 4),
        const OnbBanner('Your flat number, phone and papers are only for your broker and TrustKeyper. Tenants never see them.', kind: 'ok', icon: Icons.lock_outline),
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
            final answers = TkwSession.instance.owner(p.id)
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
                  onDone: () => Navigator.of(context).push(_route(TkwOwnerPapers(houseId: p.id, owners: answers['owners'] as int, brokerName: widget.brokerName))),
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

/// Papers in the agreed order: Aadhaar of every owner → old/current agreement → bank → keys.
class TkwOwnerPapers extends StatefulWidget {
  const TkwOwnerPapers({required this.houseId, required this.owners, required this.brokerName, super.key});
  final String houseId;
  final int owners;
  final String brokerName;

  @override
  State<TkwOwnerPapers> createState() => _TkwOwnerPapersState();
}

class _TkwOwnerPapersState extends State<TkwOwnerPapers> {
  late final Map<String, dynamic> a = TkwSession.instance.owner(widget.houseId);
  final keyName = TextEditingController();
  final keyPhone = TextEditingController();
  final Set<String> bad = {};

  @override
  void dispose() {
    keyName.dispose();
    keyPhone.dispose();
    super.dispose();
  }

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
        for (var i = 0; i < widget.owners; i++)
          if (a['aadhaar$i'] != true) 'aadhaar$i',
        if (a['bank'] != true) 'bank',
        if (a['keys'] == null) 'keys',
        if (a['keys'] == 'Someone else' && keyName.text.trim().length < 2) 'keyName',
        if (a['keys'] == 'Someone else' && keyPhone.text.replaceAll(RegExp(r'\D'), '').length < 6) 'keyPhone',
      });
    if (bad.isNotEmpty) return setState(() {});
    a['keyName'] = keyName.text.trim();
    a['keyPhone'] = keyPhone.text.trim();
    TkwSession.instance.save();
    Navigator.of(context).push(_route(TkwOwnerDone(brokerName: widget.brokerName)));
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
    title: 'Papers',
    subtitle: 'Only your broker and TrustKeyper see these.',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Send to ${widget.brokerName.isEmpty ? 'broker' : widget.brokerName.split(' ').first}', icon: Icons.chevron_right, onPressed: _send)],
    children: [
      for (var i = 0; i < widget.owners; i++) _row('aadhaar$i', widget.owners == 1 ? 'Aadhaar card' : 'Aadhaar · owner ${i + 1}', 'Front and back'),
      _row('oldAgreement', 'Old or current rent agreement', 'Only if someone rented it before'),
      _row('bank', 'Bank for the rent', 'A cancelled cheque is best'),
      const SizedBox(height: 10),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(bad.contains('keys') ? 12 : 0),
        decoration: BoxDecoration(
          color: bad.contains('keys') ? AppColors.errorSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: bad.contains('keys') ? AppColors.error : Colors.transparent, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Who has the keys?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in const ['Me', 'The broker', 'Security', 'Someone else'])
                  ChoiceChip(
                    label: Text(k),
                    selected: a['keys'] == k,
                    onSelected: (_) => setState(() {
                      a['keys'] = k;
                      bad.remove('keys');
                    }),
                  ),
              ],
            ),
            if (bad.contains('keys')) ...[const SizedBox(height: 8), const Text('Choose who has the keys', style: TextStyle(fontSize: 14.5, color: AppColors.error))],
          ],
        ),
      ),
      if (a['keys'] == 'Someone else') ...[
        const SizedBox(height: 14),
        OnbTextField(label: 'Their name', controller: keyName, capitalization: TextCapitalization.words, error: bad.contains('keyName') ? 'Type their name' : null),
        const SizedBox(height: 12),
        OnbTextField(label: 'Their phone', controller: keyPhone, keyboard: TextInputType.phone, error: bad.contains('keyPhone') ? 'Type their phone number' : null),
      ],
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
