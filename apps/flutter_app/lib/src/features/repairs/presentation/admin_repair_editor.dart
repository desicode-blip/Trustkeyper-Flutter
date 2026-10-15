import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../../participants/data/participant_workspace.dart';
import '../../participants/presentation/repair_photo_widgets.dart';
import '../data/repair_gateway.dart';
import 'repair_detail_screen.dart';

int? repairPaise(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().split('.');
  final result =
      int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  return result > 0 && result <= 100000000 ? result : null;
}

class AdminRepairEditor extends StatefulWidget {
  const AdminRepairEditor({
    required this.issueId,
    required this.onBack,
    this.gateway,
    this.photoReader,
    super.key,
  });
  final String issueId;
  final VoidCallback onBack;
  final RepairGateway? gateway;
  final IssuePhotoReader? photoReader;
  @override
  State<AdminRepairEditor> createState() => _AdminRepairEditorState();
}

class _AdminRepairEditorState extends State<AdminRepairEditor> {
  late final gateway = widget.gateway ?? FirebaseRepairGateway();
  final amount = TextEditingController();
  final vendor = TextEditingController();
  final phone = TextEditingController();
  final work = TextEditingController();
  final invoice = TextEditingController();
  final billAmount = TextEditingController();
  StreamSubscription<RepairRecord>? subscription;
  RepairRecord? repair;
  final selected = <String, DocumentFile>{};
  Map<String, dynamic>? pending;
  String? action;
  String? error;
  bool busy = false;
  bool visitDone = false;
  DateTime? visit;
  DateTime? payout;
  int durationHours = 2;
  bool get editable => !busy && pending == null;
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
            if (!mounted) return;
            setState(() {
              final initial = repair == null;
              repair = record;
              if (initial && record.quote.isNotEmpty) {
                amount.text = (record.quotePaise / 100).toStringAsFixed(2);
                billAmount.text = amount.text;
                vendor.text = record.quote['vendorName'] as String? ?? '';
                phone.text = record.quote['vendorPhone'] as String? ?? '';
                work.text = record.quote['description'] as String? ?? '';
              }
            });
          },
          onError: (Object failure) {
            if (mounted) {
              setState(() {
                repair = null;
                if (failure is StateError ||
                    failure is FirebaseException &&
                        [
                          'permission-denied',
                          'unauthenticated',
                        ].contains(failure.code)) {
                  selected.clear();
                  pending = null;
                  action = null;
                  visitDone = false;
                }
                error = _message(failure);
              });
            }
          },
        );
  }

  @override
  void dispose() {
    subscription?.cancel();
    for (final controller in [
      amount,
      vendor,
      phone,
      work,
      invoice,
      billAmount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _message(Object failure) => failure is FirebaseFunctionsException
      ? failure.message ?? 'Could not save. Retry.'
      : failure is DocumentFailure
      ? failure.message
      : failure is StateError
      ? failure.message.toString()
      : 'Could not save. Check your connection and retry.';
  void _invalid(String message) => setState(() => error = message);
  Future<void> _save(String kind, Map<String, dynamic> values) async {
    if (busy || repair == null) return;
    pending ??= {
      'issueId': widget.issueId,
      'version': repair!.version,
      'operationId': newRepairReportId(),
      ...values,
    };
    action ??= kind;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (action == 'complete') {
        await gateway.complete(pending!, Map.unmodifiable(selected));
      } else {
        await gateway.command(action!, pending!);
      }
      if (mounted) {
        setState(() {
          pending = null;
          action = null;
          selected.clear();
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = _message(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _choose(String slot) async {
    if (!editable) return;
    setState(() => busy = true);
    try {
      final file = await pickPrivateDocument();
      if (file == null || !mounted) return;
      file.validate();
      if (slot != 'bill' && !file.contentType.startsWith('image/')) {
        throw const DocumentFailure(
          'Before and after must be JPG or PNG photos.',
        );
      }
      final accepted = await reviewPrivateDocument(
        context,
        file,
        upload: true,
        selectionOnly: true,
        reviewTitle: 'Review $slot',
        instructions:
            'Nothing is submitted until you press Mark fixed. Evidence is shared privately with linked participants.',
      );
      if (accepted && mounted) setState(() => selected[slot] = file);
    } catch (failure) {
      if (mounted) _invalid(_message(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _date(bool ownerPayout) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(Duration(days: ownerPayout ? 179 : 89)),
    );
    if (picked == null || !mounted) return;
    if (ownerPayout) {
      if (picked.day != 7) {
        _invalid('Owner payouts are on the 7th. Select that date.');
        return;
      }
      setState(() => payout = picked);
    } else {
      final clock = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 11, minute: 0),
      );
      if (clock != null && mounted) {
        setState(
          () => visit = DateTime(
            picked.year,
            picked.month,
            picked.day,
            clock.hour,
            clock.minute,
          ),
        );
      }
    }
  }

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: editable,
      maxLines: lines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget _pick(String slot) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(20)),
      onPressed: editable ? () => _choose(slot) : null,
      icon: Icon(
        slot == 'bill'
            ? Icons.upload_file_outlined
            : Icons.add_a_photo_outlined,
      ),
      label: Text(
        selected[slot]?.name ??
            (slot == 'bill' ? 'Upload bill PDF or photo' : 'Add $slot photo'),
      ),
    ),
  );

  Widget _completionLayout(RepairRecord record, Widget bill) {
    Widget photo(String slot) {
      final file = selected[slot];
      final originals = record.data['photos'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            slot == 'before' ? 'Before' : 'After',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: file != null
                ? Image.memory(
                    file.bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) =>
                        const Center(child: Text('Choose a readable photo')),
                  )
                : slot == 'before' && originals is List && originals.isNotEmpty
                ? PrivateRepairPhoto(
                    issueId: record.id,
                    path: (originals.first as Map)['path'] as String? ?? '',
                    reader: widget.photoReader,
                  )
                : const Center(
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.muted,
                      size: 36,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _pick(slot),
        ],
      );
    }

    final photos = _panel('Visit done · add bill', [
      const Text(
        'Share the original before and after photos with the linked owner and tenant.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: photo('before')),
          const SizedBox(width: 14),
          Expanded(child: photo('after')),
        ],
      ),
    ]);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 800
          ? Column(children: [photos, const SizedBox(height: 18), bill])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: photos),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: bill),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = repair;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : widget.onBack,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Back to repairs'),
          ),
        ),
        if (record == null)
          Padding(
            padding: const EdgeInsets.all(30),
            child: error == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: busy ? null : _listen,
                        child: const Text('Retry loading repair'),
                      ),
                    ],
                  ),
          )
        else ...[
          Text(
            record.text('title', 'Repair'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${record.text('propertyAddress')} · ${record.statusLabel}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          if (record.role != 'admin')
            const Text('Only the support team can manage this repair.')
          else if (record.completion.isNotEmpty)
            _panel('Repair completed', [
              Text(
                '${repairMoney(record.completion['amountPaise'] as int)} · #${record.completion['invoiceNumber']}',
              ),
              const SizedBox(height: 8),
              Text(
                'Intended payout: ${record.completion['payoutDateISO']} · awaiting reconciliation',
              ),
              const SizedBox(height: 8),
              const Text(
                'The bill is immutable. This screen does not deduct or transfer money.',
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RepairDetailScreen(
                      issueId: widget.issueId,
                      gateway: gateway,
                      photoReader: widget.photoReader,
                    ),
                  ),
                ),
                child: const Text('View before, after and bill'),
              ),
              if (record.status == 'needs_attention')
                const Text(
                  'A tenant says this is still not fixed. Contact them and open a follow-up repair; do not charge twice.',
                  style: TextStyle(color: AppColors.error),
                ),
            ])
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final quotePanel = _panel('Vendor quote', [
                  _field('Vendor name', vendor),
                  _field('Vendor phone', phone),
                  _field('Work to be done', work, lines: 3),
                  _field('Repair cost (₹)', amount, numeric: true),
                  const Text(
                    'Above ₹2,000: every verified owner must approve. New quotes cancel previous approvals.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: editable
                        ? () {
                            final paise = repairPaise(amount.text);
                            if (paise == null) {
                              _invalid(
                                'Enter a positive quote up to ₹10,00,000 with at most two decimal places.',
                              );
                              return;
                            }
                            _save('quote', {
                              'amountPaise': paise,
                              'vendorName': vendor.text.trim(),
                              'vendorPhone': phone.text.trim(),
                              'description': work.text.trim(),
                            });
                          }
                        : null,
                    child: Text(
                      record.quote.isEmpty
                          ? 'Save quote'
                          : 'Replace quote · request approval again',
                    ),
                  ),
                ]);
                final visitPanel = _panel('Who fixes · when', [
                  Text(
                    record.quote.isEmpty
                        ? 'Save the quote first.'
                        : '${record.quote['vendorName']} · ${repairMoney(record.quotePaise)}',
                  ),
                  if (record.status == 'waiting_owner')
                    const Text(
                      'Waiting for all owners. This cannot be overridden.',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: editable ? () => _date(false) : null,
                    child: Text(
                      visit == null
                          ? 'Choose visit date and time'
                          : DateFormat('d MMM yyyy · h:mm a').format(visit!),
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: durationHours,
                    items: [
                      for (var hours = 1; hours <= 8; hours++)
                        DropdownMenuItem(
                          value: hours,
                          child: Text('$hours hour${hours == 1 ? '' : 's'}'),
                        ),
                    ],
                    onChanged: editable
                        ? (hours) => setState(() => durationHours = hours!)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        editable &&
                            [
                              'approved',
                              'assigned',
                              'in_progress',
                            ].contains(record.status)
                        ? () {
                            if (visit == null) {
                              _invalid('Choose a visit first.');
                              return;
                            }
                            _save('schedule', {
                              'startsAtMs': visit!.millisecondsSinceEpoch,
                              'endsAtMs': visit!
                                  .add(Duration(hours: durationHours))
                                  .millisecondsSinceEpoch,
                            });
                          }
                        : null,
                    child: const Text('Schedule visit'),
                  ),
                  if (record.visit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Saved visit: ${repairDate(record.visit['startsAtMs'])}',
                      ),
                    ),
                ]);
                final panels = constraints.maxWidth < 800
                    ? Column(
                        children: [
                          quotePanel,
                          const SizedBox(height: 18),
                          visitPanel,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: quotePanel),
                          const SizedBox(width: 18),
                          Expanded(child: visitPanel),
                        ],
                      );
                return ['assigned', 'in_progress'].contains(record.status)
                    ? ExpansionTile(
                        title: const Text('Approved quote and scheduled visit'),
                        children: [panels],
                      )
                    : panels;
              },
            ),
            if (['assigned', 'in_progress'].contains(record.status)) ...[
              const SizedBox(height: 18),
              _completionLayout(
                record,
                _panel('Bill & close', [
                  _pick('bill'),
                  _field('Bill / invoice number', invoice),
                  _field('Final amount (₹)', billAmount, numeric: true),
                  OutlinedButton(
                    onPressed: editable ? () => _date(true) : null,
                    child: Text(
                      payout == null
                          ? 'Take from · choose owner payout on the 7th'
                          : '${DateFormat('d MMM yyyy').format(payout!)} owner payout',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    onPressed: editable
                        ? () {
                            final paise = repairPaise(billAmount.text);
                            final original = record.data['photos'];
                            if (paise == null ||
                                paise > record.quotePaise ||
                                invoice.text.trim().isEmpty ||
                                !visitDone ||
                                payout == null ||
                                selected['bill'] == null ||
                                selected['after'] == null ||
                                (selected['before'] == null &&
                                    (original is! List || original.isEmpty))) {
                              _invalid(
                                'Add the bill, after photo, a before photo, invoice and payout date. The bill must not exceed the approved quote.',
                              );
                              return;
                            }
                            _save('complete', {
                              'amountPaise': paise,
                              'invoiceNumber': invoice.text.trim(),
                              'payoutDateISO': DateFormat(
                                'yyyy-MM-dd',
                              ).format(payout!),
                              'includeBefore': selected['before'] != null,
                              'visitDone': visitDone,
                            });
                          }
                        : null,
                    label: Text(
                      busy
                          ? 'Saving…'
                          : 'Mark fixed · share with owner and tenant',
                    ),
                  ),
                  CheckboxListTile(
                    value: visitDone,
                    onChanged: editable
                        ? (value) => setState(() => visitDone = value == true)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'The vendor completed the visit. The bill and photos are for this repair.',
                    ),
                  ),
                ]),
              ),
            ],
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          if (pending != null)
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : () => _save(action!, const {}),
                  child: const Text('Retry same submission'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          pending = null;
                          action = null;
                          error = null;
                        }),
                  child: const Text('Discard retry · refresh details'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
