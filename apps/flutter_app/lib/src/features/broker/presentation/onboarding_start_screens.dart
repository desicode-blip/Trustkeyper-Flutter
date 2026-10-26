import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/property_onboarding.dart';
import 'onboarding_widgets.dart';

/// First screen of "Onboard property": only two choices.
class OnboardChooseScreen extends StatelessWidget {
  const OnboardChooseScreen({super.key});

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Onboard property',
    subtitle: 'Add a house you will manage.',
    footer: [
      _CallRow(),
    ],
    children: [
      _BigTile(
        icon: Icons.send_outlined,
        title: 'Send link to owner',
        message: 'Owner sends the papers. We read them.',
        badge: 'Easiest · email or WhatsApp',
        onTap: () => context.push('/broker/property/new'),
      ),
      const SizedBox(height: 14),
      _BigTile(
        icon: Icons.edit_outlined,
        title: 'Add manually',
        message: 'You type the house details yourself.',
        badge: 'Takes longer',
        muted: true,
        onTap: () => context.push('/broker/property/manual'),
      ),
    ],
  );
}

class _CallRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    borderRadius: BorderRadius.circular(26),
    child: InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => launchUrl(Uri.parse(kHelpPhone)),
      child: const SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_outlined, size: 20, color: AppColors.body),
            SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Not sure? '),
                  TextSpan(text: 'Call us', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w500)),
                  TextSpan(text: ' – we will help'),
                ],
              ),
              style: TextStyle(fontSize: 16, color: AppColors.body),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.icon,
    required this.title,
    required this.message,
    required this.badge,
    required this.onTap,
    this.muted = false,
  });
  final IconData icon;
  final String title;
  final String message;
  final String badge;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(24),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 21, height: 26 / 21, fontWeight: FontWeight.w700, color: AppColors.heading)),
                  const SizedBox(height: 2),
                  Text(message, style: const TextStyle(fontSize: 15, height: 20 / 15, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  OnbPill(badge, muted ? 'mute' : 'info'),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// Ask the owner for papers: owner → other owners → check → sent.
class OnboardNewScreen extends StatefulWidget {
  const OnboardNewScreen({super.key});

  @override
  State<OnboardNewScreen> createState() => _OnboardNewScreenState();
}

class _OnboardNewScreenState extends State<OnboardNewScreen> {
  final _store = PropertyOnboardingStore.instance;
  final _name = TextEditingController();
  final _contact = TextEditingController();
  int _step = 0;
  String _channel = 'email';
  final List<({String name, String channel, String contact})> _others = [];
  // Adding a second, third... owner uses the same form on its own page.
  bool _adding = false;
  final _oName = TextEditingController();
  final _oContact = TextEditingController();
  String _oChannel = 'email';
  String? _oNameError;
  String? _oContactError;
  String? _nameError;
  String? _contactError;
  String? _sendError;
  bool _sending = false;
  String? _createdId;

  @override
  void initState() {
    super.initState();
    _store.load();
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _oName.dispose();
    _oContact.dispose();
    super.dispose();
  }

  bool get _dirty => _step < 3 && (_name.text.trim().isNotEmpty || _contact.text.trim().isNotEmpty);
  String get _firstName => _name.text.trim().split(' ').first;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  Future<void> _next() async {
    if (_step == 0) {
      final name = _name.text.trim();
      final contact = _contact.text.trim();
      final digits = contact.replaceAll(RegExp(r'\D'), '');
      setState(() {
        _nameError = name.length < 2 ? 'Type the owner name' : null;
        _contactError = _channel == 'email'
            ? (_emailPattern.hasMatch(contact) ? null : 'This email looks wrong. Check the @ and the dot.')
            : (digits.length == 10 ? null : 'Type the 10 digit phone number');
      });
      if (_nameError != null || _contactError != null) return;
      // Is this owner already registered (same phone/email, or same name)?
      final key = _channel == 'email' ? contact : digits;
      final lower = name.toLowerCase();
      final matches = _store.items
          .where((i) => i.contact == key || i.ownerName.trim().toLowerCase() == lower)
          .toList();
      if (matches.isNotEmpty) {
        final same = await _askSameOwner(matches.last, matches.length);
        if (!mounted) return;
        if (same == null) return; // closed the sheet: stay and edit
        if (!same) {
          // A new person: stay on this page so the broker can change the details.
          return;
        }
        // Same owner, another house: keep their saved name and contact.
        final saved = matches.last;
        setState(() {
          _name.text = saved.ownerName;
          _channel = saved.channel;
          _contact.text = saved.contact;
        });
      }
      setState(() => _step = 1);
    } else if (_step == 1) {
      setState(() => _step = 2);
    } else if (_step == 2) {
      await _send();
    }
  }

  /// true = same owner (new house) · false = a different person · null = closed.
  Future<bool?> _askSameOwner(PropertyOnboarding saved, int houses) {
    final initial = saved.ownerName.trim().isEmpty ? '?' : saved.ownerName.trim()[0].toUpperCase();
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We know this owner',
                style: TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
              const SizedBox(height: 6),
              const Text(
                'Someone with this name or number is already with you.',
                style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                      child: Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(saved.ownerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
                          Text(saved.contactText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                          Text(houses == 1 ? '1 house with you' : '$houses houses with you', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Same owner, new house', onPressed: () => Navigator.pop(sheet, true)),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text('We keep the same name and number.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              ),
              OnbSecondaryButton(label: 'No, a new owner', onPressed: () => Navigator.pop(sheet, false)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final contact = _channel == 'email' ? _contact.text.trim() : _contact.text.replaceAll(RegExp(r'\D'), '');
      final created = await _store.create(
        ownerName: _name.text,
        channel: _channel,
        contact: contact,
        otherOwners: [for (final o in _others) '${o.name} · ${o.channel == 'email' ? o.contact : '+91 ${o.contact}'}'],
      );
      if (!mounted) return;
      setState(() {
        _createdId = created.id;
        _step = 3;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = 'We could not send. Nothing was lost.';
      });
    }
  }

  void _startAdding() => setState(() {
    _adding = true;
    _oName.clear();
    _oContact.clear();
    _oChannel = 'email';
    _oNameError = null;
    _oContactError = null;
  });

  void _saveOther() {
    final name = _oName.text.trim();
    final contact = _oContact.text.trim();
    final digits = contact.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _oNameError = name.length < 2 ? 'Type the owner name' : null;
      _oContactError = _oChannel == 'email'
          ? (_emailPattern.hasMatch(contact) ? null : 'This email looks wrong. Check the @ and the dot.')
          : (digits.length == 10 ? null : 'Type the 10 digit phone number');
    });
    if (_oNameError != null || _oContactError != null) return;
    setState(() {
      _others.add((name: name, channel: _oChannel, contact: _oChannel == 'email' ? contact : digits));
      _adding = false;
    });
  }

  /// The owner form: name, how to ask, email or phone. Used for every owner.
  List<Widget> _ownerForm({
    required TextEditingController name,
    required TextEditingController contact,
    required String channel,
    required String? nameError,
    required String? contactError,
    required void Function(String channel) onChannel,
  }) => [
    OnbTextField(label: 'Owner name', controller: name, error: nameError, capitalization: TextCapitalization.words),
    const SizedBox(height: 26),
    const Text('Ask for papers on', style: TextStyle(fontSize: 14, color: AppColors.muted)),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: _ChannelChip(label: 'Email · best', icon: Icons.mail_outline, selected: channel == 'email', onTap: () => onChannel('email'))),
        const SizedBox(width: 10),
        Expanded(child: _ChannelChip(label: 'WhatsApp', icon: Icons.chat_bubble_outline, selected: channel == 'whatsapp', onTap: () => onChannel('whatsapp'))),
      ],
    ),
    const SizedBox(height: 26),
    OnbTextField(
      key: ValueKey('contact-$channel-${identical(contact, _contact) ? 1 : 2}'),
      label: channel == 'email' ? 'Owner email' : 'Owner phone number',
      controller: contact,
      error: contactError,
      // Email: full letter keyboard with @ and dot. WhatsApp: numbers only.
      keyboard: channel == 'email' ? TextInputType.emailAddress : TextInputType.number,
      formatters: channel == 'email'
          ? [FilteringTextInputFormatter.deny(RegExp(r'\s'))]
          : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      prefix: channel == 'email' ? null : '+91 ',
    ),
    const SizedBox(height: 14),
    OnbBanner(
      channel == 'email'
          ? 'We send one short email. The owner replies with photos of the papers.'
          : 'We send a WhatsApp message. The owner sends the papers there.',
      icon: channel == 'email' ? Icons.mail_outline : Icons.chat_bubble_outline,
    ),
  ];

  Future<void> _leave() async {
    final leave = await onbConfirm(
      context,
      title: 'Leave without sending?',
      message: 'Nothing is sent. What you typed will be lost.',
      yes: 'Stay here',
      no: 'Leave',
    );
    if (!leave && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: switch (_step) {
        0 => OnbPage(
          title: 'Who is the owner?',
          stepLabel: 'Step 1 of 4 · Owner',
          progress: 1,
          showCall: true,
          onBack: () => Navigator.of(context).maybePop(),
          footer: [PrimaryButton(label: 'Next', onPressed: _next)],
          children: _ownerForm(
            name: _name,
            contact: _contact,
            channel: _channel,
            nameError: _nameError,
            contactError: _contactError,
            onChannel: (c) => setState(() {
              _channel = c;
              _contact.clear();
              _contactError = null;
            }),
          ),
        ),
        1 when _adding => OnbPage(
          title: 'Owner ${_others.length + 2}',
          onBack: () => setState(() => _adding = false),
          footer: [PrimaryButton(label: 'Save owner', onPressed: _saveOther)],
          children: _ownerForm(
            name: _oName,
            contact: _oContact,
            channel: _oChannel,
            nameError: _oNameError,
            contactError: _oContactError,
            onChannel: (c) => setState(() {
              _oChannel = c;
              _oContact.clear();
              _oContactError = null;
            }),
          ),
        ),
        1 => OnbPage(
          title: 'Is there another owner?',
          onBack: () => setState(() => _step = 0),
          footer: [PrimaryButton(label: 'Next', onPressed: _next)],
          children: [
            OnbCard(
              child: OnbRow(
                icon: Icons.check,
                tone: 'ok',
                title: _name.text.trim(),
                subtitle: 'Owner 1 · ${_channel == 'email' ? 'email' : 'WhatsApp'}',
                chevron: false,
                trailing: const OnbPill('Added', 'ok'),
              ),
            ),
            for (var i = 0; i < _others.length; i++) ...[
              const SizedBox(height: 10),
              OnbCard(
                child: OnbRow(
                  icon: Icons.check,
                  tone: 'ok',
                  title: _others[i].name,
                  subtitle: 'Owner ${i + 2} · ${_others[i].channel == 'email' ? 'email' : 'WhatsApp'}',
                  chevron: false,
                  trailing: IconButton(
                    tooltip: 'Remove ${_others[i].name}',
                    onPressed: () => setState(() => _others.removeAt(i)),
                    icon: const Icon(Icons.close, size: 20, color: AppColors.muted),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OnbSecondaryButton(label: '+ Add another owner', onPressed: _startAdding),
            const SizedBox(height: 14),
            const OnbBanner('Papers go to the first owner. He can send for everyone.', icon: Icons.groups_outlined),
          ],
        ),
        2 => OnbPage(
          title: 'We will ask for these',
          subtitle: 'The owner gets this list.',
          stepLabel: 'Step 3 of 4 · Check',
          progress: 3,
          showCall: true,
          onBack: () => setState(() => _step = 1),
          footer: [
            if (_sendError != null) ...[
              OnbBanner(_sendError!, kind: 'need', icon: Icons.error_outline),
              const SizedBox(height: 10),
            ],
            PrimaryButton(
              label: _sendError != null ? 'Try again' : 'Send to $_firstName',
              loading: _sending,
              onPressed: _send,
            ),
          ],
          children: [
            for (final text in const [
              'Aadhaar card of every owner',
              'Phone number of every owner',
              'Email of every owner',
              'Rent agreement of tenant now (if any)',
              'Rent and deposit you want',
              'Bank details for rent (cancelled cheque is best)',
              'Full house address',
              'Who has the keys: name and number',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 20, color: Color(0xFF2FA866)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: AppColors.body))),
                  ],
                ),
              ),
          ],
        ),
        _ => OnbPage(
          title: 'Request sent',
          showBack: false,
          footer: [
            PrimaryButton(
              label: 'See house status',
              onPressed: () => context.pushReplacement('/broker/onboarding/$_createdId'),
            ),
          ],
          children: [
            OnbCentered(
              icon: Icons.check,
              kind: 'ok',
              title: 'We asked $_firstName',
              message: _channel == 'email'
                  ? 'We sent an email to ${_contact.text.trim()}. We will tell you when papers come.'
                  : 'We sent a WhatsApp message to +91 ${_contact.text.trim()}. We will tell you when papers come.',
            ),
          ],
        ),
      },
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.primarySoft : Colors.white,
    shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.border)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primaryDark : AppColors.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w500 : FontWeight.w400, color: selected ? AppColors.primaryDark : AppColors.muted)),
          ],
        ),
      ),
    ),
  );
}
