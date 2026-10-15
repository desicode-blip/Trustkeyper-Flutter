import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../../participants/data/participant_workspace.dart';
import '../../participants/presentation/repair_photo_widgets.dart';
import '../data/repair_gateway.dart';

String repairMoney(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: paise % 100 == 0 ? 0 : 2,
).format(paise / 100);
String repairDate(Object? milliseconds) => milliseconds is int
    ? DateFormat(
        'd MMM · h:mm a',
      ).format(DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal())
    : 'Not scheduled';

String repairPayoutDate(Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  return date == null
      ? 'Next owner payout'
      : '${DateFormat('d MMM').format(date)} payout';
}

class RepairDetailScreen extends StatefulWidget {
  const RepairDetailScreen({
    required this.issueId,
    this.gateway,
    this.photoReader,
    this.offline = false,
    super.key,
  });
  final String issueId;
  final RepairGateway? gateway;
  final IssuePhotoReader? photoReader;
  final bool offline;
  @override
  State<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends State<RepairDetailScreen> {
  late final RepairGateway gateway = widget.gateway ?? FirebaseRepairGateway();
  StreamSubscription<RepairRecord>? subscription;
  RepairRecord? repair;
  String? loadError;
  String? actionError;
  Map<String, dynamic>? pending;
  String? pendingAction;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    subscription?.cancel();
    subscription = gateway
        .watch(widget.issueId)
        .listen(
          (record) {
            if (mounted) {
              setState(() {
                repair = record;
                loadError = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                repair = null;
                if (error is StateError ||
                    error is FirebaseException &&
                        [
                          'permission-denied',
                          'unauthenticated',
                        ].contains(error.code)) {
                  pending = null;
                  pendingAction = null;
                }
                loadError = _message(error);
              });
            }
          },
        );
  }

