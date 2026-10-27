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
        message: 'Owner sends the documents. We read them.',
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

/// Ask the owner for papers: how many owners → each owner → check → sent.
/// Same flow as the rent agreement ("How many owners?", then Owner 1, Owner 2...).
class OnboardNewScreen extends StatefulWidget {
  const OnboardNewScreen({super.key});

  @override
  State<OnboardNewScreen> createState() => _OnboardNewScreenState();
}

class _OwnerForm {
  /// null until the broker picks: 'email' or 'whatsapp'.
  String? channel;
  String? channelError;
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  String? nameError;
  String? phoneError;
  String? emailError;
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
  }
}

class _OnboardNewScreenState extends State<OnboardNewScreen> {
  final _store = PropertyOnboardingStore.instance;
  final List<_OwnerForm> _owners = [_OwnerForm()];
  int _step = 0; // 0 how many · 1 owner details · 2 check · 3 sent
  int _person = 0;
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
    for (final o in _owners) {
      o.dispose();
    }
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  // Set on 'Same owner, new house': we reuse the ID proofs from that request.
  PropertyOnboarding? _carryFrom;

  _OwnerForm get _first => _owners.first;
  // How we ask owner 1 for papers: email (best) or WhatsApp.
  String get _channel => _first.channel ?? 'email';
  String get _firstName => _first.name.text.trim().split(' ').first;
  String get _contact => _channel == 'email' ? _first.email.text.trim() : _first.phone.text.trim();
  bool get _dirty => _step < 3 && _owners.any((o) => o.name.text.trim().isNotEmpty || o.phone.text.trim().isNotEmpty || o.email.text.trim().isNotEmpty);

  void _resize(int change) {
    setState(() {
      if (change > 0 && _owners.length < 10) _owners.add(_OwnerForm());
      if (change < 0 && _owners.length > 1) _owners.removeLast().dispose();
    });
  }

  /// Checks the owner shown now: name, how to reach, and that one contact.
  bool _validate(int index) {
    final o = _owners[index];
    final name = o.name.text.trim();
    final phone = o.phone.text.trim();
    final email = o.email.text.trim();
    setState(() {
      o.nameError = name.length < 2 ? 'Type the owner name' : null;
      o.channelError = o.channel == null ? 'Pick one' : null;
      o.phoneError = o.channel == 'whatsapp' && phone.length != 10 ? 'Type the 10 digit phone number' : null;
      o.emailError = o.channel == 'email' && !_emailPattern.hasMatch(email) ? 'This email looks wrong. Check the @ and the dot.' : null;
      // The same person cannot be added twice.
      for (var i = 0; i < _owners.length; i++) {
        if (i == index) continue;
        final other = _owners[i];
        if (o.channel == 'email' && o.emailError == null && other.channel == 'email' && other.email.text.trim().toLowerCase() == email.toLowerCase()) {
          o.emailError = 'Already added as Owner ${i + 1}. Use a different email.';
        }
        if (o.channel == 'whatsapp' && o.phoneError == null && other.channel == 'whatsapp' && other.phone.text.trim() == phone) {
          o.phoneError = 'Already added as Owner ${i + 1}. Use a different number.';
        }
        if (o.nameError == null && other.name.text.trim().toLowerCase() == name.toLowerCase()) {
          o.nameError = 'Owner ${i + 1} has the same name. Add the full name.';
        }
      }
    });
    return o.nameError == null && o.channelError == null && o.phoneError == null && o.emailError == null;
  }

