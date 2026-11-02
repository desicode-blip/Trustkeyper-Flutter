import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

/// Share a property with a tenant:
/// Recent people (tap one) or Add new (number + optional name)
/// → WhatsApp / Text message / Email, any mix (checkboxes) → "Sent".
/// Demo build: the send is recorded; the backend delivers the messages later.
Future<void> showTk2Send(BuildContext context, Tk2Store store, Tk2Listing l) async {
  final sentTo = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) => _SendSheet(store: store, listing: l),
  );
  if (sentTo != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('Sent to $sentTo')));
  }
}

typedef _Person = ({String name, String phone, String email});

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.store, required this.listing});
  final Tk2Store store;
  final Tk2Listing listing;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late final List<_Person> recent = widget.store.contacts.take(6).toList();

  /// who · new · how · sent
  late String page = recent.isEmpty ? 'new' : 'who';
  _Person? target;

  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  String dial = '+91';
  String? phoneError;
  String? howError;
  String? emailError;
  bool whatsapp = true;
  bool sms = false;
  bool byEmail = false;
  bool sending = false;

  static final _emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  void _go(String next) {
    FocusScope.of(context).unfocus();
    setState(() => page = next);
  }

  void _pick(_Person p) {
    target = p;
    email.text = p.email;
    howError = emailError = null;
    _go('how');
  }

  void _addNew() {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (!PhoneCountry.valid(dial, digits)) {
      return setState(() => phoneError = dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number');
    }
    _pick((name: name.text.trim(), phone: PhoneCountry.format(dial, digits), email: ''));
  }

  Future<void> _send() async {
    if (!whatsapp && !sms && !byEmail) return setState(() => howError = 'Tick at least one');
    if (byEmail && !_emailOk.hasMatch(email.text.trim())) return setState(() => emailError = 'Enter a valid email');
    final t = target!;
    setState(() => sending = true);
    await widget.store.sendListing(
      widget.listing.id,
      name: t.name,
      phone: t.phone,
      email: byEmail ? email.text.trim() : '',
      whatsapp: whatsapp,
      sms: sms,
      byEmail: byEmail,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      sending = false;
      page = 'sent';
    });
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (mounted) Navigator.pop(context, t.name.isEmpty ? t.phone : t.name);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: switch (page) {
            'who' => _who(),
            'new' => _new(),
            'how' => _how(),
            _ => _sent(),
          },
        ),
      ),
    ),
  );

  Widget _title(String title, String sub, {VoidCallback? onBack}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        if (onBack != null) ...[IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left), tooltip: 'Back'), const SizedBox(width: 4)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(fontSize: 12.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: AppColors.muted),
    ),
  );

  Widget _row({required Widget leading, required String title, String? sub, Widget? trailing, required VoidCallback onTap, bool on = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: on ? AppColors.primarySoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    ),
  );

  /// Recent people, then Add new.
  Widget _who() => SingleChildScrollView(
    key: const ValueKey('who'),
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Share with', widget.listing.publicTitle),
        _section('Recent'),
        for (final p in recent)
          _row(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surfaceMuted,
              child: Text(
                tk2Initials(p.name.isEmpty ? '?' : p.name),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
            ),
            title: p.name.isEmpty ? p.phone : p.name,
            sub: p.name.isEmpty ? null : p.phone,
            trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
            onTap: () => _pick(p),
          ),
        const SizedBox(height: 8),
        _row(
          leading: const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.person_add_alt_1_outlined, color: AppColors.primaryDark),
          ),
          title: 'Add new',
          sub: 'Share with someone new',
          trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
          onTap: () => _go('new'),
        ),
      ],
    ),
  );

  /// New person: number (required) and name (optional).
  Widget _new() => SingleChildScrollView(
    key: const ValueKey('new'),
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Add new', widget.listing.publicTitle, onBack: recent.isEmpty ? null : () => _go('who')),
        ApprovedPhoneField(controller: phone, error: phoneError, dialCode: dial, onDialCodeChanged: (c) => setState(() => dial = c)),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name (optional)', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 18),
        PrimaryButton(label: 'Next', icon: Icons.chevron_right, onPressed: _addNew),
      ],
    ),
  );

  Widget _check(bool on, Widget leading, String title, ValueChanged<bool> onChanged) => _row(
    on: on,
    leading: leading,
    title: title,
    trailing: IgnorePointer(
      child: Checkbox(value: on, onChanged: (_) {}),
    ),
    onTap: () => setState(() {
      onChanged(!on);
      howError = null;
    }),
  );

  /// WhatsApp / Text message / Email: tick any.
  Widget _how() {
    final t = target!;
    return SingleChildScrollView(
      key: const ValueKey('how'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Share by', 'To ${t.name.isEmpty ? t.phone : '${t.name} · ${t.phone}'}', onBack: () => _go(recent.contains(t) ? 'who' : 'new')),
          _check(whatsapp, tk2WhatsAppLogo(size: 28), 'WhatsApp', (v) => whatsapp = v),
          _check(sms, const Icon(Icons.sms_outlined, size: 28, color: AppColors.primaryDark), 'Text message', (v) => sms = v),
          _check(byEmail, const Icon(Icons.mail_outline, size: 28, color: AppColors.primaryDark), 'Email', (v) => byEmail = v),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: byEmail
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() => emailError = null),
                      decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.alternate_email), errorText: emailError),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (howError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(howError!, style: const TextStyle(color: AppColors.error, fontSize: 14.5)),
            ),
          const SizedBox(height: 8),
          PrimaryButton(label: 'Send', icon: Icons.send_rounded, loading: sending, onPressed: sending ? null : _send),
        ],
      ),
    );
  }

  Widget _sent() {
    final t = target!;
    final ways = [if (whatsapp) 'WhatsApp', if (sms) 'text message', if (byEmail) 'email'];
    final how = ways.length == 1 ? ways.single : '${ways.sublist(0, ways.length - 1).join(', ')} and ${ways.last}';
    return Padding(
      key: const ValueKey('sent'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Tk2SuccessTick(),
          const SizedBox(height: 16),
          const Text(
            'Sent!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.heading),
          ),
          const SizedBox(height: 4),
          Text(
            '${t.name.isEmpty ? t.phone : t.name} gets it on $how.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