  String _message(Object error) => error is FirebaseFunctionsException
      ? error.message ?? 'Could not save. Check your connection and retry.'
      : error is StateError
      ? error.message.toString()
      : 'Could not save. Check your connection and retry.';
  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> _run(String action, Map<String, dynamic> values) async {
    if (busy || repair == null) return;
    pending ??= {
      'issueId': widget.issueId,
      'version': repair!.version,
      'operationId': newRepairReportId(),
      ...values,
    };
    pendingAction ??= action;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      await gateway.command(pendingAction!, pending!);
      if (mounted) {
        setState(() {
          pending = null;
          pendingAction = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => actionError = _message(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm(bool working) async {
    String note = '';
    if (!working) {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('What is still wrong?'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText:
                  'Describe the remaining problem (at least 10 characters)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null || !mounted) return;
      if (result.length < 10) {
        setState(
          () => actionError =
              'Describe the remaining problem in at least 10 characters.',
        );
        return;
      }
      note = result;
    }
    await _run('confirm', {
      'outcome': working ? 'working' : 'not_working',
      'note': note,
    });
  }

  Future<void> _bill() async {
    setState(() => busy = true);
    try {
      final file = await gateway.evidence(widget.issueId, 'bill');
      if (mounted) {
        await reviewPrivateDocument(
          context,
          file,
          upload: false,
          reviewTitle: 'Repair bill',
          instructions: 'Original private bill submitted by the support team.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => actionError = _message(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _call() async {
    if (widget.offline) {
      setState(
        () => actionError = 'Offline design preview: no call is placed.',
      );
      return;
    }
    if (!await launchUrl(Uri.parse('tel:+918088516875')) && mounted) {
      setState(
        () => actionError = 'Could not open the phone. Call +91 80885 16875.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = repair;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDF0F4)),
                    ),
                  ),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.chevron_left, size: 20),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _call,
                        icon: const Icon(Icons.headset_mic_outlined, size: 16),
                        label: const Text('Help'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF006B50),
                          backgroundColor: const Color(0xFFE6F7F0),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        tooltip: 'Refresh repair',
                        onPressed: busy ? null : _listen,
                        icon: const Icon(Icons.notifications_none),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: record == null
                      ? Center(
                          child: loadError == null
                              ? const CircularProgressIndicator()
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        loadError!,
                                        textAlign: TextAlign.center,
                                      ),
                                      TextButton(
                                        onPressed: _listen,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          children: [
                            if (widget.offline)
                              const Text(
                                'OFFLINE DESIGN PREVIEW · no live repair',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 12,
                                ),
                              ),
                            if (_approvedState(record))
                              _approvedBody(record)
                            else ...[
                              Text(
                                record.text('title', 'Reported problem'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  height: 32 / 26,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.heading,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                record.text('propertyAddress', 'Linked home'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _photos(record),
                              const SizedBox(height: 14),
                              if (record.completion.isNotEmpty) ...[
                                InkWell(
                                  onTap: busy ? null : _bill,
                                  borderRadius: BorderRadius.circular(18),
                                  child: _card(
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.receipt_long_outlined,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Repair bill',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '${record.completion['vendorName']} · #${record.completion['invoiceNumber']}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          children: [
                                            Text(
                                              repairMoney(
                                                record.completion['amountPaise']
                                                    as int,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Text(
                                              '↓ Open bill',
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              if (record.quote.isNotEmpty)
                                _card(
                                  Column(
                                    children: [
                                      if (record.completion.isEmpty)
                                        _fact(
                                          'Repair cost (quote)',
                                          repairMoney(record.quotePaise),
                                        ),
                                      _fact(
                                        'Taken from',
                                        record.completion.isEmpty
                                            ? 'Next owner payout'
                                            : repairPayoutDate(
                                                record
                                                    .completion['payoutDateISO'],
                                              ),
                                      ),
                                      if (record.completion.isNotEmpty)
                                        _fact(
                                          'Tenant says',
                                          record.tenantUpdate,
                                        ),
                                    ],
                                  ),
                                ),
                              if (record.canApprove)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 18,
                                          color: Color(0xFFE08A00),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Repairs above ₹2,000 need your approval.',
                                            style: TextStyle(fontSize: 14.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (!record.canApprove &&
                                  record.completion.isEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  record.statusLabel,
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (record.visit.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    '${record.visit['vendorName']} · ${repairDate(record.visit['startsAtMs'])}',
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Text(record.text('description')),
                              ],
                              if (record.completion.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Deduction awaiting payout reconciliation. No money is moved by this screen.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                            if (actionError != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                actionError!,
                                style: const TextStyle(color: AppColors.error),
                              ),
                              if (pending != null)
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                                _run(pendingAction!, const {}),
                                      child: const Text('Retry same action'),
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                              pending = null;
                                              pendingAction = null;
                                              actionError = null;
                                            }),
                                      child: const Text('Discard retry'),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                ),
                if (record != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFEDF0F4))),
                    ),
                    child: Row(
                      children: [
                        if (record.canApprove) ...[
                          Expanded(
                            child: _button(
                              'Call us',
                              Icons.phone_outlined,
                              _call,
                              outlined: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _button(
                              busy ? 'Saving…' : 'Approve',
                              Icons.check,
                              busy || pending != null
                                  ? null
                                  : () => _run('approve', {
                                      'quoteVersion': record.quote['version'],
                                    }),
                            ),
                          ),
                        ] else if (record.canConfirm) ...[
                          Expanded(
                            child: _button(
                              'Still not fixed',
                              Icons.build_outlined,
                              busy || pending != null
                                  ? null
                                  : () => _confirm(false),
                              outlined: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _button(
                              'Working now',
                              Icons.check,
                              busy || pending != null
                                  ? null
                                  : () => _confirm(true),
                            ),
                          ),
                        ] else
                          Expanded(
                            child: _button(
                              _approvedState(record)
                                  ? 'Back to issues'
                                  : 'Close',
                              Icons.check,
                              () => Navigator.maybePop(context),
                              outlined: true,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(
    String title,
    IconData icon,
    VoidCallback? callback, {
    bool outlined = false,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return outlined
        ? OutlinedButton.icon(
            style: style.copyWith(
              side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.primary),
              ),
            ),
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(title),
          )
        : FilledButton.icon(
            style: style,
            onPressed: callback,
            icon: Icon(icon, size: 18),
            label: Text(title),
          );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 15),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.heading,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _photos(RepairRecord record) {
    final photos = record.data['photos'];
    final reported = photos is List
        ? photos.whereType<Map>().toList()
        : <Map>[];
    final completed = record.completion.isNotEmpty;
    final before =
        record.completion['evidence'] is Map &&
        (record.completion['evidence'] as Map)['before'] != null;
    Widget original(int index) => index < reported.length
        ? PrivateRepairPhoto(
            issueId: record.id,
            path: reported[index]['path'] as String? ?? '',
            reader: widget.photoReader,
          )
        : const Text('No before photo');
    Widget evidence(String slot) =>
        _EvidencePhoto(issueId: record.id, slot: slot, gateway: gateway);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var index = 0;
          index < (completed ? 2 : reported.length.clamp(0, 2));
          index++
        ) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (completed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      index == 0 ? 'Before' : 'After',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: index == 0
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                  ),
                SizedBox(
                  height: completed ? 120 : 150,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.offline)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: index == 1 && completed
                                ? const Color(0xFFE0EFE8)
                                : index == 0
                                ? const Color(0xFFE9E1D5)
                                : const Color(0xFFE2E9F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            index == 1 && !completed
                                ? Icons.bolt_outlined
                                : Icons.water_drop_outlined,
                            size: 30,
                            color: const Color(0xFF9D9E9E),
                          ),
                        )
                      else if (completed && (index == 1 || before))
                        evidence(index == 0 ? 'before' : 'after')
                      else
                        original(index),
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF48525B),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'Received ${repairDate(completed && index == 1 ? record.completion['completedAtMs'] : record.data['createdAtMs'])}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _approvedState(RepairRecord record) =>
      record.role == 'owner' &&
      record.completion.isEmpty &&
      record.quote['needsApproval'] == true &&
      ['approved', 'assigned', 'in_progress'].contains(record.status);
  Widget _approvedBody(RepairRecord record) {
    final replies = record.object('ownerApprovals');
    final own = replies[record.text('actorUid')];
    final approvedAt = own is Map ? own['approvedAtMs'] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: Color(0xFFE6F7F0),
            child: CircleAvatar(
              radius: 29,
              backgroundColor: Color(0xFF2AAB69),
              child: Icon(Icons.check, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Approved · ${repairMoney(record.quotePaise)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.heading,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'We will fix the problem and send you the bill.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 17),
        ),
        const SizedBox(height: 18),
        _card(
          Column(
            children: [
              _timeline(
                'You approved',
                repairDate(approvedAt),
                Icons.check,
                AppColors.success,
              ),
              _timeline(
                'Plumber visit',
                record.visit.isEmpty
                    ? 'The team is arranging a visit'
                    : repairDate(record.visit['startsAtMs']),
                Icons.schedule,
                AppColors.primary,
              ),
              _timeline(
                'Repair done',
                'Photos and bill shared here',
                Icons.schedule,
                AppColors.disabled,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeline(String title, String subtitle, IconData icon, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _EvidencePhoto extends StatefulWidget {
  const _EvidencePhoto({
    required this.issueId,
    required this.slot,
    required this.gateway,
  });
  final String issueId;
  final String slot;
  final RepairGateway gateway;
  @override
  State<_EvidencePhoto> createState() => _EvidencePhotoState();
}

class _EvidencePhotoState extends State<_EvidencePhoto> {
  late Future<DocumentFile> file = widget.gateway.evidence(
    widget.issueId,
    widget.slot,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<DocumentFile>(
    future: file,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(
            () => file = widget.gateway.evidence(widget.issueId, widget.slot),
          ),
          child: const Text('Retry photo'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return InkWell(
        onTap: () =>
            reviewPrivateDocument(context, snapshot.data!, upload: false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            snapshot.data!.bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 700,
            errorBuilder: (_, error, stack) =>
                const Center(child: Text('Photo unavailable')),
          ),
        ),
      );
    },
  );
}
