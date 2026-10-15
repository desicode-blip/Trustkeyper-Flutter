import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/trustkeyper_ui.dart';
import 'payment_agreement_picker.dart';
import '../../participants/data/participant_repository.dart';

enum PaymentMethod { upi, card, netBanking }

class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({
    this.previewOnly = false,
    this.agreementRepository,
    super.key,
  });
  final bool previewOnly;
  final ParticipantRepository? agreementRepository;

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  final amountController = TextEditingController(text: '11000');
  final upiController = TextEditingController();
  final cardController = TextEditingController();
  final bankController = TextEditingController();
  PaymentMethod method = PaymentMethod.upi;
  bool paying = false;
  String? receipt;

  @override
  void dispose() {
    amountController.dispose();
    upiController.dispose();
    cardController.dispose();
    bankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.previewOnly) {
      return PaymentAgreementPicker(repository: widget.agreementRepository);
    }
    if (receipt != null) return _success(context);
    return TkPage(
      onBack: () => context.pop(),
      showHelp: true,
      step: 'Checkout preview · simulation only',
      title: 'Pay November rent',
      subtitle: 'Phoenix Towers 402 · your share',
      bottom: TkPrimaryButton(
        label: paying ? 'Running simulation…' : 'Simulate payment',
        onPressed: paying ? null : _confirmPayment,
        icon: Icons.lock_outline_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_outlined, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SIMULATION ONLY — no Razorpay integration or payment verification. Use dummy details only. No money moves, rent balance changes or notifications are sent.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount to pay *',
              prefixText: '₹ ',
              helperText: 'You can pay the full rent or a part now.',
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Choose payment method',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(
                value: PaymentMethod.upi,
                label: Text('UPI'),
                icon: Icon(Icons.qr_code_2),
              ),
              ButtonSegment(
                value: PaymentMethod.card,
                label: Text('Card'),
                icon: Icon(Icons.credit_card),
              ),
              ButtonSegment(
                value: PaymentMethod.netBanking,
                label: Text('Bank'),
                icon: Icon(Icons.account_balance),
              ),
            ],
            selected: {method},
            onSelectionChanged: (value) => setState(() => method = value.first),
          ),
          const SizedBox(height: 18),
          switch (method) {
            PaymentMethod.upi => TextField(
              controller: upiController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Dummy UPI ID only',
                hintText: 'name@bank',
              ),
            ),
            PaymentMethod.card => TextField(
              controller: cardController,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Test card number',
                hintText: '4111 1111 1111 1111',
              ),
            ),
            PaymentMethod.netBanking => DropdownMenu<String>(
              controller: bankController,
              width: double.infinity,
              label: const Text('Choose bank'),
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 'SBI', label: 'State Bank of India'),
                DropdownMenuEntry(value: 'HDFC', label: 'HDFC Bank'),
                DropdownMenuEntry(value: 'ICICI', label: 'ICICI Bank'),
                DropdownMenuEntry(value: 'Axis', label: 'Axis Bank'),
              ],
            ),
          },
          const SizedBox(height: 24),
          const TkStatusRow(
            icon: Icons.shield_outlined,
            title: 'Provider checkout pending',
            detail: 'This preview does not contact a payment provider.',
            done: false,
          ),
          const TkStatusRow(
            icon: Icons.receipt_long_outlined,
            title: 'Receipt delivery pending',
            detail: 'Only a simulated reference is saved on this device.',
            done: false,
          ),
        ],
      ),
    );
  }

  Widget _success(BuildContext context) {
    return TkPage(
      title: 'Test payment successful',
      subtitle: 'No real money moved. The receipt is stored on this device.',
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 96,
          ),
          const SizedBox(height: 24),
          TkAmount(
            label: 'Amount recorded',
            amount: '₹${amountController.text.trim()}',
            words: 'November rent · test transaction',
          ),
          const SizedBox(height: 18),
          TkStatusRow(
            icon: Icons.receipt_long_outlined,
            title: 'Receipt',
            detail: receipt!,
            done: true,
          ),
          const SizedBox(height: 26),
          TkPrimaryButton(
            label: 'Back to tenant home',
            onPressed: () => context.go('/tenant'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment() async {
    final amount = int.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      _message('Enter a valid amount.');
      return;
    }
    final methodValue = switch (method) {
      PaymentMethod.upi => upiController.text.trim(),
      PaymentMethod.card => cardController.text.replaceAll(' ', '').trim(),
      PaymentMethod.netBanking => bankController.text.trim(),
    };
    if (methodValue.isEmpty) {
      _message('Complete the selected payment method.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.science_outlined),
        title: const Text('Run test payment?'),
        content: Text(
          'This simulates a ₹$amount payment. It does not contact Razorpay or move money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run test'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => paying = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final now = DateTime.now().millisecondsSinceEpoch;
    final value = 'TK-TEST-$now';
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('latest_payment_receipt', value);
    if (!mounted) return;
    setState(() {
      paying = false;
      receipt = value;
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
