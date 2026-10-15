import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/current_language_label.dart';
import '../../document_requests/presentation/document_request_widgets.dart';
import '../data/tenant_setup.dart';

class TenantSetupScreen extends StatefulWidget {
  const TenantSetupScreen({
    required this.agreementId,
    required this.gateway,
    super.key,
    this.onDone,
    this.initialData,
  });
  final String agreementId;
  final TenantSetupGateway gateway;
  final VoidCallback? onDone;
  final TenantSetupData? initialData;
  @override
  State<TenantSetupScreen> createState() => _TenantSetupScreenState();
}

class _TenantSetupScreenState extends State<TenantSetupScreen> {
  TenantSetupData? data;
  String? failure;
  String? shareError;
  String? noteError;
  String? correction;
  int step = 0;
  int generation = 0;
  bool busy = true;
  final share = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialData case final initial?) {
      data = initial;
      step = _step(initial);
      busy = false;
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(TenantSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agreementId != widget.agreementId ||
        oldWidget.gateway != widget.gateway) {
      data = null;
      correction = null;
      share.clear();
      note.clear();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    generation++;
    share.dispose();
    note.dispose();
    super.dispose();
  }

  String _message(Object error) => error is FirebaseFunctionsException
      ? error.message ?? 'Please try again.'
      : error is TimeoutException
      ? 'This is taking too long. Check your connection and retry.'
      : 'Your home details could not be saved. Please retry.';
  int _step(TenantSetupData result) => result.pending
      ? 4
      : result.complete
      ? 3
      : !result.homeConfirmed
      ? 0
      : !result.flatmatesConfirmed
      ? 1
      : 2;
  Future<void> _load() async {
    final active = ++generation;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final result = await widget.gateway
          .read(widget.agreementId)
          .timeout(const Duration(seconds: 45));
      if (!mounted || generation != active) {
        return;
      }
      setState(() {
        data = result;
        step = _step(result);
        busy = false;
      });
    } catch (error) {
      if (mounted && generation == active) {
        setState(() {
          busy = false;
          failure = _message(error);
        });
      }
    }
  }

  Future<void> _record(String action, {String? kind, int? amount}) async {
    final current = data;
    if (current == null || busy) {
      return;
    }
    final active = ++generation;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final result = await widget.gateway
          .record(
            widget.agreementId,
            current.revision,
            action,
            kind: kind,
            rentSharePaise: amount,
            note: note.text.trim(),
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted || generation != active) {
        return;
      }
      setState(() {
        data = result;
        step = _step(result);
        correction = null;
        busy = false;
      });
    } catch (error) {
      if (mounted && generation == active) {
        setState(() {
          failure = _message(error);
          busy = false;
        });
      }
    }
  }

  void _request() {
    final current = data!;
    final amount = tenantSharePaise(share.text);
    setState(() {
      shareError = correction != 'share'
          ? null
          : amount == null || amount <= 0
          ? 'Enter a valid amount.'
          : amount > current.totalRent
          ? 'Your share cannot exceed the total rent.'
          : amount == current.rent
          ? 'Enter a different share.'
          : null;
      noteError = note.text.trim().length > 2000
          ? 'Keep your note within 2,000 characters.'
          : null;
    });
    if (shareError == null && noteError == null) {
      unawaited(_record('request', kind: correction, amount: amount));
    }
  }

  String _money(int value) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: value % 100 == 0 ? 0 : 2,
  ).format(value / 100);
  String _phone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (value.startsWith('+91') && digits.length == 12) {
      final local = digits.substring(2);
      return '${local.substring(0, 5)} ${local.substring(5)}';
    }
    return value;
  }

  void _done() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.pop(context);
    }
  }

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 26,
          height: 32 / 26,
          color: AppColors.heading,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 17,
          height: 1.3,
          color: AppColors.muted,
        ),
      ),
    ],
  );
  Widget _card(
    Widget child, {
    Color color = AppColors.surfaceMuted,
    bool border = false,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: border ? Border.all(color: AppColors.border) : null,
    ),
    child: child,
  );
  Widget _avatar(String name, {bool property = false}) => property
      ? Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: const DocumentGlyph(
            'building',
            size: 28,
            color: AppColors.primaryDark,
          ),
        )
      : CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFFF1EAFF),
          foregroundColor: const Color(0xFF7A4DFF),
          child: property
              ? const Icon(Icons.apartment_outlined)
              : Text(
                  name
                      .trim()
                      .split(RegExp(r'\s+'))
                      .where((part) => part.isNotEmpty)
                      .take(2)
                      .map((part) => part[0])
                      .join()
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        );
  Widget _body() {
    final current = data!;
    if (correction != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            correction == 'share'
                ? 'Change your share'
                : correction == 'home'
                ? 'Not your home?'
                : 'Something is wrong?',
            correction == 'share'
                ? 'Your broker and our team will check this change.'
                : 'Tell our team what needs correcting.',
          ),
          const SizedBox(height: 22),
          if (correction == 'share') ...[
            TextField(
              controller: share,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Your rent share',
                prefixText: '₹ ',
                errorText: shareError,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total rent ${_money(current.totalRent)}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
          ],
          TextField(
            controller: note,
            enabled: !busy,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Why? (not needed)',
              errorText: noteError,
            ),
          ),
          const SizedBox(height: 16),
          _card(
            const Text(
              'Your current agreement and rent stay unchanged until the corrected agreement is approved.',
            ),
            color: AppColors.warningSoft,
          ),
        ],
      );
    }
    if (step == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Is this your home?',
            'We found this home linked to your phone.',
          ),
          const SizedBox(height: 22),
          _card(
            Row(
              children: [
                _avatar('', property: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.property,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Owner: ${current.owners.join(', ')} · Broker: ${current.brokerName}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Who lives with you?',
            '${current.tenants.length} ${current.tenants.length == 1 ? 'person is' : 'people are'} on this agreement.',
          ),
          const SizedBox(height: 22),
          _card(
            Column(
              children: [
                for (
                  var index = 0;
                  index < current.tenants.length;
                  index++
                ) ...[
                  if (index != 0) const Divider(height: 30),
                  Row(
                    children: [
                      _avatar(current.tenants[index]['name'] as String),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${current.tenants[index]['name']}${current.tenants[index]['you'] == true ? ' (you)' : ''}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              current.tenants[index]['you'] == true
                                  ? 'Tenant'
                                  : 'Flatmate · ${_phone(current.tenants[index]['phone'] as String)}',
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            color: Colors.white,
            border: true,
          ),
        ],
      );
    }
    if (step == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Your rent share',
            current.rent * 2 == current.totalRent
                ? 'You pay half of the total rent.'
                : 'Your share of the rent on this agreement.',
          ),
          const SizedBox(height: 22),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You pay every month',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _money(current.rent),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        current.tenants
                            .map(
                              (tenant) =>
                                  '${tenant['you'] == true ? 'You' : (tenant['name'] as String).trim().split(RegExp(r'\s+')).first} ${_money(tenant['rentSharePaise'] as int)}',
                            )
                            .join(' · '),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Total ${_money(current.totalRent)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            color: AppColors.primarySoft,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.muted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your deposit share: ${_money(current.deposit)} (one time)',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 42),
      child: Column(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: step == 3
                ? AppColors.successSoft
                : AppColors.warningSoft,
            child: Icon(
              step == 3 ? Icons.check_rounded : Icons.schedule,
              size: 48,
              color: step == 3 ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            step == 3 ? 'You are all set!' : 'Sent for OK',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Text(
            step == 3
                ? 'Pay rent, get receipts and ask for repairs – all here.'
                : 'Our team will check your request. Your existing rent share has not changed.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _outline(String label, VoidCallback action) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: busy ? null : action,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 56),
        side: const BorderSide(color: AppColors.primary),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
  );
  Widget _footer() {
    if (data == null) {
      return PrimaryButton(
        label: busy ? 'Loading…' : 'Try again',
        onPressed: busy ? null : _load,
      );
    }
    if (correction != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: busy ? 'Sending…' : 'Send request',
            icon: Icons.send_outlined,
            onPressed: busy ? null : _request,
          ),
          const SizedBox(height: 8),
          _outline(
            'Cancel',
            () => setState(() {
              correction = null;
              shareError = null;
              noteError = null;
            }),
          ),
        ],
      );
    }
    if (step >= 3) {
      return PrimaryButton(
        label: step == 3 ? 'Go to my home' : 'Go to home',
        icon: Icons.chevron_right,
        onPressed: busy ? null : _done,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PrimaryButton(
          label: busy
              ? 'Saving…'
              : [
                  'Yes, this is my home',
                  'Yes, that is right',
                  'Looks good',
                ][step],
          icon: Icons.check,
          onPressed: busy
              ? null
              : () => _record(['home', 'flatmates', 'complete'][step]),
        ),
        const SizedBox(height: 10),
        _outline(
          ['Not my home', 'Something is wrong', 'Change my share'][step],
          () => setState(() {
            correction = ['home', 'flatmates', 'share'][step];
            note.clear();
            share.clear();
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
                child: Row(
                  children: [
                    const AppBrand(height: 34),
                    const Spacer(),
                    const CurrentLanguageLabel(),
                  ],
                ),
              ),
              if (step < 3 && data != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(
                      5,
                      (index) => Expanded(
                        child: Container(
                          height: 6,
                          margin: EdgeInsets.only(right: index == 4 ? 0 : 4),
                          decoration: BoxDecoration(
                            color: index <= step
                                ? AppColors.primary
                                : AppColors.primaryBorder,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (busy) const LinearProgressIndicator(minHeight: 2),
                      if (data != null) _body(),
                      if (failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Text(
                            failure!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                      if (failure != null && data != null)
                        TextButton(
                          onPressed: busy ? null : _load,
                          child: const Text('Reload current agreement'),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                child: _footer(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
