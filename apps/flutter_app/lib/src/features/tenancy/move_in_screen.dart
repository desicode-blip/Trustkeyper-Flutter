import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../agreement_copies/agreement_copy_screen.dart';
import '../broker/data/private_documents.dart';
import '../broker/presentation/private_documents_screen.dart';
import '../inspections/inspection_gateway.dart';
import '../inspections/inspection_screen.dart';
import '../participants/presentation/participant_workspace_screen.dart';
import '../participants/data/participant_workspace.dart';
import 'tenancy_gateway.dart';
import 'move_out_screen.dart';
import '../payments/presentation/rent_payment_screen.dart';

class MoveInScreen extends StatefulWidget {
  const MoveInScreen({
    required this.agreementId,
    required this.role,
    this.gateway,
    this.photos,
    this.camera,
    this.offline = false,
    this.initialPage = 'checklist',
    super.key,
  });
  final String agreementId;
  final String role;
  final TenancyGateway? gateway;
  final InspectionGateway? photos;
  final Future<DocumentFile?> Function()? camera;
  final bool offline;
  final String initialPage;
  @override
  State<MoveInScreen> createState() => _MoveInScreenState();
}

class _MoveInScreenState extends State<MoveInScreen> {
  late final gateway = widget.gateway ?? FirebaseTenancyGateway();
  late final photos = widget.photos ?? FirebaseInspectionGateway();
  StreamSubscription<TenancyRecord>? subscription;
  TenancyRecord? data;
  String? error;
  late String page = widget.initialPage;
  String? selectedRoom;
  String? recipient;
  bool busy = false;
  bool noGas = false;
  bool confirmedCount = false;
  bool lockInAcknowledged = false;
  int bedroomCount = 2;
  int washroomCount = 2;
  bool hasBalcony = true;
  int generation = 0;
  String? confirmationCode;
  String? confirmationIdentity;
  int? codeExpiry;
  Timer? expiryTimer;
  bool privateDialog = false;
  Map<String, dynamic>? retry;
  final readings = {
    for (final kind in ['electricity', 'water', 'gas'])
      kind: TextEditingController(),
  };
  final meterPhotos = <String, String>{};
  final thumbnails = <String, Future<DocumentFile>>{};
  final counts = {
    'mainDoor': 0,
    'bedrooms': 0,
    'letterBox': 0,
    'parkingCard': 0,
  };
  final code = TextEditingController();
  final reason = TextEditingController();
  final leaving = <String>{};
  DateTime? moveOutDate;
  String requestedBy = 'tenant';
  String? rentPerson;
  late String rentAction = widget.role == 'tenant'
      ? 'rent_promise'
      : widget.role == 'owner'
      ? 'rent_extension'
      : 'rent_call';
  DateTime? rentDate;
  final rentNote = TextEditingController();
  bool spokeToTenant = false;
  bool ownerInformed = false;
  bool formChanged = false;
  final formFingerprints = <String, String>{};

  Map<String, String> _formFingerprints(TenancyRecord record) => {
    'meters': jsonEncode(record.map('meters')),
    'keys': jsonEncode([record.map('keys'), record.map('challenge')]),
    'notice': jsonEncode(record.map('notice')),
    'rent': jsonEncode(record.rows('rent')),
  };

  void _reloadForm() {
    if (data == null) return;
    final record = data!;
    if (page == 'meters') {
      final saved = record.map('meters');
      noGas = saved?['noGas'] == true;
      meterPhotos.clear();
      for (final kind in readings.keys) {
        final meter = saved?[kind];
        readings[kind]!.text = meter is Map
            ? meter['reading'] as String? ?? ''
            : '';
        if (meter is Map && meter['checkId'] is String) {
          meterPhotos[kind] = meter['checkId'] as String;
        }
      }
    } else if (page == 'keys') {
      final saved = record.map('keys') ?? {};
      for (final kind in counts.keys) {
        counts[kind] = (saved[kind] as num?)?.toInt() ?? 0;
      }
      recipient = record.rows('payments').firstOrNull?['personId'] as String?;
    } else if (page == 'rent') {
      rentNote.clear();
      rentDate = null;
      spokeToTenant = false;
      ownerInformed = false;
      rentPerson = null;
    } else if (page == 'notice') {
      reason.clear();
      leaving.clear();
      lockInAcknowledged = false;
      moveOutDate = DateTime.tryParse(record.text('earliestMoveOutDate'));
      if (record.text('myPersonId').isNotEmpty) {
        leaving.add(record.text('myPersonId'));
      }
    }
    formChanged = false;
  }

