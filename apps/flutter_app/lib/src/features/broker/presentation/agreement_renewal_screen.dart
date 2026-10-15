import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../data/agreement_renewals.dart';

class AgreementRenewalScreen extends StatefulWidget {
  const AgreementRenewalScreen({
    this.gateway,
    this.now,
    this.onDraft,
    this.offline = false,
    super.key,
  });
  final AgreementRenewalGateway? gateway;
  final DateTime? now;
  final void Function(String id)? onDraft;
  final bool offline;
  @override
  State<AgreementRenewalScreen> createState() => _AgreementRenewalScreenState();
}

class _AgreementRenewalScreenState extends State<AgreementRenewalScreen> {
  late final gateway = widget.gateway ?? FirebaseAgreementRenewalGateway();
  StreamSubscription<List<RenewalSource>>? subscription;
  final search = TextEditingController();
  List<RenewalSource>? sources;
  RenewalSource? selected;
  String? loadError;
  String? saveError;
  String? operationId;
  bool busy = false;
  int generation = 0;
  DateTime get today => DateUtils.dateOnly(widget.now ?? DateTime.now());
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final request = ++generation;
    subscription?.cancel();
    sources = null;
    loadError = null;
    selected = null;
    operationId = null;
    subscription = gateway.watch().listen(
      (values) {
        if (!mounted || request != generation) return;
        setState(() {
          sources = values;
          loadError = null;
          if (selected != null &&
              !values.any((value) => value.identity == selected!.identity)) {
            selected = null;
            operationId = null;
            saveError =
                'The original changed or is no longer available. Choose it again.';
            busy = false;
          }
        });
      },
      onError: (Object error) {
        if (!mounted || request != generation) return;
        setState(() {
          sources = null;
          selected = null;
          operationId = null;
          busy = false;
          saveError = null;
          loadError = error is StateError
              ? error.message.toString()
              : 'Agreements could not be loaded. Check your account and connection.';
        });
      },
    );
  }

  @override
  void dispose() {
    generation++;
    subscription?.cancel();
    search.dispose();
    super.dispose();
  }

  void _back() {
    if (busy) return;
    if (selected != null) {
      setState(() {
        selected = null;
        saveError = null;
        operationId = null;
      });
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _create() async {
    final source = selected;
    if (source == null || busy || sources == null) return;
    final request = generation;
    operationId ??= renewalOperationId();
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      final result = await gateway.create(source, operationId!);
      if (!mounted ||
          request != generation ||
          selected?.identity != source.identity ||
          sources == null) {
        return;
      }
      final id = result['agreementId'] as String;
      if (result['status'] != 'draft') {
        setState(() {
          busy = false;
          saveError =
              'This renewal has already been sent. See its actual progress in Records.';
        });
        return;
      }
      if (widget.onDraft != null) {
        widget.onDraft!(id);
      } else {
        context.pushReplacement('/broker/draft/${Uri.encodeComponent(id)}');
      }
      if (mounted) setState(() => busy = false);
    } catch (error) {
      if (!mounted ||
          request != generation ||
          selected?.identity != source.identity) {
        return;
      }
      setState(() {
        busy = false;
        saveError = error is FirebaseFunctionsException
            ? error.message
            : 'Renewal could not be saved. Retry without leaving this page.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ApprovedAuthScaffold(
          showBack: false,
          bodyPadding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              children: [
                if (widget.offline) ...[
                  const Text(
                    'OFFLINE TEST · synthetic agreement, no legal signing',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: selected == null ? 1 / 3 : 2 / 3,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: const Color(0xFFDCE5F7),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected == null
                            ? 'Step 1 of 3 · Pick agreement'
                            : 'Step 2 of 3 · Check details',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: widget.offline
                          ? null
                          : () => launchUrl(Uri.parse('tel:+918088516875')),
                      icon: const Icon(Icons.phone_outlined),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          footerBorder: selected != null,
          footerPadding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          footer: selected == null
              ? TextButton(
                  onPressed: widget.offline
                      ? null
                      : () => context.push('/broker/agreement/steps'),
                  child: const Text('Not made on TrustKeyper?  Make a new one'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: busy ? null : _create,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          busy ? 'Saving renewal…' : 'Yes, make new agreement',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Review names, documents, rent and new dates next.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ApprovedBackButton(onPressed: _back),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      selected == null ? 'Renew agreement' : 'Is this correct?',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                selected == null
                    ? 'Which agreement do you want to renew?'
                    : 'From your saved signed agreement.',
                style: const TextStyle(fontSize: 16, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              if (loadError != null) ...[
                Text(loadError!, style: const TextStyle(color: AppColors.body)),
                TextButton(
                  onPressed: () => setState(_listen),
                  child: const Text('Retry'),
                ),
              ] else if (sources == null)
                const Center(child: CircularProgressIndicator())
              else if (selected != null)
                _review(selected!)
              else ...[
                TextField(
                  controller: search,
                  enabled: !busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    hintText: 'House or tenant name',
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ..._list(),
              ],
              if (saveError != null) ...[
                const SizedBox(height: 16),
                Text(
                  saveError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  List<Widget> _list() {
    final query = search.text.trim().toLowerCase();
    final visible = sources!
        .where(
          (source) => '${source.address} ${source.names('tenants')}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    if (sources!.isEmpty) {
      return [
        const Text(
          'Nothing to renew yet',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Agreements you make on TrustKeyper show here after everyone signs. No sample homes are added to your account.',
        ),
      ];
    }
    if (visible.isEmpty) {
      return [const Text('No agreements match this search.')];
    }
    final widgets = <Widget>[];
    for (final ended in [false, true]) {
      final group = visible
          .where((source) => source.end.isBefore(today) == ended)
          .toList();
      if (group.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(
                ended ? Icons.info_outline : Icons.schedule,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                ended ? 'Already ended' : 'Ending soon',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
      for (final source in group) {
        final days = DateUtils.dateOnly(source.end).difference(today).inDays;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: busy
                    ? null
                    : () => setState(() {
                        selected = source;
                        saveError = null;
                        operationId = null;
                      }),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: ended
                              ? AppColors.errorSoft
                              : AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.home_outlined,
                          color: ended
                              ? AppColors.error
                              : AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.address,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tenant: ${source.names('tenants')}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${days < 0
                                  ? 'Ended ${-days} days ago'
                                  : days == 0
                                  ? 'Ends today'
                                  : 'Ends in $days days'} · ${DateFormat('d MMM yyyy').format(source.end)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: ended
                                    ? AppColors.error
                                    : const Color(0xFFA05A00),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _review(RenewalSource source) {
    String money(String key) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: (source.data[key] as int) % 100 == 0 ? 0 : 2,
    ).format((source.data[key] as num) / 100);
    final fields = [
      (Icons.home_outlined, 'House', source.address),
      (Icons.person_outline, 'Owners', source.names('owners')),
      (Icons.people_outline, 'Tenants', source.names('tenants')),
      (Icons.currency_rupee, 'Rent every month', money('monthlyRentPaise')),
      (
        Icons.account_balance_wallet_outlined,
        'Deposit',
        money('securityDepositPaise'),
      ),
      (
        Icons.event_outlined,
        'Old agreement',
        '${DateFormat('d MMM yyyy').format(DateTime.parse(source.data['startDateISO'] as String))} – ${DateFormat('d MMM yyyy').format(source.end)}',
      ),
    ];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          fields[index].$1,
                          color: AppColors.primaryDark,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fields[index].$2,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              fields[index].$3,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < fields.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.autorenew, color: AppColors.primaryDark),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New agreement starts',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      DateFormat('d MMM yyyy').format(source.nextStart),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const Text(
                      'The day after the old one ends',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'Check every person and phone number before sending. Documents, replies, signing and payments need fresh checks. Nothing is carried over as verified or paid.',
          ),
        ),
      ],
    );
  }
}
