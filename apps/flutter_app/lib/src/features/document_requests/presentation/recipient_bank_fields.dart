import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class RecipientBankFields extends StatefulWidget {
  const RecipientBankFields({
    required this.method,
    required this.onSave,
    this.initial,
    super.key,
  });
  final String method;
  final Map<String, dynamic>? initial;
  final ValueChanged<Map<String, dynamic>> onSave;
  @override
  State<RecipientBankFields> createState() => _RecipientBankFieldsState();
}

class _RecipientBankFieldsState extends State<RecipientBankFields> {
  final name = TextEditingController();
  final bank = TextEditingController();
  final number = TextEditingController();
  final repeat = TextEditingController();
  final ifsc = TextEditingController();
  final upi = TextEditingController();
  String accountType = 'savings';
  String? error;
  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? {};
    name.text = initial['name'] as String? ?? '';
    bank.text = initial['bank'] as String? ?? '';
    number.text = repeat.text = initial['accountNumber'] as String? ?? '';
    ifsc.text = initial['ifsc'] as String? ?? '';
    upi.text = initial['upiId'] as String? ?? '';
    accountType = initial['accountType'] as String? ?? 'savings';
  }

  @override
  void dispose() {
    for (final controller in [name, bank, number, repeat, ifsc, upi]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? get validation {
    if (widget.method == 'upi') {
      return RegExp(
            r'^[a-zA-Z0-9._-]{2,128}@[a-zA-Z0-9.-]{2,64}$',
          ).hasMatch(upi.text.trim())
          ? null
          : 'UPI ID needs @ – like name@bank';
    }
    if (name.text.trim().length < 2 || bank.text.trim().length < 2) {
      return 'Fill all boxes to save';
    }
    if (!RegExp(r'^\d{9,18}$').hasMatch(number.text)) {
      return 'Enter an account number with 9–18 digits';
    }
    if (number.text != repeat.text) {
      return 'Numbers are not the same. Check again.';
    }
    if (!RegExp(
      r'^[A-Z]{4}0[A-Z0-9]{6}$',
    ).hasMatch(ifsc.text.trim().toUpperCase())) {
      return 'IFSC has 11 letters and numbers – check it.';
    }
    return null;
  }

  void _save() {
    final failure = validation;
    if (failure != null) {
      setState(() => error = failure);
      return;
    }
    widget.onSave(
      widget.method == 'upi'
          ? {'method': 'upi', 'upiId': upi.text.trim().toLowerCase()}
          : {
              'method': 'bank',
              'name': name.text.trim(),
              'bank': bank.text.trim(),
              'accountNumber': number.text,
              'ifsc': ifsc.text.trim().toUpperCase(),
              'accountType': accountType,
            },
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool digits = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: digits ? TextInputType.number : TextInputType.text,
      inputFormatters: digits
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(18),
            ]
          : null,
      onChanged: (_) => setState(() => error = null),
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.method == 'upi' ? 'Type UPI ID' : 'Type bank details',
        style: const TextStyle(fontSize: 17, color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      if (widget.method == 'upi')
        _field('UPI ID', upi)
      else ...[
        Row(
          children: [
            for (final type in ['savings', 'current'])
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(type == 'savings' ? 'Savings' : 'Current'),
                  selected: accountType == type,
                  onSelected: (_) => setState(() => accountType = type),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _field('Name on account *', name),
        _field('Bank *', bank),
        _field('Account number *', number, digits: true),
        _field('Type account number again *', repeat, digits: true),
        _field('IFSC code *', ifsc),
      ],
      if (error != null)
        Text(error!, style: const TextStyle(color: AppColors.error)),
      const SizedBox(height: 12),
      const Text(
        'Details are saved for review, not bank or UPI verification.',
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: _save,
          child: const Text('Save details'),
        ),
      ),
    ],
  );
}
