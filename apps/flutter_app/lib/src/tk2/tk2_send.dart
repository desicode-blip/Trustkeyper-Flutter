import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

/// Send a property to a tenant: pick someone added before or type a new
/// number → WhatsApp, text message or both → "Sent".
/// Demo build: the send is recorded; the backend delivers WhatsApp/SMS later.
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

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.store, required this.listing});
  final Tk2Store store;
  final Tk2Listing listing;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  int page = 0; // 0 who · 1 how · 2 sent
  int? picked; // index in contacts; -1 = new number
  final name = TextEditingController();
  final phone = TextEditingController();
  String dial = '+91';
  String? whoError;
  String? phoneError;
  bool whatsapp = true;
  bool sms = false;
  bool sending = false;

  late final contacts = widget.store.contacts;

  @override
  void initState() {
    super.initState();
    if (contacts.isEmpty) picked = -1;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  ({String name, String phone})? get _target {
    if (picked == null) return null;
    if (picked! >= 0) return contacts[picked!];
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    return (name: name.text.trim(), phone: PhoneCountry.format(dial, digits));
  }

  void _next() {
    if (picked == null) return setState(() => whoError = 'Choose a tenant or add a number');
    if (picked == -1) {
      final digits = phone.text.replaceAll(RegExp(r'\D'), '');
      if (!PhoneCountry.valid(dial, digits)) {
        return setState(() => phoneError = dial == '+91' ? 'Enter a valid 10-digit mobile number' : 'Enter a valid phone number');
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => page = 1);
  }

  Future<void> _send() async {
    final t = _target!;
    setState(() => sending = true);
    await widget.store.sendListing(widget.listing.id, name: t.name, phone: t.phone, whatsapp: whatsapp, sms: sms);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() {
      sending = false;
      page = 2;
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
            0 => _who(),
            1 => _how(),
            _ => _sent(),
          },
        ),
      ),
    ),
  );

  Widget _title(String title, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
      ),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
      const SizedBox(height: 16),
    ],
  );

  Widget _option({required bool on, required Widget leading, required String title, String? sub, required VoidCallback onTap}) => Padding(
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
                    if (sub != null) Text(sub, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                  ],
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
    ),
  );

  Widget _who() => SingleChildScrollView(
    key: const ValueKey('who'),
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Send to', widget.listing.publicTitle),
        for (var i = 0; i < contacts.length && i < 6; i++)
          _option(
            on: picked == i,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surfaceMuted,
              child: Text(
                tk2Initials(contacts[i].name.isEmpty ? '?' : contacts[i].name),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
            ),
            title: contacts[i].name.isEmpty ? contacts[i].phone : contacts[i].name,
            sub: contacts[i].name.isEmpty ? null : contacts[i].phone,
            onTap: () => setState(() {
              picked = i;
              whoError = null;
            }),
          ),
        _option(
          on: picked == -1,
          leading: const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.person_add_alt_1_outlined, color: AppColors.primaryDark),
          ),
          title: 'New number',
          sub: 'Send to someone new',
          onTap: () => setState(() {
            picked = -1;
            whoError = null;
          }),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: picked == -1
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    children: [
                      TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name (optional)', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 12),
                      ApprovedPhoneField(controller: phone, error: phoneError, dialCode: dial, onDialCodeChanged: (c) => setState(() => dial = c)),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (whoError != null) ...[const SizedBox(height: 8), Text(whoError!, style: const TextStyle(color: AppColors.error, fontSize: 14.5))],
        const SizedBox(height: 18),
        PrimaryButton(label: 'Next', icon: Icons.chevron_right, onPressed: _next),
      ],
    ),
  );

  Widget _how() {
    final t = _target!;
    return Padding(
      key: const ValueKey('how'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => setState(() => page = 0), icon: const Icon(Icons.chevron_left), tooltip: 'Back'),
              Expanded(child: _title('Send by', 'To ${t.name.isEmpty ? t.phone : '${t.name} · ${t.phone}'}')),
            ],
          ),
          _option(
            on: whatsapp && !sms,
            leading: tk2WhatsAppLogo(size: 28),
            title: 'WhatsApp',
            onTap: () => setState(() {
              whatsapp = true;
              sms = false;
            }),
          ),
          _option(
            on: sms && !whatsapp,
            leading: const Icon(Icons.sms_outlined, size: 28, color: AppColors.primaryDark),
            title: 'Text message',
            onTap: () => setState(() {
              whatsapp = false;
              sms = true;
            }),
          ),
          _option(
            on: whatsapp && sms,
            leading: const Icon(Icons.done_all, size: 28, color: AppColors.primaryDark),
            title: 'Both',
            sub: 'WhatsApp and text message',
            onTap: () => setState(() {
              whatsapp = true;
              sms = true;
            }),
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: 'Send', icon: Icons.send_rounded, loading: sending, onPressed: sending ? null : _send),
        ],
      ),
    );
  }

  Widget _sent() {
    final t = _target!;
    final how = whatsapp && sms
        ? 'WhatsApp and text message'
        : whatsapp
        ? 'WhatsApp'
        : 'text message';
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
