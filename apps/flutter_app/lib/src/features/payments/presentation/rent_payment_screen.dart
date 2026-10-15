import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/trustkeyper_ui.dart';
import '../../broker/data/private_documents.dart';
import '../data/gateway_checkout.dart';
import '../data/rent_payments.dart';

class RentPaymentScreen extends StatefulWidget {
  const RentPaymentScreen({
    required this.agreementId,
    required this.revision,
    this.gateway,
    this.checkout,
    this.offlineFixture = false,
    super.key,
  });
  final String agreementId;
  final int revision;
  final RentPaymentGateway? gateway;
  final Future<Map<String, String>> Function(Map<String, dynamic>)? checkout;
  final bool offlineFixture;
  @override
  State<RentPaymentScreen> createState() => _RentPaymentScreenState();
}

class _RentPaymentScreenState extends State<RentPaymentScreen> {
  late final gateway = widget.gateway ?? FirebaseRentPaymentGateway();
  RentPaymentData? quote;
  RentPaymentData? intent;
  final selected = <String>{};
  String? operationId;
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Status could not be confirmed. Check status before paying again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final result = await gateway.quote(widget.agreementId, widget.revision);
    if (!mounted) return;
    setState(() {
      quote = result;
      intent = result.pending?.text('status') == 'creation_failed'
          ? null
          : result.pending;
      selected.clear();
      final available = result
          .rows('periods')
          .where((period) => !period.flag('paid'))
          .toList();
      if (available.isNotEmpty) {
        final initial = result.flag('firstPayment')
            ? result.text('firstPaymentMonth')
            : available.first.text('month');
        if (available.any((period) => period.text('month') == initial)) {
          selected.add(initial);
        }
      }
    });
  });
  Future<void> _pay() => _run(() async {
    operationId ??= gateway.operationId();
    final result =
        intent ??
        await gateway.begin(
          widget.agreementId,
          widget.revision,
          selected.toList(),
          operationId!,
        );
    if (!mounted) return;
    setState(() => intent = result);
    if (result.paid) return;
    if (result.text('orderId').isEmpty) {
      throw const DocumentFailure(
        'Order creation is being checked. Tap Check payment status.',
      );
    }
    if (result.text('status') == 'reconciliation_required') {
      throw const DocumentFailure(
        'Payment needs team reconciliation. Do not pay again.',
      );
    }
    if (!result.text('keyId').startsWith('rzp_test_')) {
      final resumed = await gateway.reconcile(result.text('intentId'));
      if (!mounted) return;
      setState(() => intent = resumed);
      if (resumed.paid) return;
    }
    final current = intent!;
    if (!current.text('keyId').startsWith('rzp_test_')) {
      throw const DocumentFailure(
        'Test checkout is unavailable. Check status.',
      );
    }
    final response = await (widget.checkout ?? openGatewayCheckout)({
      'key': current.text('keyId'),
      'order_id': current.text('orderId'),
      'amount': current.amount('amountPaise'),
      'currency': 'INR',
      'name': 'TrustKeyper · Test',
      'description': 'Test rent and deposit · no real money',
      'prefill': {
        'name': current.text('payerName'),
        'contact': current.text('payerPhone'),
      },
      'theme': {'color': '#4169FF'},
    });
    final confirmed = await gateway.confirm(current.text('intentId'), response);
    if (mounted) setState(() => intent = confirmed);
  });
  Future<void> _check() => _run(() async {
    if (intent == null) {
      final result = await gateway.quote(widget.agreementId, widget.revision);
      if (mounted) {
        setState(() {
          quote = result;
          intent = result.pending;
        });
      }
    }
    if (intent != null) {
      final result = await gateway.reconcile(intent!.text('intentId'));
      if (mounted) {
        setState(() {
          intent = result.text('status') == 'creation_failed' ? null : result;
          if (intent == null) {
            operationId = null;
            error =
                'The gateway rejected order creation. You can start a new test checkout.';
          }
        });
      }
    }
  });
  Future<void> _save() => _run(() async {
    final verified = await gateway.reconcile(intent!.text('intentId'));
    if (!mounted) return;
    setState(() => intent = verified);
    final bytes = await paymentReceipt(verified);
    await FilePicker.saveFile(
      fileName: '${intent!.text('receiptNumber')}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
  });
  String monthName(String month) =>
      DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));
  int get total => quote == null
      ? 0
      : quote!.amount('depositPaise') +
            quote!
                .rows('periods')
                .where((period) => selected.contains(period.text('month')))
                .fold(0, (sum, period) => sum + period.amount('totalPaise'));
  @override
  Widget build(BuildContext context) {
    final paid = intent?.paid == true;
    return TkPage(
      onBack: () => Navigator.pop(context),
      showHelp: true,
      step: 'Tenant · Test payments',
      title: paid
          ? '${paymentMoney(intent!.amount('amountPaise'))} paid · test'
          : 'What do you want to pay?',
      subtitle: quote?.text('propertyAddress'),
      bottom: TkPrimaryButton(
        label: paid
            ? 'Download receipt'
            : intent == null
            ? 'Pay ${paymentMoney(total)} · test'
            : 'Resume test checkout',
        onPressed:
            busy || quote == null || !paid && intent == null && selected.isEmpty
            ? null
            : paid
            ? _save
            : _pay,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.offlineFixture
                  ? 'OFFLINE UI FIXTURE · no network or gateway. Use this screen only to check layout and month selection.'
                  : 'RAZORPAY TEST MODE · no real money moves. Test payments do not release keys, settle payouts or complete legal signing.',
            ),
          ),
          const SizedBox(height: 20),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
          ],
          if (paid) ...[
            const Icon(Icons.check_circle, size: 88, color: AppColors.success),
            const SizedBox(height: 18),
            _row('Receipt', intent!.text('receiptNumber')),
            _row('Gateway payment', intent!.text('paymentId')),
            _row('Deposit', paymentMoney(intent!.amount('depositPaise'))),
            for (final line in intent!.rows('lines')) ...[
              _row(
                '${monthName(line.text('month'))} rent',
                paymentMoney(line.amount('rentPaise')),
              ),
              _row(
                'Maintenance',
                paymentMoney(line.amount('maintenancePaise')),
              ),
            ],
            const Text(
              'Verified by the backend with Razorpay. Email and WhatsApp receipt delivery have not been sent.',
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      operationId = null;
                      _load();
                    },
              child: const Text('Pay other months'),
            ),
          ] else if (quote != null) ...[
            if (quote!.flag('firstPayment')) ...[
              _row(
                'Deposit · one time',
                paymentMoney(quote!.amount('depositPaise')),
              ),
              const Text(
                'First payment is the current rental month, deposit and maintenance only. For a future lease, its first month is scheduled. Older unpaid rent stays due. Advance months are available after this payment, up to the agreement end date.',
              ),
            ],
            for (final period
                in quote!
                    .rows('periods')
                    .where(
                      (period) =>
                          !quote!.flag('firstPayment') ||
                          period.text('month') ==
                              quote!.text('firstPaymentMonth'),
                    ))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value:
                    period.flag('paid') ||
                    selected.contains(period.text('month')),
                title: Text('${monthName(period.text('month'))} rent'),
                subtitle: Text(
                  period.flag('paid')
                      ? 'Paid · test'
                      : 'Rent ${paymentMoney(period.amount('rentPaise'))} + maintenance ${paymentMoney(period.amount('maintenancePaise'))}'
                            '${period.amount('days') == period.amount('daysInMonth') ? '' : ' · ${period.amount('days')} rental days'}',
                ),
                onChanged:
                    busy ||
                        intent != null ||
                        period.flag('paid') ||
                        quote!.flag('firstPayment')
                    ? null
                    : (checked) => setState(() {
                        operationId = null;
                        if (checked == true) {
                          selected.add(period.text('month'));
                        } else {
                          selected.remove(period.text('month'));
                        }
                      }),
              ),
            const Divider(),
            _row(
              'Total to pay',
              paymentMoney(intent?.amount('amountPaise') ?? total),
            ),
            const Text(
              'Choose UPI, card or net banking in secure Razorpay checkout. We never see your UPI PIN or card details.',
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: busy ? null : _check,
            icon: const Icon(Icons.refresh),
            label: const Text('Check payment status'),
          ),
          if (quote == null)
            TextButton(
              onPressed: busy ? null : _load,
              child: const Text('Retry loading payments'),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
