import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_listing.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

/// All visits: money held / yours at the top, upcoming then past.
class Tk2Visits extends StatelessWidget {
  const Tk2Visits({required this.store, required this.onShare, super.key});
  final Tk2Store store;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final upcoming = store.upcoming;
    final past = store.past;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const Tk2Appear(child: Tk2Title('Visits')),
          const SizedBox(height: 16),
          Tk2Appear(
            index: 1,
            child: Row(
              children: [
                _money(
                  Tk2Store.money(store.heldTotal),
                  'Held for you',
                  'Yours after the visit',
                  AppColors.warningSoft,
                  AppColors.warning,
                  Icons.lock_clock_outlined,
                ),
                const SizedBox(width: 10),
                _money(
                  Tk2Store.money(store.releasedTotal),
                  'Yours',
                  'From visits done',
                  AppColors.successSoft,
                  AppColors.success,
                  Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          if (upcoming.isEmpty && past.isEmpty)
            Tk2Appear(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.event_available_outlined, size: 44, color: AppColors.primaryDark),
                    const SizedBox(height: 12),
                    const Text(
                      'No visits yet',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.heading),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Share a property. When a customer books, the visit shows here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onShare,
                      child: const Text('Go to properties', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          if (upcoming.isNotEmpty) ...[
            _heading('Coming up'),
            for (var i = 0; i < upcoming.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Tk2Appear(
                  key: ValueKey(upcoming[i].id),
                  index: i + 2,
                  child: Tk2VisitRow(visit: upcoming[i], store: store, showProperty: true, onTap: () => showTk2Visit(context, store, upcoming[i])),
                ),
              ),
          ],
          if (past.isNotEmpty) ...[
            const SizedBox(height: 14),
            _heading('Earlier'),
            for (final v in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Tk2VisitRow(visit: v, store: store, showProperty: true, onTap: () => showTk2Visit(context, store, v)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      t,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
  );

  Widget _money(String value, String label, String note, Color bg, Color fg, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: fg),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.8)),
          ),
        ],
      ),
    ),
  );
}

/// One visit: call the customer, mark it done with their code, or close it.
Future<void> showTk2Visit(BuildContext context, Tk2Store store, Tk2Visit visit) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (sheet) => _VisitSheet(store: store, visit: visit, outer: context),
);

class _VisitSheet extends StatefulWidget {
  const _VisitSheet({required this.store, required this.visit, required this.outer});
  final Tk2Store store;
  final Tk2Visit visit;
  final BuildContext outer;

  @override
  State<_VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends State<_VisitSheet> {
  bool askCode = false;
  final code = TextEditingController();
  String? error;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!widget.outer.mounted) return;
    ScaffoldMessenger.of(widget.outer).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  Future<void> _confirm() async {
    final why = await widget.store.confirmVisit(widget.visit.id, code.text);
    if (!mounted) return;
    if (why != null) {
      setState(
        () => error = why == 'window'
            ? 'The code works from 24 hours before to 24 hours after the visit time.'
            : 'That code is not right. Ask the customer again.',
      );
      return;
    }
    Navigator.pop(context);
    _toast('${Tk2Store.money(widget.visit.fee)} is yours. Nice work!');
  }

  /// Gate pass: photo or screenshot from the society app. Sent to the customer on WhatsApp.
  Future<void> _gatePass() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (file == null) return;
      await widget.store.addGatePass(widget.visit.id, file.path);
      if (!mounted) return;
      setState(() {});
      _toast('Gate pass sent to ${widget.visit.customerName} on WhatsApp');
    } catch (_) {}
  }

  Future<void> _close(String status) async {
    final cancel = status == VisitStatus.cancelled;
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(cancel ? 'Cancel this visit?' : 'Customer did not come?'),
        content: Text(
          cancel
              ? '${widget.visit.customerName} gets ${Tk2Store.money(widget.visit.fee)} back.'
              : 'You get ${Tk2Store.money(widget.visit.fee ~/ 2)} for your time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Go back')),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(cancel ? 'Cancel visit' : 'Yes, did not come'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.store.closeVisit(widget.visit.id, status);
    if (!mounted) return;
    Navigator.pop(context);
    _toast(
      cancel
          ? 'Visit cancelled. ${Tk2Store.money(widget.visit.fee)} goes back to the customer.'
          : '${Tk2Store.money(widget.visit.fee ~/ 2)} is yours for your time.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visit;
    final l = widget.store.listing(v.listingId);
    final at = DateTime.fromMillisecondsSinceEpoch(v.at);
    final early = DateTime.now().isBefore(at.subtract(const Duration(minutes: 30)));
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              v.customerName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
            ),
            const SizedBox(height: 4),
            Text('${tk2Day(at)}, ${tk2Time(at)} · ${l?.name ?? ''}', style: const TextStyle(fontSize: 15, color: AppColors.muted)),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: switch (v.feeStatus) {
                'released' => Tk2Pill('${Tk2Store.money(v.fee)} is yours', kind: 'ok', icon: Icons.check),
                'refunded' => Tk2Pill('${Tk2Store.money(v.customerRefund)} refunded to customer'),
                'half' => Tk2Pill('${Tk2Store.money(v.brokerShare)} is yours · did not come', kind: 'ok', icon: Icons.check),
                'kept' => const Tk2Pill('Customer cancelled'),
                _ => Tk2Pill('${Tk2Store.money(v.fee)} held · yours after the visit', kind: 'wait', icon: Icons.lock_clock_outlined),
              },
            ),
            const SizedBox(height: 18),
            if (v.customerPhone.isNotEmpty)
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:${v.customerPhone.replaceAll(' ', '')}')).catchError((_) => false),
                  icon: const Icon(Icons.call_outlined),
                  label: Text('Call ${v.customerPhone}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.border),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (v.upcoming) ...[
              const SizedBox(height: 10),
              _GatePassRow(sent: (widget.store.visits.where((x) => x.id == v.id).firstOrNull ?? v).gatePass.isNotEmpty, onTap: _gatePass),
              const SizedBox(height: 14),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: askCode
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Ask the customer for their 4 digit visit code', style: TextStyle(fontSize: 15.5, color: AppColors.body)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: code,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 10),
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                            onChanged: (t) {
                              setState(() => error = null);
                              if (t.length == 4) _confirm();
                            },
                            decoration: const InputDecoration(hintText: '• • • •'),
                          ),
                          if (error != null) ...[const SizedBox(height: 8), Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 15))],
                        ],
                      )
                    : PrimaryButton(label: 'Visit done · get ${Tk2Store.money(v.fee)}', onPressed: () => setState(() => askCode = true)),
              ),
              if (early && !askCode)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap this after the customer has seen the house.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: AppColors.muted),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _close(VisitStatus.noShow),
                      style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                      child: const Text('Did not come'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _close(VisitStatus.cancelled),
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Cancel visit'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gate pass for gated societies: add once, we send it to the customer.
class _GatePassRow extends StatelessWidget {
  const _GatePassRow({required this.sent, required this.onTap});
  final bool sent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: sent ? AppColors.successSoft : AppColors.warningSoft,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(sent ? Icons.check_circle_outline : Icons.badge_outlined, color: sent ? AppColors.success : AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sent ? 'Gate pass sent on WhatsApp' : 'Add gate pass',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
                  Text(
                    sent ? 'Tap to change it' : 'Upload it here. We send it to the customer on WhatsApp.',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                  ),
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
