import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../broker/data/demo_agreement.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/demo_agreement_screen.dart';
import '../../agreement_copies/agreement_copy_screen.dart';
import '../data/agreement_approvals.dart';
import '../../payments/data/rent_payments.dart';
import '../../payments/presentation/rent_payment_screen.dart';

class RecipientApprovalScreen extends StatefulWidget {
  const RecipientApprovalScreen({required this.token, this.gateway, super.key});
  final String token;
  final AgreementRecipientGateway? gateway;
  @override
  State<RecipientApprovalScreen> createState() =>
      _RecipientApprovalScreenState();
}

class _RecipientApprovalScreenState extends State<RecipientApprovalScreen> {
  AgreementRecipientGateway? gateway;
  ApprovalInfo? info;
  final phone = TextEditingController();
  final code = TextEditingController();
  final note = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  int generation = 0;
  int cooldown = 0;
  bool loading = true;
  bool busy = false;
  bool otpSent = false;
  bool fullOpened = false;
  bool confirming = false;
  bool changing = false;
  bool readAll = false;
  bool agreeTerms = false;
  String category = 'Rent or deposit';
  String? error;
  Map<String, dynamic>? pendingReply;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecipientApprovalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token ||
        oldWidget.gateway != widget.gateway) {
      generation++;
      timer?.cancel();
      gateway = null;
      info = null;
      pendingReply = null;
      phone.clear();
      code.clear();
      note.clear();
      cooldown = 0;
      otpSent = false;
      fullOpened = false;
      confirming = false;
      changing = false;
      readAll = false;
      agreeTerms = false;
      busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    phone.dispose();
    code.dispose();
    note.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool _current(int active) => mounted && active == generation;
  String _message(Object failure) {
    if (failure is DocumentFailure) return failure.message;
    if (failure is FirebaseFunctionsException &&
        [
          'permission-denied',
          'failed-precondition',
          'invalid-argument',
          'aborted',
        ].contains(failure.code)) {
      return failure.message ??
          'Open the current agreement link and verify your phone.';
    }
    if (failure is FirebaseAuthException) {
      return switch (failure.code) {
        'invalid-verification-code' => 'That code is incorrect. Try again.',
        'session-expired' => 'That code expired. Request a new code.',
        'too-many-requests' => 'Too many attempts. Wait before trying again.',
        _ => 'Phone verification failed. Check your connection and retry.',
      };
    }
    return 'Could not confirm this action. Keep this page open and retry.';
  }

  Future<void> _load() async {
    final active = generation;
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      if (!RegExp(r'^[a-f0-9]{64}\.[\w-]{43}$').hasMatch(widget.token)) {
        throw const DocumentFailure(
          'This link is incomplete. Ask the broker for a new link.',
        );
      }
      final service =
          gateway ??
          widget.gateway ??
          await FirebaseAgreementRecipientGateway.create();
      final result = await service.read(widget.token);
      if (result.verified) result.draft;
      if (!_current(active)) return;
      gateway = service;
      setState(() => info = result);
    } catch (failure) {
      if (_current(active)) setState(() => error = _message(failure));
    } finally {
      if (_current(active)) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function(int active) action) async {
    if (busy || loading) return;
    final active = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(active);
    } catch (failure) {
      if (_current(active)) setState(() => error = _message(failure));
    } finally {
      if (_current(active)) setState(() => busy = false);
    }
  }

  Future<void> _sendOtp() => _run((active) async {
    final digits = phone.text.trim();
    if (!RegExp(r'^[1-9]\d{9}$').hasMatch(digits)) {
      throw const DocumentFailure(
        'Enter the ten-digit number on the agreement.',
      );
    }
    final verified = await gateway!.requestOtp('+91$digits');
    if (!_current(active)) return;
    setState(() {
      otpSent = !verified;
      cooldown = 60;
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_current(active) || cooldown <= 1) {
        timer.cancel();
        if (_current(active)) setState(() => cooldown = 0);
      } else {
        setState(() => cooldown--);
      }
    });
    if (verified) await _afterVerification(active);
  });
  Future<void> _afterVerification(int active) async {
    final result = await gateway!.read(widget.token);
    if (!result.verified) {
      await gateway!.signOut();
      throw const DocumentFailure(
        'This phone is not on this link. Use the number ending shown above, or ask the broker to correct it.',
      );
    }
    result.draft;
    if (_current(active)) {
      setState(() {
        info = result;
        otpSent = false;
        code.clear();
      });
    }
  }

  Future<void> _verify() => _run((active) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      throw const DocumentFailure('Enter the six-digit code.');
    }
    await gateway!.verifyOtp(code.text.trim());
    if (_current(active)) await _afterVerification(active);
  });
  Future<void> _reply(String decision) => _run((active) async {
    final current = info!;
    if (pendingReply == null) {
      if (decision == 'agreed' && (!fullOpened || !readAll || !agreeTerms)) {
        throw const DocumentFailure(
          'Open the full demo and check both confirmations.',
        );
      }
      if (decision == 'change_requested' &&
          (note.text.trim().length < 5 || note.text.length > 1000)) {
        throw const DocumentFailure(
          'Describe the change in 5–1000 characters.',
        );
      }
      pendingReply = Map.unmodifiable({
        'operationId': gateway!.operationId(),
        'decision': decision,
        if (decision == 'agreed') ...{'readAll': true, 'agreeTerms': true},
        if (decision == 'change_requested') ...{
          'category': category,
          'note': note.text.trim(),
        },
      });
    }
    final result = await gateway!.reply(widget.token, current, pendingReply!);
    if (!_current(active)) return;
    if (!result.verified ||
        result.revision != current.revision ||
        result.digest != current.digest ||
        result.status != pendingReply!['decision']) {
      throw const DocumentFailure(
        'The server did not confirm this reply. Retry the same reply.',
      );
    }
    result.draft;
    setState(() {
      info = result;
      pendingReply = null;
      confirming = false;
      changing = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(active) && scroll.hasClients) scroll.jumpTo(0);
    });
  });
  Future<void> _readFull() async {
    final active = generation;
    const fields = {
      'propertyAddress': 'property',
      'owners': 'owners',
      'tenants': 'tenants',
      'monthlyRentPaise': 'rent',
      'monthlyMaintenancePaise': 'maintenance',
      'securityDepositPaise': 'deposit',
      'startDateISO': 'term',
      'endDateISO': 'term',
      'rentDueDay': 'due',
      'lockInMonths': 'lock',
      'noticeMonths': 'notice',
      'ownerBrokeragePaise': 'brokerage',
      'tenantBrokeragePaise': 'brokerage',
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DemoAgreementScreen(
          agreement: DemoAgreement(info!.draft),
          changedFields: info!.changed
              .map((key) => fields[key])
              .whereType<String>()
              .toSet(),
        ),
      ),
    );
    if (_current(active)) setState(() => fullOpened = true);
  }

  String _money(int value) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: value % 100 == 0 ? 0 : 2,
  ).format(value / 100);
  Widget _term(String label, String value, {bool changed = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            changed ? '$label · Changed' : label,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              color: changed ? AppColors.successSoft : null,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: changed ? AppColors.success : AppColors.heading,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _group(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: AppColors.primarySoft),
          children[index],
        ],
      ],
    ),
  );

  Widget _people(String role) {
    final people = info!.people.where((person) => person['role'] == role);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primarySoft,
            child: Icon(
              role == 'owner' ? Icons.home_outlined : Icons.people_outline,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == 'owner' ? 'Owners' : 'Tenants',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  people
                      .map(
                        (person) =>
                            '${person['name']}${person['id'] == info!.data['partyId'] ? ' (you)' : ''}',
                      )
                      .join(', '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                if (['agreed', 'change_requested'].contains(info!.status))
                  for (final person in people)
                    Text(
                      '${person['name']} · ${approvalStatus(person['status'] as String)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _footer() {
    if (loading || info?.verified != true || changing || confirming) {
      return null;
    }
    final current = info!;
    final frozen = busy || pendingReply != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.primarySoft)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!['agreed', 'change_requested'].contains(current.status))
              FilledButton(
                onPressed: busy
                    ? null
                    : () => setState(() => confirming = true),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: Text(
                  pendingReply != null
                      ? 'Retry same reply'
                      : 'Yes, I agree · demo only',
                ),
              )
            else
              OutlinedButton(
                onPressed: busy ? null : _load,
                child: const Text('Refresh replies'),
              ),
            if (current.status != 'change_requested')
              TextButton.icon(
                onPressed: frozen
                    ? null
                    : () => setState(() => changing = true),
                icon: const Icon(Icons.edit_outlined, size: 21),
                label: const Text('Something is wrong'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _confirmation() {
    final frozen = busy || pendingReply != null;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Say yes to these demo details?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.error)),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I have read the full demo agreement'),
                  value: readAll,
                  onChanged: frozen || !fullOpened
                      ? null
                      : (value) => setState(() => readAll = value == true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I agree to these demo rent, deposit and terms',
                  ),
                  value: agreeTerms,
                  onChanged: frozen
                      ? null
                      : (value) => setState(() => agreeTerms = value == true),
                ),
                const Text(
                  'Saying yes records a demo reply only. It is not a legal signature or consent to an approved contract.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (!fullOpened)
                  const Text(
                    'Open Read full demo agreement before confirming.',
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed:
                      busy ||
                          (pendingReply == null &&
                              (!readAll || !agreeTerms || !fullOpened))
                      ? null
                      : () => _reply('agreed'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  child: Text(
                    pendingReply != null
                        ? 'Retry same reply'
                        : 'Yes, I agree · demo only',
                  ),
                ),
                TextButton(
                  onPressed: frozen
                      ? null
                      : () => setState(() => confirming = false),
                  child: const Text('Go back'),
                ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      info?.verified == true &&
          info!.data['copyReady'] == true &&
          info!.data['copyMode'] == 'externally_signed'
      ? AgreementCopyScreen(
          agreementId: info!.draft.id,
          revision: info!.revision,
          demo: false,
          role: info!.role,
          reader: () => gateway!.readCopy(info!.draft.id, info!.revision),
          onPayments:
              info!.role == 'tenant' &&
                  gateway is FirebaseAgreementRecipientGateway
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) {
                      final recipient =
                          gateway! as FirebaseAgreementRecipientGateway;
                      return RentPaymentScreen(
                        agreementId: info!.draft.id,
                        revision: info!.revision,
                        gateway: FirebaseRentPaymentGateway(
                          auth: recipient.phone.auth,
                          functions: recipient.phone.functions,
                        ),
                      );
                    },
                  ),
                )
              : null,
        )
      : Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            centerTitle: true,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                info?.verified == true
                    ? (info!.role == 'owner' ? 'Owner' : 'Tenant')
                    : 'TrustKeyper',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            actions: [
              if (gateway != null && !confirming)
                TextButton(
                  onPressed: busy || loading
                      ? null
                      : () => _run((active) async {
                          await gateway!.signOut();
                          if (_current(active)) {
                            pendingReply = null;
                            fullOpened = false;
                            confirming = false;
                            changing = false;
                            readAll = false;
                            agreeTerms = false;
                            await _load();
                          }
                        }),
                  child: const Text('Change number'),
                ),
            ],
          ),
          bottomNavigationBar: _footer(),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    SafeArea(
                      child: ListView(
                        controller: scroll,
                        padding: const EdgeInsets.all(24),
                        children: [
                          if (error != null && !confirming)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          if (info == null) ...[
                            const Text('Agreement unavailable'),
                            FilledButton(
                              onPressed: busy ? null : _load,
                              child: const Text('Retry'),
                            ),
                          ] else if (!info!.verified) ...[
                            Text(
                              '${info!.broker} sent you a rent agreement',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Read the details. Say yes, or ask for a change. No app installation or profile setup is needed.',
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Verify the number ending ${info!.phoneMasked}',
                            ),
                            const Text(
                              'Only people on this agreement can read it. This version is a non-signable demo.',
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: phone,
                              enabled: !busy && !otpSent,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                prefixText: '+91 ',
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: busy || cooldown > 0 ? null : _sendOtp,
                              child: Text(
                                cooldown > 0
                                    ? 'Resend in ${cooldown}s'
                                    : 'Get OTP',
                              ),
                            ),
                            if (otpSent) ...[
                              TextField(
                                controller: code,
                                enabled: !busy,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Six-digit OTP',
                                ),
                              ),
                              FilledButton(
                                onPressed: busy ? null : _verify,
                                child: const Text('Verify and continue'),
                              ),
                            ],
                          ] else
                            ..._verified(),
                          if (busy && !confirming)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ),
                    ),
                    if (confirming) ...[
                      const ModalBarrier(
                        dismissible: false,
                        color: Color(0x80172231),
                      ),
                      _confirmation(),
                    ],
                  ],
                ),
        );
  List<Widget> _verified() {
    final current = info!;
    final draft = current.draft;
    final tenant = draft.tenants
        .where((party) => party.id == current.data['partyId'])
        .firstOrNull;
    final frozen = busy || pendingReply != null;
    final date = DateFormat('d MMM yyyy');
    if (changing) {
      return [
        const Text(
          'What is wrong?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        Text(
          '${current.broker} will check it and send a revised agreement. Everyone must reply again.',
        ),
        const SizedBox(height: 16),
        for (final choice in [
          'Rent or deposit',
          'Dates',
          'Names or details',
          'Rules · lock-in, notice',
          'Brokerage',
          'Other',
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              category == choice
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: AppColors.primary,
            ),
            title: Text(choice),
            onTap: frozen ? null : () => setState(() => category = choice),
          ),
        TextField(
          controller: note,
          enabled: !frozen,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: 'Tell ${current.broker} in a few words',
          ),
        ),
        FilledButton(
          onPressed: busy ? null : () => _reply('change_requested'),
          child: Text(
            pendingReply != null
                ? 'Retry same change request'
                : 'Send change request',
          ),
        ),
        TextButton(
          onPressed: frozen ? null : () => setState(() => changing = false),
          child: const Text('Go back'),
        ),
      ];
    }
    return [
      Text(
        current.status == 'agreed'
            ? 'You said yes'
            : current.status == 'change_requested'
            ? 'Change request sent'
            : 'Check the agreement',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text('${draft.propertyAddress} · sent by ${current.broker}'),
      const SizedBox(height: 12),
      Text(
        'Demo only · version ${current.revision}. Not a legal contract. No signing or payment.',
        style: const TextStyle(color: AppColors.muted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      if (current.data['copyReady'] == true)
        FilledButton.icon(
          onPressed: frozen
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AgreementCopyScreen(
                      agreementId: current.draft.id,
                      revision: current.revision,
                      demo: current.data['copyMode'] == 'demo',
                      reader: () =>
                          gateway!.readCopy(current.draft.id, current.revision),
                      onPayments:
                          current.role == 'tenant' &&
                              gateway is FirebaseAgreementRecipientGateway
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) {
                                  final recipient =
                                      gateway!
                                          as FirebaseAgreementRecipientGateway;
                                  return RentPaymentScreen(
                                    agreementId: current.draft.id,
                                    revision: current.revision,
                                    gateway: FirebaseRentPaymentGateway(
                                      auth: recipient.phone.auth,
                                      functions: recipient.phone.functions,
                                    ),
                                  );
                                },
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
          icon: const Icon(Icons.description_outlined),
          label: Text(
            current.data['copyMode'] == 'demo'
                ? 'Read demo agreement copy'
                : 'Signed agreement',
          ),
        ),
      if (current.changed.isNotEmpty)
        const Text(
          'The agreement changed. Green fields changed since the previous shared version. Every person must read and reply again.',
        ),
      _group([
        _term(
          tenant == null ? 'Rent every month' : 'Your rent share',
          tenant == null
              ? _money(draft.monthlyRentPaise)
              : '${_money(tenant.rentSharePaise)} of ${_money(draft.monthlyRentPaise)}',
          changed: current.changed.any(
            ['monthlyRentPaise', 'tenants'].contains,
          ),
        ),
        _term(
          tenant == null ? 'Deposit' : 'Your deposit share',
          tenant == null
              ? _money(draft.depositPaise)
              : '${_money(tenant.depositSharePaise)} of ${_money(draft.depositPaise)}',
          changed: current.changed.any(
            ['securityDepositPaise', 'tenants'].contains,
          ),
        ),
        _term(
          'Starts · ends',
          '${date.format(draft.startDate!)} · ${date.format(draft.endDate!)}',
          changed: current.changed.any(['startDateISO', 'endDateISO'].contains),
        ),
        _term(
          'Rent paid by',
          '${draft.rentDueDay} of each month',
          changed: current.changed.contains('rentDueDay'),
        ),
        _term(
          'Lock-in · notice',
          '${draft.lockInMonths} months · ${draft.noticeMonths} months',
          changed: current.changed.any(
            ['lockInMonths', 'noticeMonths'].contains,
          ),
        ),
        _term(
          tenant == null
              ? 'Brokerage paid by owners'
              : 'Brokerage paid by tenants',
          _money(
            tenant == null
                ? draft.ownerBrokeragePaise
                : draft.tenantBrokeragePaise,
          ),
          changed: current.changed.any(
            ['ownerBrokeragePaise', 'tenantBrokeragePaise'].contains,
          ),
        ),
      ]),
      const SizedBox(height: 8),
      const Text(
        'Brokerage is the group total, not a verified personal split. Monthly maintenance is in the full demo.',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      const SizedBox(height: 16),
      _group([_people('owner'), _people('tenant')]),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: frozen ? null : _readFull,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primarySoft,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.description_outlined),
        label: const Row(
          children: [
            Expanded(child: Text('Read full demo agreement')),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
      if (current.status == 'change_requested')
        Text('Your note: ${(current.data['reply'] as Map)['note']}'),
    ];
  }
}