  Future<void> _next() async {
    if (_step == 0) {
      setState(() {
        _step = 1;
        _person = 0;
      });
    } else if (_step == 1) {
      if (!_validate(_person)) return;
      if (_person == 0) {
        // Is this owner already registered (same phone/email, or same name)?
        final lower = _first.name.text.trim().toLowerCase();
        final key = _contact;
        final matches = _store.items
            .where((i) => i.contact == key || i.ownerName.trim().toLowerCase() == lower)
            .toList();
        _carryFrom = null;
        if (matches.isNotEmpty) {
          final same = await _askSameOwner(matches.last, matches.length);
          if (!mounted) return;
          if (same == null) return; // closed the sheet: stay on this page
          if (same) {
            // Same owner, new house: keep the saved name and contact, and reuse
            // the ID proofs (Aadhaar, phone, email) from the earlier request.
            final saved = matches.last;
            _carryFrom = matches.lastWhere(
              (m) => m.paper(PaperKeys.aadhaar).status == PaperStatus.approved,
              orElse: () => saved,
            );
            setState(() {
              _first.name.text = saved.ownerName;
              _first.channel = saved.channel;
              if (saved.channel == 'email') {
                _first.email.text = saved.contact;
              } else {
                _first.phone.text = saved.contact;
              }
            });
          }
          // A new owner: carry on with what was typed. Nothing is copied
          // except the phone or email given now.
        }
      }
      setState(() {
        if (_person + 1 < _owners.length) {
          _person++;
        } else {
          _step = 2;
        }
      });
    } else if (_step == 2) {
      await _send();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else if (_step == 1) {
      setState(() {
        if (_person > 0) {
          _person--;
        } else {
          _step = 0;
        }
      });
    } else if (_step == 2) {
      setState(() {
        _step = 1;
        _person = _owners.length - 1;
      });
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
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 8),
                child: Text('A different person. We start fresh. Only the phone or email you typed is used.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              ),
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
      final contact = _channel == 'email' ? _first.email.text.trim() : _first.phone.text.trim();
      final others = [
        for (final o in _owners.skip(1))
          CoOwner(
            name: o.name.text.trim(),
            channel: o.channel ?? 'email',
            contact: o.channel == 'whatsapp' ? o.phone.text.trim() : o.email.text.trim(),
          ),
      ];
      final created = await _store.create(
        ownerName: _first.name.text.trim(),
        channel: _channel,
        contact: contact,
        coOwners: others,
        carryFrom: _carryFrom,
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

  /// Back + Next > bar, same as the rent agreement.
  List<Widget> _bar(String label, {VoidCallback? onNext, bool loading = false}) => [
    Row(
      children: [
        SizedBox(
          width: 72,
          child: TextButton(
            onPressed: _back,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left, size: 20),
                SizedBox(width: 6),
                Flexible(child: Text('Back', maxLines: 1, style: TextStyle(fontSize: 17))),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(label: label, icon: Icons.chevron_right, loading: loading, onPressed: onNext ?? _next),
        ),
      ],
    ),
  ];

  Widget _count() => Padding(
    padding: const EdgeInsets.only(top: 60, bottom: 40),
    child: Column(
      children: [
        const CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.primarySoft,
          child: Icon(Icons.people_outline, size: 40, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 24),
        const Text('How many owners?', style: TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600, color: AppColors.heading)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _owners.length > 1 ? () => _resize(-1) : null,
              tooltip: 'Remove owner',
              icon: const Icon(Icons.remove),
              iconSize: 30,
            ),
            const SizedBox(width: 18),
            Container(
              width: 100,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_owners.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.heading)),
            ),
            const SizedBox(width: 18),
            IconButton.filled(
              onPressed: _owners.length < 10 ? () => _resize(1) : null,
              tooltip: 'Add owner',
              icon: const Icon(Icons.add),
              iconSize: 30,
            ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _person_() {
    final o = _owners[_person];
    return [
      if (_owners.length > 1) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _owners.length; i++)
              ChoiceChip(
                label: Text('Owner ${i + 1}${i == _person ? ' of ${_owners.length}' : ''}'),
                selected: _person == i,
                onSelected: (_) {
                  if (i < _person || _validate(_person)) setState(() => _person = i);
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
      Text('Owner ${_person + 1} details', style: const TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w600, color: AppColors.heading)),
      const SizedBox(height: 26),
      OnbTextField(label: 'Full name *', controller: o.name, error: o.nameError, capitalization: TextCapitalization.words, onChanged: (_) => setState(() => o.nameError = null)),
      const SizedBox(height: 26),
      Text(_person == 0 ? 'How do we ask for the documents?' : 'How do we reach this owner?', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _ChannelChip(label: 'Email · best', icon: Icons.mail_outline, selected: o.channel == 'email', onTap: () => setState(() { o.channel = 'email'; o.channelError = null; }))),
          const SizedBox(width: 10),
          Expanded(child: _ChannelChip(label: 'WhatsApp', icon: Icons.chat_bubble_outline, selected: o.channel == 'whatsapp', onTap: () => setState(() { o.channel = 'whatsapp'; o.channelError = null; }))),
        ],
      ),
      if (o.channelError != null)
        Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(o.channelError!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
      // The box appears only after a choice, and only for that choice.
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: o.channel == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  key: ValueKey('contact-$_person-${o.channel}'),
                  padding: const EdgeInsets.only(top: 26),
                  child: o.channel == 'email'
                      ? OnbTextField(
                          label: 'Email Address',
                          controller: o.email,
                          error: o.emailError,
                          keyboard: TextInputType.emailAddress,
                          formatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                          onChanged: (_) => setState(() => o.emailError = null),
                        )
                      : OnbTextField(
                          label: 'Mobile number',
                          controller: o.phone,
                          error: o.phoneError,
                          keyboard: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                          prefix: 'IN +91 ',
                          onChanged: (_) => setState(() => o.phoneError = null),
                        ),
                ),
        ),
      ),
    ];
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
          title: 'Owner details',
          subtitle: 'Who is giving the property on rent?',
          onBack: _back,
          footer: _bar('Next'),
          children: [_count()],
        ),
        1 => OnbPage(
          title: 'Owner details',
          subtitle: 'Who is giving the property on rent?',
          onBack: _back,
          footer: _bar(_person + 1 < _owners.length ? 'Next: Owner ${_person + 2}' : 'Next'),
          children: _person_(),
        ),
        2 => OnbPage(
          title: 'We will ask for these',
          subtitle: 'The owner gets this list.',
          onBack: _back,
          footer: [
            if (_sendError != null) ...[
              OnbBanner(_sendError!, kind: 'need', icon: Icons.error_outline),
              const SizedBox(height: 10),
            ],
            ..._bar(_sendError != null ? 'Try again' : 'Send to $_firstName', loading: _sending),
          ],
          children: [
            for (final text in const [
              'Full house address',
              'Aadhaar card of every owner',
              'Phone number of every owner (we have yours)',
              'Email of every owner (we have yours)',
              'Rent agreement of tenant now or before (if any)',
              'Rent and deposit you want',
              'Bank details for rent (cancelled cheque is best)',
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
                  ? 'We sent an email to $_contact. We will tell you when documents come.'
                  : 'We sent a WhatsApp message to +91 $_contact. We will tell you when documents come.',
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
