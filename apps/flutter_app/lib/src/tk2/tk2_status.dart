import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_store.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String tk2DateOf(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Active / Not active switch for the property page header.
class Tk2ActiveToggle extends StatelessWidget {
  const Tk2ActiveToggle({required this.store, required this.listing, super.key});
  final Tk2Store store;
  final Tk2Listing listing;

  @override
  Widget build(BuildContext context) {
    final on = store.isActive(listing.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          on ? 'Active' : 'Not active',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: on ? AppColors.success : AppColors.muted),
        ),
        const SizedBox(width: 6),
        Switch.adaptive(
          key: const ValueKey('active-toggle'),
          value: on,
          activeTrackColor: AppColors.success,
          onChanged: (v) async {
            if (v) {
              await store.activate(listing.id);
              if (context.mounted) _toast(context, 'Active again. You can share it now.');
            } else {
              await showTk2Deactivate(context, store, listing);
            }
          },
        ),
      ],
    );
  }
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));

/// Why is it going off the market? Rented out → when did the rent start.
Future<void> showTk2Deactivate(BuildContext context, Tk2Store store, Tk2Listing l) async {
  final done = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _DeactivateSheet(store: store, listing: l),
  );
  if (done != null && context.mounted) {
    _toast(context, 'Turned off. We will remind you on ${tk2DateOf(done)}.');
  }
}

class _DeactivateSheet extends StatefulWidget {
  const _DeactivateSheet({required this.store, required this.listing});
  final Tk2Store store;
  final Tk2Listing listing;

  @override
  State<_DeactivateSheet> createState() => _DeactivateSheetState();
}

class _DeactivateSheetState extends State<_DeactivateSheet> {
  String? reason;
  DateTime? rentStart;
  final note = TextEditingController();
  final Set<String> bad = {};

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  bool get _rented => reason != null && Tk2Inactive.isRented(reason!);

  DateTime get _remindOn => Tk2Inactive.tenMonthsAfter(_rented && rentStart != null ? rentStart! : DateTime.now());

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: rentStart ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Rent started on',
    );
    if (picked != null) {
      setState(() {
        rentStart = picked;
        bad.remove('date');
      });
    }
  }

  Future<void> _save() async {
    bad
      ..clear()
      ..addAll({if (reason == null) 'reason', if (_rented && rentStart == null) 'date', if (reason == 'Other reason' && note.text.trim().isEmpty) 'note'});
    if (bad.isNotEmpty) return setState(() {});
    final remind = _remindOn;
    await widget.store.deactivate(widget.listing.id, reason: reason!, note: note.text, rentStart: rentStart);
    if (mounted) Navigator.pop(context, remind);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Turn off this property?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
          ),
          const SizedBox(height: 4),
          const Text(
            'It moves to Not active and cannot be shared. We keep it, and remind you after 10 months to check with the owner.',
            style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Text(
            'Why?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bad.contains('reason') ? AppColors.error : AppColors.heading),
          ),
          const SizedBox(height: 8),
          for (final r in Tk2Inactive.reasons) ...[
            _option(r),
            if (reason == r && _rented) _dateRow(),
            if (reason == r && r == 'Other reason')
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: note,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() => bad.remove('note')),
                  decoration: InputDecoration(labelText: 'What happened?', errorText: bad.contains('note') ? 'Tell us in a few words' : null),
                ),
              ),
          ],
          if (bad.contains('reason')) const Text('Choose a reason', style: TextStyle(fontSize: 14.5, color: AppColors.error)),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Text(
              _rented && rentStart == null ? 'Pick the rent start date to set the reminder.' : 'We will remind you on ${tk2DateOf(_remindOn)}.',
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 14),
          PrimaryButton(label: 'Turn off', onPressed: _save),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep it active')),
        ],
      ),
    ),
  );

  Widget _option(String r) {
    final on = reason == r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? AppColors.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? AppColors.primary : (bad.contains('reason') ? AppColors.error : AppColors.border), width: on ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            reason = r;
            bad.clear();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AppColors.heading),
                  ),
                ),
                Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: on ? AppColors.primary : AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateRow() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: bad.contains('date') ? AppColors.error : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, color: AppColors.primaryDark),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Rent started on', style: TextStyle(fontSize: 15.5, color: AppColors.heading)),
              ),
              Text(
                rentStart == null ? 'Pick date' : tk2DateOf(rentStart!),
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: bad.contains('date') ? AppColors.error : AppColors.primaryDark),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shown on the property page while it is off the market.
class Tk2InactiveBanner extends StatelessWidget {
  const Tk2InactiveBanner({required this.info, super.key});
  final Tk2Inactive info;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFEEF1F5), borderRadius: BorderRadius.circular(16)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.pause_circle_outline, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Not active · ${info.reason}',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (info.rentStart != null) 'Rent started ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(info.rentStart!))}.',
                  if (info.note.isNotEmpty) info.note,
                  'We remind you on ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(info.remindAt))}. Sharing is off until you turn it on.',
                ].join(' '),
                style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Bell: "check with the owner" reminders, then visits.
Future<void> showTk2Updates(BuildContext context, Tk2Store store, {required VoidCallback onOpenVisits}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (sheet) => ListenableBuilder(
    listenable: store,
    builder: (sheet, _) {
      final due = store.remindersDue();
      final upcoming = store.upcoming.length;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Updates',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
              ),
              const SizedBox(height: 14),
              for (final l in due) _Reminder(store: store, listing: l),
              Material(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const Icon(Icons.event_available_outlined, color: AppColors.primaryDark),
                  title: Text(upcoming == 0 ? 'No visits coming up' : '$upcoming visit${upcoming == 1 ? '' : 's'} coming up'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheet);
                    onOpenVisits();
                  },
                ),
              ),
              if (due.isEmpty) ...[const SizedBox(height: 12), const Text('Nothing else for now.', style: TextStyle(fontSize: 14.5, color: AppColors.muted))],
            ],
          ),
        ),
      );
    },
  ),
);

class _Reminder extends StatelessWidget {
  const _Reminder({required this.store, required this.listing});
  final Tk2Store store;
  final Tk2Listing listing;

  @override
  Widget build(BuildContext context) {
    final info = store.inactive(listing.id)!;
    final from = DateTime.fromMillisecondsSinceEpoch(info.rentStart ?? info.since);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This property might be available',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
          ),
          const SizedBox(height: 2),
          Text(
            '${listing.publicTitle} · ${info.reason.toLowerCase()} since ${tk2DateOf(from)}. Check the status with the owner.',
            style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.body),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  await store.activate(listing.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                    context.push('/p/${listing.id}?d=b');
                  }
                },
                child: const Text('It is available'),
              ),
              OutlinedButton(onPressed: () => store.remindLater(listing.id), child: const Text('Still not free · remind later')),
              if (listing.ownerPhone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:${listing.ownerPhone.replaceAll(' ', '')}')).then((_) {}, onError: (_) {}),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call owner'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
