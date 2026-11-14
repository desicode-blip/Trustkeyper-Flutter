import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_store.dart';

/// What a token is, in one line (Profile and each property).
const tk2TokenWhy = 'A tenant who likes the house pays this to block it, so no one else takes it.';

/// "Your token amount" in Profile. It is first asked with the broker's first
/// property, then filled in for every new property; each property can change it.
class Tk2TokenScreen extends StatefulWidget {
  const Tk2TokenScreen({required this.store, required this.onDone, super.key});
  final Tk2Store store;
  final VoidCallback onDone;

  @override
  State<Tk2TokenScreen> createState() => _Tk2TokenScreenState();
}

class _Tk2TokenScreenState extends State<Tk2TokenScreen> {
  late final amount = TextEditingController(text: '${widget.store.defaultToken}');
  String? error;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = tk2TokenError(amount.text);
    setState(() => error = n.$2);
    if (n.$2 != null) return;
    setState(() => saving = true);
    await widget.store.setDefaultToken(n.$1);
    if (!mounted) return;
    setState(() => saving = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          OnbHeader(title: 'Your token amount', subtitle: 'Filled in for every new property', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: OnbShadowBody(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                children: [
                  const Text(
                    tk2TokenWhy,
                    style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'We fill this in for every new property. You can change it for any one property.',
                    style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  Tk2TokenField(controller: amount, error: error, onChanged: () => setState(() => error = null)),
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Save', icon: Icons.check, loading: saving, onPressed: saving ? null : _save),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Amount typed, and the red message to show (null when fine).
(int, String?) tk2TokenError(String text) {
  final n = int.tryParse(text.replaceAll(RegExp(r'\D'), '')) ?? 0;
  if (n <= 0) return (0, 'Type the token amount');
  if (n > Tk2Store.maxToken) return (n, 'Token can be up to ${Tk2Store.money(Tk2Store.maxToken)}');
  return (n, null);
}

/// ₹ field for a token amount; the helper shows it in Indian style (₹15,000).
class Tk2TokenField extends StatelessWidget {
  const Tk2TokenField({required this.controller, required this.onChanged, this.error, this.helper, super.key});
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? error;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(controller.text) ?? 0;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter('${Tk2Store.maxToken}'.length)],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: 'Token amount', prefixText: '₹ ', helperText: helper ?? (n > 0 ? Tk2Store.money(n) : null), errorText: error),
    );
  }
}