  @override
  void initState() {
    super.initState();
    requestedBy = widget.role == 'owner' ? 'owner' : 'tenant';
    subscription = gateway
        .watch(widget.agreementId, widget.role)
        .listen(
          (record) {
            if (!mounted) return;
            final first = data == null;
            final fingerprints = _formFingerprints(record);
            if (!first &&
                !busy &&
                fingerprints.containsKey(page) &&
                fingerprints[page] != formFingerprints[page]) {
              formChanged = true;
            }
            formFingerprints.addAll(fingerprints);
            final nextIdentity = jsonEncode([
              record.map('challenge')?['id'],
              record.map('keys'),
            ]);
            if (confirmationIdentity != nextIdentity ||
                record.text('phase') == 'active') {
              confirmationCode = null;
              codeExpiry = null;
              confirmedCount = false;
              code.clear();
            }
            confirmationIdentity = nextIdentity;
            setState(() {
              data = record;
              error = null;
              if (first) {
                final savedMeters = record.map('meters');
                noGas = savedMeters?['noGas'] == true;
                for (final kind in readings.keys) {
                  final meter = savedMeters?[kind];
                  if (meter is Map) {
                    readings[kind]!.text = meter['reading'] as String? ?? '';
                    if (meter['checkId'] is String) {
                      meterPhotos[kind] = meter['checkId'] as String;
                    }
                  }
                }
                final savedKeys = record.map('keys');
                if (savedKeys != null) {
                  for (final kind in counts.keys) {
                    counts[kind] = (savedKeys[kind] as num?)?.toInt() ?? 0;
                  }
                }
                recipient =
                    record.rows('payments').firstOrNull?['personId'] as String?;
                moveOutDate = DateTime.tryParse(
                  record.text('earliestMoveOutDate'),
                );
                if (record.text('myPersonId').isNotEmpty) {
                  leaving.add(record.text('myPersonId'));
                }
              }
              if (record.text('phase') == 'active' && page == 'confirm') {
                page = 'complete';
              }
            });
          },
          onError: (Object failure) {
            if (!mounted) return;
            generation++;
            if (privateDialog) Navigator.of(context).pop();
            setState(() {
              data = null;
              error = _message(failure);
              busy = false;
              confirmationCode = null;
              confirmationIdentity = null;
              codeExpiry = null;
              confirmedCount = false;
              meterPhotos.clear();
              thumbnails.clear();
              retry = null;
              code.clear();
              reason.clear();
              rentNote.clear();
              rentPerson = null;
              rentDate = null;
              spokeToTenant = false;
              ownerInformed = false;
              lockInAcknowledged = false;
              formChanged = false;
              formFingerprints.clear();
              leaving.clear();
              recipient = null;
              for (final controller in readings.values) {
                controller.clear();
              }
              for (final kind in counts.keys) {
                counts[kind] = 0;
              }
            });
          },
        );
    expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          codeExpiry != null &&
          DateTime.now().millisecondsSinceEpoch >= codeExpiry!) {
        setState(() {
          confirmationCode = null;
          codeExpiry = null;
        });
      }
    });
  }

  @override
  void dispose() {
    generation++;
    subscription?.cancel();
    expiryTimer?.cancel();
    for (final controller in readings.values) {
      controller.dispose();
    }
    code.dispose();
    reason.dispose();
    rentNote.dispose();
    super.dispose();
  }

  String _message(Object failure) => failure is FirebaseFunctionsException
      ? failure.message ?? 'This action could not be completed. Retry.'
      : failure is StateError
      ? failure.message.toString()
      : 'This action could not be completed. Check your connection and retry.';

  void _open(String value) => setState(() {
    page = value;
    confirmationCode = null;
    if (data != null && _formFingerprints(data!).containsKey(value)) {
      _reloadForm();
    } else {
      formChanged = false;
    }
  });

  Future<void> _record(
    String action,
    Map<String, dynamic> payload, {
    String? next,
  }) async {
    if (data == null || busy) return;
    if (formChanged) {
      setState(
        () => error =
            'This form changed on another device. Reload the latest details before saving.',
      );
      return;
    }
    if (retry != null) {
      setState(
        () => error =
            'Retry the saved action or discard its local retry before changing the form.',
      );
      return;
    }
    retry =
        jsonDecode(
              jsonEncode({
                'agreementId': widget.agreementId,
                'role': widget.role,
                'version': data!.number('version'),
                'operationId': newRepairReportId(),
                'action': action,
                'payload': payload,
              }),
            )
            as Map<String, dynamic>;
    await _submit(next);
  }

  Future<void> _submit(String? next) async {
    if (retry == null || busy || data == null) return;
    final active = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await gateway.record(retry!);
      if (!mounted || active != generation) return;
      retry = null;
      if (result['codeAccepted'] == false) {
        setState(
          () => error =
              result['message'] as String? ?? 'That code is not correct.',
        );
      } else {
        await gateway.refresh(widget.agreementId, widget.role);
        if (mounted && active == generation && next != null) _open(next);
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() => error = _message(failure));
      }
    } finally {
      if (mounted && active == generation) setState(() => busy = false);
    }
  }

  Future<void> _review(String checkId) async {
    final active = generation;
    setState(() => busy = true);
    try {
      final file = await photos.photo(data!.text('propertyId'), checkId);
      if (!mounted || active != generation || data == null) return;
      privateDialog = true;
      try {
        await reviewPrivateDocument(context, file, upload: false);
      } finally {
        privateDialog = false;
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() => error = _message(failure));
      }
    } finally {
      if (mounted && active == generation) setState(() => busy = false);
    }
  }

  Future<void> _capture(
    String room,
    String title,
    String itemId, {
    String? meter,
  }) async {
    if (data == null || busy || !data!.flag('canEdit')) return;
    final active = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final grant = await photos.begin({
        'propertyId': data!.text('propertyId'),
        'agreementId': widget.agreementId,
        'role': 'broker',
        'room': room,
        'title': title,
        'note': '',
        'source': 'camera',
        'operationId': newRepairReportId(),
        'purpose': meter == null ? 'move_in' : 'move_in_meter',
        'itemId': itemId,
      });
      if (!mounted || active != generation || data == null) return;
      final original =
          await (widget.camera?.call() ?? pickPrivateDocument(camera: true));
      if (!mounted ||
          active != generation ||
          data == null ||
          original == null) {
        return;
      }
      final stamped = await stampInspectionPhoto(original, grant);
      if (!mounted || active != generation || data == null) return;
      privateDialog = true;
      bool approved;
      try {
        approved = await reviewPrivateDocument(context, stamped, upload: true);
      } finally {
        privateDialog = false;
      }
      if (!mounted || active != generation || data == null || !approved) return;
      await photos.save(grant, stamped);
      if (!mounted || active != generation || data == null) return;
      if (meter != null) {
        setState(() => meterPhotos[meter] = grant['checkId'] as String);
      }
      await gateway.refresh(widget.agreementId, widget.role);
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() => error = _message(failure));
      }
    } finally {
      if (mounted && active == generation) setState(() => busy = false);
    }
  }

  Future<void> _absent(Map<String, dynamic> item) async {
    final note = TextEditingController();
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${item['title']} not present'),
          content: TextField(
            controller: note,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Explain what is absent',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, note.text),
              child: const Text('Save reason'),
            ),
          ],
        ),
      );
      if (value != null && mounted) {
        await _record('absent', {'itemId': item['id'], 'reason': value});
      }
    } finally {
      note.dispose();
    }
  }

  Future<void> _issueCode() async {
    final active = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await gateway.issueCode({
        'agreementId': widget.agreementId,
        'role': widget.role,
        'countsConfirmed': confirmedCount,
      });
      if (mounted &&
          active == generation &&
          data != null &&
          result['challengeId'] == data!.map('challenge')?['id'] &&
          confirmedCount &&
          data!.flag('canIssueCode')) {
        setState(() {
          confirmationCode = result['code'] as String;
          codeExpiry = result['expiresAtMs'] as int;
        });
      }
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() => error = _message(failure));
      }
    } finally {
      if (mounted && active == generation) setState(() => busy = false);
    }
  }

  String get title => switch (page) {
    'money' => 'Deposit and first rent',
    'rooms' => 'Move-in photos',
    'items' => selectedRoom ?? 'Move-in photos',
    'meters' => 'Meter readings',
    'keys' => 'Hand over keys',
    'confirm' => 'Confirm keys',
    'complete' => 'Moved in!',
    'notice' => 'When will you move out?',
    'rent' => widget.role == 'owner' ? 'Rent yet to be paid' : 'Rent follow-up',
    _ => 'Move-in',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.outlined(
                        onPressed: busy
                            ? null
                            : () {
                                if (page == 'checklist') {
                                  Navigator.of(context).maybePop();
                                } else {
                                  _open(
                                    page == 'items' ? 'rooms' : 'checklist',
                                  );
                                }
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.offline)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 5),
                  child: Text(
                    'OFFLINE TEST · No login, money, SMS or real keys',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              Expanded(
                child: data == null
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          if (error == null)
                            const Center(child: CircularProgressIndicator())
                          else ...[
                            Text(
                              error!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => gateway.refresh(
                                widget.agreementId,
                                widget.role,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                error!,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                          if (retry != null && !busy)
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _submit(null),
                                  child: const Text('Retry saved action'),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    retry = null;
                                    error = null;
                                  }),
                                  child: const Text('Discard local retry'),
                                ),
                              ],
                            ),
                          if (busy) const LinearProgressIndicator(),
                          if (formChanged) ...[
                            _note(
                              'This form changed on another device. Reload latest details to replace your unsaved input.',
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(_reloadForm),
                              child: const Text('Reload latest details'),
                            ),
                          ],
                          ...switch (page) {
                            'money' => _money(),
                            'rooms' => _rooms(),
                            'items' => _items(),
                            'meters' => _meters(),
                            'keys' => _keys(),
                            'confirm' => _confirmation(),
                            'complete' => _complete(),
                            'notice' => _notice(),
                            'rent' => _rent(),
                            _ => _checklist(),
                          },
                        ],
                      ),
              ),
              if (data != null && _footer() != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: _footer()!,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _note(String value) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F9FD),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      value,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.muted,
        height: 1.45,
      ),
    ),
  );
  Widget _row(
    IconData icon,
    String heading,
    String detail,
    bool done,
    VoidCallback? tap, {
    bool highlight = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE8EFF7))),
    ),
    child: InkWell(
      onTap: busy ? null : tap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: done
                ? const Color(0xFF27AE60)
                : highlight
                ? AppColors.primary
                : Colors.white,
            child: Icon(
              done ? Icons.check : icon,
              color: done || highlight ? Colors.white : AppColors.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (done)
            _badge('Done', true)
          else if (highlight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Do it',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    ),
  );
  Widget _badge(String value, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: done ? const Color(0xFFE5F7EF) : const Color(0xFFE9EFFB),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.check, size: 14, color: Color(0xFF087C57)),
          ),
        Text(
          value.replaceFirst('✓ ', ''),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: done ? const Color(0xFF087C57) : AppColors.primary,
          ),
        ),
      ],
    ),
  );

  List<Widget> _checklist() {
    final current = data!;
    final completed =
        1 +
        [
          current.flag('moneyComplete'),
          current.flag('photoComplete'),
          current.flag('meterComplete'),
          current.text('phase') == 'active',
        ].where((value) => value).length;
    return [
      Text(
        '${current.text('address')} · ${DateFormat('d MMM yyyy').format(DateTime.parse(current.text('startDate')))}',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(child: Text('Move-in steps')),
          Text(
            '$completed of 5 done',
            style: const TextStyle(
              color: Color(0xFF087C57),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: List.generate(
          5,
          (index) => Expanded(
            child: Container(
              height: 8,
              margin: EdgeInsets.only(right: index == 4 ? 0 : 4),
              decoration: BoxDecoration(
                color: index < completed
                    ? const Color(0xFF27AE60)
                    : const Color(0xFFDCE6F7),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _row(
        Icons.description_outlined,
        'Agreement signed',
        'Current signed original is ready',
        true,
        widget.offline
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AgreementCopyScreen(
                    agreementId: widget.agreementId,
                    revision: current.number('revision'),
                    demo: false,
                    role: widget.role,
                  ),
                ),
              ),
      ),
      _row(
        Icons.account_balance_wallet_outlined,
        'Deposit and first rent',
        '${current.rows('payments').where((person) => person['paid'] == true).length} of ${current.rows('payments').length} tenants paid',
        current.flag('moneyComplete'),
        () => _open('money'),
        highlight: !current.flag('moneyComplete'),
      ),
      _row(
        Icons.camera_alt_outlined,
        'Move-in photos',
        '${current.recordedItems} of ${current.items.length} items recorded',
        current.flag('photoComplete'),
        () => _open('rooms'),
      ),
      _row(
        Icons.speed_outlined,
        'Meter readings',
        'Electricity, water, gas',
        current.flag('meterComplete'),
        () => _open('meters'),
      ),
      _row(
        Icons.key_outlined,
        'Hand over keys',
        current.text('phase') == 'active'
            ? 'Tenant confirmed the key count'
            : 'Tenant confirms the count with a private code',
        current.text('phase') == 'active',
        () => _open(
          current.text('phase') == 'active'
              ? 'complete'
              : current.flag('canIssueCode')
              ? 'confirm'
              : 'keys',
        ),
      ),
      _note(
        'Do these on move-in day at the flat. Tenant and owner see the saved record. TEST payments never release real keys.',
      ),
      if (current.text('phase') == 'active') ...[
        OutlinedButton.icon(
          onPressed: busy ? null : () => _open('rent'),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Rent follow-up and more time'),
        ),
        if (current.text('nextInspectionDate').isNotEmpty)
          Text('Next photo check: ${current.text('nextInspectionDate')}'),
        const SizedBox(height: 16),
        if (current.map('notice') != null)
          _note(
            'Move-out notice received for ${current.map('notice')!['date']}. No deposit refund has been recorded.',
          ),
        if (current.map('notice') == null)
          OutlinedButton(
            onPressed: busy ? null : () => _open('notice'),
            child: Text(
              widget.role == 'tenant' ? 'I want to move out' : 'Start move-out',
            ),
          ),
      ],
    ];
  }

  List<Widget> _money() => [
    const Text(
      'Tenants pay in their app',
      style: TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 20),
    for (final person in data!.rows('payments'))
      _row(
        Icons.person_outline,
        person['name'] as String,
        person['amountPaise'] is int
            ? '${workspaceMoney(person['amountPaise'] as int)} · ${person['month']}'
            : 'Agreement ended — team review required',
        person['paid'] == true,
        null,
      ),
    _note(
      'Hand over keys only after every tenant has paid. Only server-verified LIVE captures count here; a TEST receipt is not money received.',
    ),
  ];

  List<Widget> _rooms() => [
    if (data!.map('roomConfiguration') == null) ...[
      _note(
        'Confirm the physical room layout at the flat before taking official move-in evidence. Suggested counts are not a confirmed inspection.',
      ),
      if (data!.flag('canEdit')) ...[
        DropdownButtonFormField<int>(
          initialValue: bedroomCount,
          decoration: const InputDecoration(labelText: 'Actual bedrooms'),
          items: List.generate(
            10,
            (count) => DropdownMenuItem(value: count, child: Text('$count')),
          ),
          onChanged: busy
              ? null
              : (value) => setState(() => bedroomCount = value!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: washroomCount,
          decoration: const InputDecoration(labelText: 'Actual washrooms'),
          items: List.generate(
            9,
            (index) =>
                DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
          ),
          onChanged: busy
              ? null
              : (value) => setState(() => washroomCount = value!),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: hasBalcony,
          title: const Text('Balcony / utility area is present'),
          onChanged: busy
              ? null
              : (value) => setState(() => hasBalcony = value!),
        ),
        FilledButton(
          onPressed: busy || retry != null
              ? null
              : () => _record('rooms', {
                  'bedrooms': bedroomCount,
                  'washrooms': washroomCount,
                  'balcony': hasBalcony,
                  'confirmedPhysicalLayout': true,
                }),
          child: const Text('Confirm room layout'),
        ),
      ],
      const SizedBox(height: 20),
    ],
    Text(
      '${data!.recordedItems} of ${data!.items.length} items recorded',
      style: const TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 20),
    if (data!.rows('rooms').isEmpty)
      _note(
        'The saved agreement has no valid room plan. Ask the team to correct it; do not skip the photo gate.',
      ),
    for (final room in data!.rows('rooms'))
      Builder(
        builder: (context) {
          final items = (room['items'] as List).whereType<Map>().toList();
          final done = items
              .where(
                (item) =>
                    item['checkId'] != null || item['absentReason'] != null,
              )
              .length;
          return InkWell(
            onTap: busy
                ? null
                : () {
                    selectedRoom = room['room'] as String;
                    _open('items');
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE8EFF7))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 44,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SvgPicture.string(
                      inspectionRoomIcon(room['room'] as String),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room['room'] as String,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$done of ${items.length} items',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _badge(
                    done == items.length
                        ? '✓ Done'
                        : done > 0
                        ? 'Going on'
                        : 'To do',
                    done == items.length,
                  ),
                ],
              ),
            ),
          );
        },
      ),
  ];

  List<Widget> _items() {
    final room = data!
        .rows('rooms')
        .where((room) => room['room'] == selectedRoom)
        .firstOrNull;
    if (room == null) {
      return [_note('Choose a room from this home’s checklist.')];
    }
    return [
      const Text(
        'Take a new photo of each item. Date, time, name and role are stamped on your record.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      for (final item in (room['items'] as List).whereType<Map>())
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8EFF7))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item['title'] as String,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item['checkId'] != null)
                    IconButton(
                      onPressed: busy
                          ? null
                          : () => _review(item['checkId'] as String),
                      tooltip: 'View ${item['title']}',
                      icon: const Icon(Icons.image_outlined),
                    ),
                  if (data!.flag('canEdit') &&
                      data!.map('roomConfiguration') != null &&
                      data!.text('phase') != 'active')
                    IconButton(
                      onPressed: busy
                          ? null
                          : () => _capture(
                              selectedRoom!,
                              item['title'] as String,
                              item['id'] as String,
                            ),
                      tooltip: 'Take photo of ${item['title']}',
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              if (item['checkId'] != null)
                const Text(
                  'Photo saved',
                  style: TextStyle(color: Color(0xFF087C57), fontSize: 13),
                ),
              if (item['absentReason'] != null)
                Text(
                  'Not present: ${item['absentReason']}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              if (item['optional'] == true &&
                  item['checkId'] == null &&
                  data!.flag('canEdit') &&
                  data!.text('phase') != 'active')
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => _absent(Map<String, dynamic>.from(item)),
                    child: const Text('Not present here'),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _meters() => [
    const Text(
      'Take a photo, then type the number',
      style: TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 20),
    for (final kind in ['electricity', 'water', if (!noGas) 'gas'])
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDCE4EF)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 82,
              height: 70,
              child: OutlinedButton(
                onPressed:
                    busy ||
                        !data!.flag('canEdit') ||
                        data!.text('phase') == 'active'
                    ? (meterPhotos[kind] != null && !busy
                          ? () => _review(meterPhotos[kind]!)
                          : null)
                    : () => _capture(
                        'Fixtures & fittings',
                        '${kind[0].toUpperCase()}${kind.substring(1)} meter',
                        kind,
                        meter: kind,
                      ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: meterPhotos[kind] == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            meterPhotos[kind] == null
                                ? Icons.camera_alt_outlined
                                : Icons.check_circle_outline,
                          ),
                          Text(
                            meterPhotos[kind] == null ? 'Photo' : 'Saved',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    : FutureBuilder<DocumentFile>(
                        key: ValueKey(meterPhotos[kind]),
                        future: thumbnails.putIfAbsent(
                          meterPhotos[kind]!,
                          () => photos.photo(
                            data!.text('propertyId'),
                            meterPhotos[kind]!,
                          ),
                        ),
                        builder: (context, snapshot) => snapshot.hasData
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  snapshot.data!.bytes,
                                  width: 76,
                                  height: 62,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                snapshot.hasError
                                    ? Icons.image_not_supported_outlined
                                    : Icons.photo_outlined,
                              ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == 'gas'
                        ? 'Gas (if any)'
                        : '${kind[0].toUpperCase()}${kind.substring(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: readings[kind],
                    enabled:
                        !busy &&
                        data!.flag('canEdit') &&
                        data!.text('phase') != 'active',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      suffixText: kind == 'water' ? 'litres' : 'units',
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: noGas,
      onChanged:
          !busy && data!.flag('canEdit') && data!.text('phase') != 'active'
          ? (value) => setState(() => noGas = value!)
          : null,
      title: const Text(
        'No gas meter here',
        style: TextStyle(fontSize: 15, color: AppColors.primary),
      ),
    ),
  ];

  int get keyTotal => counts.values.fold(0, (total, count) => total + count);
  List<Widget> _keys() => [
    const Text(
      'Count the keys you give',
      style: TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 20),
    if (!data!.flag('canHandOver'))
      _note(
        'Key handover is locked until the current signed original, every tenant’s LIVE payment, all room records and meter readings are complete on move-in day.',
      ),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDCE4EF)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (final entry in {
            'mainDoor': 'Main door',
            'bedrooms': 'Bedroom doors',
            'letterBox': 'Letter box',
            'parkingCard': 'Car parking card',
          }.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.key_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        busy ||
                            !data!.flag('canHandOver') ||
                            counts[entry.key] == 0
                        ? null
                        : () => setState(
                            () => counts[entry.key] = counts[entry.key]! - 1,
                          ),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${counts[entry.key]}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        busy ||
                            !data!.flag('canHandOver') ||
                            counts[entry.key]! >= 50
                        ? null
                        : () => setState(
                            () => counts[entry.key] = counts[entry.key]! + 1,
                          ),
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    DropdownButtonFormField<String>(
      initialValue: recipient,
      decoration: const InputDecoration(labelText: 'Tenant receiving the keys'),
      items: data!
          .rows('payments')
          .map(
            (person) => DropdownMenuItem(
              value: person['personId'] as String,
              child: Text(person['name'] as String),
            ),
          )
          .toList(),
      onChanged: busy || !data!.flag('canHandOver')
          ? null
          : (value) => setState(() => recipient = value),
    ),
    _note(
      'The selected tenant opens this home in their account, confirms $keyTotal keys and gets a private six-digit code to tell you. No SMS has been sent by this step.',
    ),
  ];

  List<Widget> _confirmation() {
    final challenge = data!.map('challenge');
    final saved = data!.map('keys') ?? {};
    final total = saved.values.whereType<num>().fold<int>(
      0,
      (total, count) => total + count.toInt(),
    );
    return [
      Text(
        widget.role == 'tenant'
            ? 'Check the keys you received'
            : 'Ask ${challenge?['name'] ?? 'the receiving tenant'} for the code',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 24),
      _badge('$total keys', false),
      const SizedBox(height: 20),
      for (final entry in saved.entries)
        Text(
          '${{'mainDoor': 'Main door', 'bedrooms': 'Bedroom doors', 'letterBox': 'Letter box', 'parkingCard': 'Car parking card'}[entry.key] ?? entry.key}: ${entry.value}',
        ),
      const SizedBox(height: 24),
      if (widget.role == 'tenant') ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: confirmedCount,
          onChanged: busy
              ? null
              : (value) => setState(() => confirmedCount = value!),
          title: const Text(
            'I received this exact number of keys and access cards.',
          ),
        ),
        if (confirmationCode != null) ...[
          SelectableText(
            confirmationCode!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 40,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          _note(
            'Tell this code only to your broker after checking the keys. Valid until ${DateFormat('h:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(codeExpiry!))}. Requesting another code invalidates the old one.',
          ),
        ],
      ] else
        TextField(
          controller: code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !busy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Tenant’s six-digit confirmation code',
          ),
        ),
      _note(
        'This is an authenticated app confirmation code, not an Aadhaar OTP or a legal signature. A wrong code never marks the flat rented.',
      ),
    ];
  }

  List<Widget> _complete() => [
    const SizedBox(height: 36),
    const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 76),
    const SizedBox(height: 24),
    Text(
      '${data!.text('address')} is now Rented.',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 24),
    _row(
      Icons.account_balance_wallet_outlined,
      'Money received',
      'Every tenant’s live first payment verified',
      true,
      null,
    ),
    _row(
      Icons.camera_alt_outlined,
      'Move-in record',
      '${data!.recordedItems} room items recorded',
      true,
      () => _open('rooms'),
    ),
    _row(
      Icons.speed_outlined,
      'Meter readings',
      'Saved with private photos',
      true,
      () => _open('meters'),
    ),
    _note(
      'Brokerage and owner payouts are separate financial processes. This screen does not claim a transfer or a bank settlement.',
    ),
  ];

  List<Widget> _notice() {
    if (data!.map('notice') != null) {
      return [
        const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 64),
        const SizedBox(height: 20),
        Text(
          'Notice saved · ${data!.map('notice')!['date']}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        _note(
          'Book the check, compare photos, return keys and review deductions from the saved move-out.',
        ),
        FilledButton(
          onPressed: widget.offline
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MoveOutScreen(
                      agreementId: widget.agreementId,
                      role: widget.role,
                    ),
                  ),
                ),
          child: const Text('Continue move-out'),
        ),
        if (widget.offline)
          _note('Open the move-out journeys from the offline test gallery.'),
      ];
    }
    return [
      Text(
        'Your notice is ${data!.number('noticeMonths')} month(s). Today is ${data!.text('today')}.',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: busy
            ? null
            : () async {
                final earliest = DateTime.parse(
                  data!.text('earliestMoveOutDate'),
                );
                final selected = await showDatePicker(
                  context: context,
                  initialDate: moveOutDate ?? earliest,
                  firstDate: earliest,
                  lastDate: earliest.add(const Duration(days: 330)),
                );
                if (selected != null && mounted) {
                  setState(() => moveOutDate = selected);
                }
              },
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(
          moveOutDate == null
              ? 'Pick a date'
              : DateFormat('d MMM yyyy').format(moveOutDate!),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Who is moving out?',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      for (final person in data!.rows('payments'))
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: leaving.contains(person['personId']),
          onChanged:
              busy ||
                  widget.role == 'tenant' &&
                      person['personId'] == data!.text('myPersonId')
              ? null
              : (value) => setState(() {
                  if (value == true) {
                    leaving.add(person['personId'] as String);
                  } else {
                    leaving.remove(person['personId']);
                  }
                }),
          title: Text(person['name'] as String),
        ),
      if (widget.role == 'broker' || widget.role == 'admin')
        DropdownButtonFormField<String>(
          initialValue: requestedBy,
          decoration: const InputDecoration(
            labelText: 'Who asked for this move-out?',
          ),
          items: const [
            DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
            DropdownMenuItem(value: 'owner', child: Text('Owner')),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() => requestedBy = value!),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: reason,
        enabled: !busy,
        maxLength: 1000,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Why? (optional)'),
      ),
      if (moveOutDate != null &&
          moveOutDate!.isBefore(DateTime.parse(data!.text('lockInEnds')))) ...[
        _note(
          'You are in lock-in until ${data!.text('lockInEnds')}. You may owe additional rent under the signed agreement. Contact the team before deciding.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: lockInAcknowledged,
          onChanged: busy
              ? null
              : (value) => setState(() => lockInAcknowledged = value!),
          title: const Text('I understand the lock-in warning.'),
        ),
      ],
      _note(
        'This saves a notice visible to the linked people and team in the app. It does not send SMS/email, cancel the lease, empty the flat or refund a deposit.',
      ),
    ];
  }

  Widget? _footer() {
    final current = data!;
    VoidCallback? action;
    String? label;
    if (page == 'meters' &&
        current.flag('canEdit') &&
        current.text('phase') != 'active') {
      label = 'Save readings';
      action = () => _record('meters', {
        'noGas': noGas,
        for (final kind in ['electricity', 'water', if (!noGas) 'gas'])
          kind: {
            'reading': readings[kind]!.text.trim(),
            'checkId': meterPhotos[kind],
          },
      }, next: 'checklist');
    }
    if (page == 'keys' && current.flag('canHandOver')) {
      label = 'Prepare tenant confirmation';
      action = () => _record('keys', {
        'counts': counts,
        'personId': recipient,
      }, next: 'confirm');
    }
    if (page == 'keys' && current.flag('canIssueCode')) {
      label = 'Confirm my keys';
      action = () => _open('confirm');
    }
    if (page == 'confirm' &&
        widget.role == 'tenant' &&
        current.flag('canIssueCode')) {
      label = 'Get my confirmation code';
      action = confirmedCount ? _issueCode : null;
    }
    if (page == 'confirm' &&
        current.flag('canEdit') &&
        current.map('challenge') != null) {
      label = 'Confirm';
      action = () => _record('confirm', {
        'challengeId': current.map('challenge')!['id'],
        'code': code.text,
      }, next: 'complete');
    }
    if (page == 'complete') {
      label = 'Go to home';
      action = () => Navigator.of(context).maybePop();
    }
    if (page == 'notice' && current.map('notice') == null) {
      label = 'Send notice';
      action = moveOutDate != null && leaving.isNotEmpty
          ? () => _record('notice', {
              'date': DateFormat('yyyy-MM-dd').format(moveOutDate!),
              'personIds': leaving.toList()..sort(),
              'requestedBy': requestedBy,
              'reason': reason.text,
              'lockInAcknowledged': lockInAcknowledged,
            }, next: 'checklist')
          : null;
    }
    if (page == 'rent' &&
        current.text('phase') == 'active' &&
        _selectedRent != null) {
      final row = _selectedRent!;
      label = switch (rentAction) {
        'rent_call' => 'Save call notes',
        'rent_promise' => 'Save my payment promise',
        _ => 'Give more time',
      };
      final enabled = rentAction == 'rent_call'
          ? spokeToTenant
          : rentDate != null &&
                (rentAction != 'rent_extension' ||
                    widget.role == 'owner' ||
                    ownerInformed);
      action = enabled
          ? () => _record(rentAction, {
              'personId': row['personId'],
              'month': row['month'],
              'note': rentNote.text,
              'contacted': spokeToTenant,
              'ownerInformed': ownerInformed,
              if (rentDate != null)
                'date': DateFormat('yyyy-MM-dd').format(rentDate!),
            })
          : null;
    }
    if (label == null) return null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: busy || retry != null || formChanged ? null : action,
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _unpaidRent => data!
      .rows('rent')
      .where(
        (row) =>
            row['status'] == 'unpaid' &&
            (widget.role != 'tenant' ||
                row['personId'] == data!.text('myPersonId')),
      )
      .toList();
  Map<String, dynamic>? get _selectedRent =>
      _unpaidRent.where((row) => row['personId'] == rentPerson).firstOrNull ??
      _unpaidRent.firstOrNull;

  List<Widget> _rent() => [
    Text(data!.text('address'), style: const TextStyle(color: AppColors.muted)),
    if (data!.text('phase') != 'active')
      _note(
        'A live tenancy has not started. TEST payments and demo agreements do not create live rent obligations in this workflow.',
      ),
    for (final row in data!.rows('rent'))
      Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:
              widget.role == 'tenant' &&
                  (row['daysLate'] as int? ?? 0) > 0 &&
                  row['status'] == 'unpaid'
              ? const Color(0xFFFFF2F2)
              : const Color(0xFFF6F9FD),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['name'] as String,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              row['status'] == 'paid'
                  ? 'Rent paid'
                  : workspaceMoney(row['amountPaise'] as int),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            if (row['status'] != 'paid') ...[
              Text(
                widget.role == 'owner'
                    ? 'Rent yet to be paid · by ${row['deadline']}'
                    : '${row['month']} · Pay by ${row['deadline']}',
              ),
              if (widget.role != 'owner' && (row['daysLate'] as int? ?? 0) > 0)
                Text('${row['daysLate']} days late · No late fee'),
              if (row['manualNoticeReviewRequired'] == true)
                _note(
                  '30 days unpaid: the team must review the signed agreement and any extension before serving a notice. No notice has been automatically sent.',
                ),
              if (row['followUp'] is Map &&
                  (row['followUp'] as Map)['extension'] is Map)
                Text(
                  'More time granted until ${((row['followUp'] as Map)['extension'] as Map)['date']}',
                ),
              if (row['followUp'] is Map &&
                  (row['followUp'] as Map)['promise'] is Map)
                Text(
                  'Tenant’s requested payment date: ${((row['followUp'] as Map)['promise'] as Map)['date']}',
                ),
              if (row['followUp'] is Map &&
                  (row['followUp'] as Map)['lastCall'] is Map)
                const Text('Follow-up call notes saved'),
              if (widget.role == 'tenant' &&
                  row['personId'] == data!.text('myPersonId'))
                TextButton(
                  onPressed: busy || widget.offline
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => RentPaymentScreen(
                              agreementId: widget.agreementId,
                              revision: data!.number('revision'),
                            ),
                          ),
                        ),
                  child: const Text('Open payment · TEST gateway'),
                ),
            ],
          ],
        ),
      ),
    if (_selectedRent != null && data!.text('phase') == 'active') ...[
      const SizedBox(height: 24),
      if (widget.role != 'tenant')
        DropdownButtonFormField<String>(
          key: ValueKey(
            _unpaidRent
                .map((row) => '${row['personId']}:${row['month']}')
                .join('|'),
          ),
          initialValue: _selectedRent!['personId'] as String,
          decoration: const InputDecoration(labelText: 'Tenant'),
          items: _unpaidRent
              .map(
                (row) => DropdownMenuItem(
                  value: row['personId'] as String,
                  child: Text(row['name'] as String),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                  rentPerson = value;
                  spokeToTenant = false;
                  ownerInformed = false;
                  rentDate = null;
                  rentNote.clear();
                }),
        ),
      if (widget.role == 'broker' || widget.role == 'admin') ...[
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'rent_call', label: Text('Call notes')),
            ButtonSegment(value: 'rent_extension', label: Text('More time')),
          ],
          selected: {rentAction},
          onSelectionChanged: busy
              ? null
              : (value) => setState(() {
                  rentAction = value.first;
                  ownerInformed = false;
                  rentDate = null;
                  rentNote.clear();
                }),
        ),
      ],
      const SizedBox(height: 16),
      if (rentAction == 'rent_call') ...[
        OutlinedButton.icon(
          onPressed: busy || widget.offline
              ? null
              : () => launchUrl(Uri.parse('tel:${_selectedRent!['phone']}')),
          icon: const Icon(Icons.phone_outlined),
          label: const Text('Call tenant'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: spokeToTenant,
          title: const Text('I spoke to the tenant'),
          onChanged: busy
              ? null
              : (value) => setState(() => spokeToTenant = value!),
        ),
      ] else
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final first = DateTime.parse(
                    data!.text('today'),
                  ).add(const Duration(days: 1));
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: rentDate ?? first,
                    firstDate: first,
                    lastDate: first.add(const Duration(days: 89)),
                  );
                  if (selected != null && mounted) {
                    setState(() => rentDate = selected);
                  }
                },
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            rentDate == null
                ? 'Pick payment date'
                : DateFormat('d MMM yyyy').format(rentDate!),
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: rentNote,
        enabled: !busy,
        maxLength: 1000,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: rentAction == 'rent_call'
              ? 'What did the tenant say?'
              : 'Why is more time needed?',
        ),
      ),
      if (rentAction == 'rent_extension' && widget.role != 'owner')
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: ownerInformed,
          title: const Text('The owner is informed'),
          onChanged: busy
              ? null
              : (value) => setState(() => ownerInformed = value!),
        ),
      _note(
        'The saved update is visible in the app. A promise is not a payment; an extension does not deduct a deposit. SMS, WhatsApp and email delivery are separate and have not been sent.',
      ),
    ],
  ];
}
