import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/trustkeyper_ui.dart';
import '../broker/data/private_documents.dart';
import '../broker/presentation/private_documents_screen.dart';
import '../inspections/inspection_gateway.dart';
import '../inspections/inspection_screen.dart';
import '../participants/data/participant_workspace.dart';
import 'tenancy_gateway.dart';

class MoveOutScreen extends StatefulWidget {
  const MoveOutScreen({
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
  State<MoveOutScreen> createState() => _MoveOutScreenState();
}

class _MoveOutScreenState extends State<MoveOutScreen> {
  late final gateway = widget.gateway ?? FirebaseTenancyGateway(moveOut: true);
  late final photos = widget.photos ?? FirebaseInspectionGateway();
  StreamSubscription<TenancyRecord>? subscription;
  Timer? timer;
  TenancyRecord? data;
  late String page = widget.initialPage;
  String? room;
  String? itemId;
  String condition = 'same';
  String? personId;
  String? error;
  String? privateCode;
  int? codeExpiry;
  String? codeIdentity;
  int generation = 0;
  bool busy = false;
  bool privateDialog = false;
  bool dirty = false;
  bool stale = false;
  bool countsConfirmed = false;
  bool reviewed = false;
  bool physicalHandover = false;
  bool ownBank = false;
  String destination = 'original_payment';
  String slot = '09:00–12:00';
  DateTime? bookingDate;
  Map<String, dynamic>? retry;
  final cost = TextEditingController();
  final note = TextEditingController();
  final code = TextEditingController();
  final bankName = TextEditingController();
  final account = TextEditingController();
  final accountAgain = TextEditingController();
  final ifsc = TextEditingController();
  final readings = {
    for (final kind in ['electricity', 'water', 'gas'])
      kind: TextEditingController(),
  };
  final meterPhotos = <String, String>{};
  final counts = {
    'mainDoor': 0,
    'bedrooms': 0,
    'letterBox': 0,
    'parkingCard': 0,
  };
  final thumbnails = <String, Future<DocumentFile>>{};
  static const keyNames = {
    'mainDoor': 'Main door',
    'bedrooms': 'Bedroom doors',
    'letterBox': 'Letter box',
    'parkingCard': 'Parking card',
  };
  static const conditions = {
    'same': 'Same as move-in',
    'repair': 'Needs repair',
    'damaged': 'Damaged',
    'missing': 'Missing',
  };

  @override
  void initState() {
    super.initState();
    subscription = gateway
        .watch(widget.agreementId, widget.role)
        .listen(
          (record) {
            if (!mounted) return;
            final first = data == null;
            if (!first &&
                dirty &&
                !busy &&
                data!.number('version') != record.number('version')) {
              stale = true;
            }
            final identity = jsonEncode([
              record.map('keyChallenge'),
              record.map('returnedKeys'),
            ]);
            if (identity != codeIdentity || record.flag('keysConfirmed')) {
              privateCode = null;
              codeExpiry = null;
              countsConfirmed = false;
              code.clear();
            }
            codeIdentity = identity;
            setState(() {
              data = record;
              error = null;
              if (first) _reload();
            });
          },
          onError: (Object failure) {
            if (!mounted) return;
            generation++;
            if (privateDialog) Navigator.of(context).pop();
            setState(() {
              data = null;
              busy = false;
              privateCode = null;
              codeExpiry = null;
              codeIdentity = null;
              retry = null;
              countsConfirmed = false;
              reviewed = false;
              ownBank = false;
              dirty = false;
              stale = false;
              meterPhotos.clear();
              thumbnails.clear();
              for (final controller in [
                cost,
                note,
                code,
                bankName,
                account,
                accountAgain,
                ifsc,
                ...readings.values,
              ]) {
                controller.clear();
              }
              error = _message(failure);
            });
          },
        );
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          codeExpiry != null &&
          DateTime.now().millisecondsSinceEpoch >= codeExpiry!) {
        setState(() {
          privateCode = null;
          codeExpiry = null;
        });
      }
    });
  }

  @override
  void dispose() {
    generation++;
    subscription?.cancel();
    timer?.cancel();
    for (final controller in [
      cost,
      note,
      code,
      bankName,
      account,
      accountAgain,
      ifsc,
      ...readings.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _message(Object failure) => failure is FirebaseFunctionsException
      ? failure.message ?? 'Could not save this move-out.'
      : failure.toString().replaceFirst('Bad state: ', '');
  String _money(Object? amount) => NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: (amount as num? ?? 0) % 100 == 0 ? 0 : 2,
  ).format((amount ?? 0) / 100);
  int? _paise(String value) {
    if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value.trim())) return null;
    final parts = value.trim().split('.');
    return int.parse(parts[0]) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  Map<String, dynamic>? get selectedItem =>
      data?.items.where((item) => item['id'] == itemId).firstOrNull;
  Map<String, dynamic> get report => data?.map('report') ?? {};
  List<Map<String, dynamic>> get lines => (report['lines'] as List? ?? [])
      .whereType<Map>()
      .map((line) => Map<String, dynamic>.from(line))
      .toList();
  bool get editable =>
      data?.flag('canEdit') == true &&
      report.isEmpty &&
      data?.flag('handoverComplete') != true;
  Map<String, dynamic> _reportPayload(Map<String, dynamic> payload) => {
    'reportVersion': report['version'],
    ...payload,
  };

  void _reload() {
    dirty = false;
    stale = false;
    reviewed = false;
    physicalHandover = false;
    if (data == null) return;
    bookingDate = DateTime.tryParse(
      (data!.map('booking')?['date'] ?? data!.map('notice')?['date'])
              as String? ??
          '',
    );
    slot = data!.map('booking')?['slot'] as String? ?? '09:00–12:00';
    personId = data!.rows('people').firstOrNull?['personId'] as String?;
    if (page == 'compare') {
      final saved = selectedItem?['comparison'] as Map?;
      condition = saved?['condition'] as String? ?? 'same';
      cost.text = saved == null
          ? ''
          : ((saved['costPaise'] as num) / 100).toStringAsFixed(2);
      note.text = saved?['note'] as String? ?? '';
    }
    for (final kind in readings.keys) {
      final meter = data!.map('meters')?[kind];
      readings[kind]!.text = meter is Map
          ? meter['reading'] as String? ?? ''
          : '';
      if (meter is Map && meter['checkId'] is String) {
        meterPhotos[kind] = meter['checkId'] as String;
      }
    }
    final saved = data!.map('returnedKeys') ?? data!.map('givenKeys') ?? {};
    for (final kind in counts.keys) {
      counts[kind] = (saved[kind] as num?)?.toInt() ?? 0;
    }
    if (page == 'destination') {
      destination =
          data!.map('destination')?['method'] as String? ?? 'original_payment';
      account.clear();
      accountAgain.clear();
      bankName.clear();
      ifsc.clear();
      ownBank = false;
    }
  }

  void _open(String next, {String? roomName, String? item}) {
    if (busy || retry != null) return;
    setState(() {
      page = next;
      room = roomName ?? room;
      itemId = item ?? itemId;
      error = null;
      _reload();
    });
  }

  Future<void> _record(
    String action,
    Map<String, dynamic> payload, {
    String? next,
  }) async {
    if (data == null || busy) return;
    if (stale || retry != null) {
      setState(
        () => error =
            'Reload changed details or retry the saved action before editing.',
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
      dirty = false;
      if (result['codeAccepted'] == false) {
        setState(
          () => error =
              result['message'] as String? ?? 'Incorrect key-return code.',
        );
      } else {
        await gateway.refresh(widget.agreementId, widget.role);
        if (mounted && active == generation && next != null) {
          setState(() {
            page = next;
            _reload();
          });
        }
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
    if (busy || data == null) return;
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

  Future<String?> _capture(
    String purpose,
    String roomName,
    String title,
    String item,
  ) async {
    if (busy || data == null || retry != null || stale) return null;
    final active = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final grant = await photos.begin({
        'propertyId': data!.text('propertyId'),
        'agreementId': widget.agreementId,
        'role': widget.role,
        'room': roomName,
        'title': title,
        'note': '',
        'source': 'camera',
        'operationId': newRepairReportId(),
        'purpose': purpose,
        'itemId': item,
      });
      if (!mounted || active != generation || data == null) return null;
      final original =
          await (widget.camera?.call() ?? pickPrivateDocument(camera: true));
      if (!mounted ||
          active != generation ||
          data == null ||
          original == null) {
        return null;
      }
      final stamped = await stampInspectionPhoto(original, grant);
      if (!mounted || active != generation || data == null) return null;
      privateDialog = true;
      bool approved;
      try {
        approved = await reviewPrivateDocument(context, stamped, upload: true);
      } finally {
        privateDialog = false;
      }
      if (!mounted || active != generation || data == null || !approved) {
        return null;
      }
      await photos.save(grant, stamped);
      if (!mounted || active != generation || data == null) return null;
      await gateway.refresh(widget.agreementId, widget.role);
      return grant['checkId'] as String;
    } catch (failure) {
      if (mounted && active == generation) {
        setState(() => error = _message(failure));
      }
      return null;
    } finally {
      if (mounted && active == generation) setState(() => busy = false);
    }
  }

  Future<void> _issue() async {
    if (!countsConfirmed || busy || data == null) return;
    final active = generation;
    final identity = codeIdentity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await gateway.issueCode({
        'agreementId': widget.agreementId,
        'role': widget.role,
        'countsConfirmed': true,
      });
      if (mounted &&
          active == generation &&
          data != null &&
          identity == codeIdentity &&
          result['challengeId'] == data!.map('keyChallenge')?['id']) {
        setState(() {
          privateCode = result['code'] as String;
          codeExpiry = (result['expiresAtMs'] as num).toInt();
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
    'booking' => 'Book a move-out check',
    'rooms' => 'Photos by room',
    'items' => room ?? 'Move-out photos',
    'compare' => '$room · ${selectedItem?['title'] ?? 'Compare item'}',
    'meters' => 'Final meter readings',
    'keys' => 'Keys back',
    'report' => 'Deductions',
    'destination' => 'Your deposit',
    'complete' => 'Move-out record',
    _ => 'Move-out',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.role == 'admin' && page == 'report' ? 1150 : 440,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    IconButton.outlined(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        side: const BorderSide(color: AppColors.border),
                        shape: const CircleBorder(),
                      ),
                      onPressed: busy
                          ? null
                          : () {
                              if (page == 'checklist' ||
                                  widget.role == 'admin' &&
                                      page == widget.initialPage) {
                                Navigator.of(context).maybePop();
                              } else {
                                _open(
                                  page == 'compare'
                                      ? 'items'
                                      : page == 'items'
                                      ? 'rooms'
                                      : 'checklist',
                                );
                              }
                            },
                      icon: const Icon(Icons.chevron_left),
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
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      tooltip: 'Call TrustKeyper for help',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        side: const BorderSide(color: AppColors.border),
                        shape: const CircleBorder(),
                      ),
                      onPressed: widget.offline
                          ? null
                          : () => TkPage.showHelpSheet(context),
                      icon: const Icon(Icons.call_outlined, size: 20),
                    ),
                  ],
                ),
              ),
              if (widget.offline)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'OFFLINE TEST · No real money, keys or bank transfer',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
              if (data != null && error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (stale)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Text(
                        'The move-out changed. Reload before saving.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => setState(_reload),
                        child: const Text('Reload latest details'),
                      ),
                    ],
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
                            TextButton(
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
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                        children: [
                          if (busy) const LinearProgressIndicator(),
                          if (retry != null && !busy)
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => _submit(null),
                                  child: const Text('Retry saved action'),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    retry = null;
                                    error = null;
                                    stale = dirty;
                                  }),
                                  child: const Text('Discard local retry'),
                                ),
                              ],
                            ),
                          ...switch (page) {
                            'booking' => _booking(),
                            'rooms' => _rooms(),
                            'items' => _items(),
                            'compare' => _compare(),
                            'meters' => _meters(),
                            'keys' => _keys(),
                            'report' => _report(),
                            'destination' => _destination(),
                            'complete' => _complete(),
                            _ => _checklist(),
                          },
                        ],
                      ),
              ),
              if (data != null && _footer() != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: _footer(),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _hint(String text) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F9FD),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.muted),
    ),
  );
  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget _button(String text, VoidCallback? action) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: busy || stale || retry != null ? null : action,
      child: Text(text),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
    int maxLines = 1,
    bool enabled = true,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      enabled: enabled && !busy,
      obscureText: secret,
      maxLines: maxLines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => setState(() => dirty = true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _step(
    IconData icon,
    String text,
    String detail,
    bool done,
    String target, {
    bool active = false,
  }) => InkWell(
    onTap: busy ? null : () => _open(target),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDF0F5))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: done
                ? const Color(0xFF27AE60)
                : active
                ? AppColors.primary
                : AppColors.border,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: done
                  ? const Color(0xFF27AE60)
                  : active
                  ? AppColors.primary
                  : Colors.white,
              child: Icon(
                done ? Icons.check : icon,
                color: done || active ? Colors.white : const Color(0xFF9CAEC5),
                size: 21,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: done || active ? AppColors.heading : AppColors.muted,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 14, color: AppColors.success),
                  SizedBox(width: 5),
                  Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            )
          else if (active)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Do it',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 7),
                  Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ],
              ),
            )
          else
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    ),
  );

  List<Widget> _checklist() {
    final rentPaid =
        data!.rows('rent').isNotEmpty &&
        data!.rows('rent').every((person) => person['status'] == 'paid');
    final steps = [
      true,
      rentPaid,
      data!.flag('inspectionComplete'),
      data!.map('meters') != null,
      data!.flag('keysConfirmed'),
      report.isNotEmpty,
    ];
    final active = steps.indexWhere((done) => !done);
    return [
      Text(
        '${data!.text('address')} · ${data!.map('notice')?['date'] ?? ''}',
        style: const TextStyle(fontSize: 16, color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(child: Text('Move-out steps')),
          Flexible(
            child: Text(
              '${steps.where((done) => done).length} of 6 done',
              style: const TextStyle(
                color: Color(0xFF087F5B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final done in steps)
            Expanded(
              child: Container(
                height: 7,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF27AE60)
                      : const Color(0xFFDCE6F8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _step(
        Icons.event_available,
        'Notice given',
        '${data!.map('notice')?['date']}',
        true,
        'booking',
      ),
      _step(
        Icons.account_balance_wallet_outlined,
        'Last rent',
        rentPaid ? 'Captured rent reconciled' : 'Rent needs reconciliation',
        rentPaid,
        'report',
        active: active == 1,
      ),
      _step(
        Icons.camera_alt_outlined,
        'Move-out photos',
        'Compare every room with move-in',
        steps[2],
        'rooms',
        active: active == 2,
      ),
      _step(
        Icons.speed_outlined,
        'Final meter readings',
        'Electricity, water${data!.map('beforeMeters')?['noGas'] == true ? '' : ', gas'}',
        steps[3],
        'meters',
        active: active == 3,
      ),
      _step(
        Icons.key_outlined,
        'Keys back',
        '${(data!.map('givenKeys') ?? {}).values.fold<int>(0, (total, amount) => total + (amount as num).toInt())} keys were given',
        steps[4],
        'keys',
        active: active == 4,
      ),
      _step(
        Icons.currency_rupee,
        'Deductions and deposit',
        'Owner and tenants check it',
        steps[5],
        'report',
        active: active == 5,
      ),
      const SizedBox(height: 20),
      const Text(
        'Do these at the flat, with the tenant. Owner and tenant can see everything.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: busy ? null : () => _open('booking'),
        child: const Text('Book the check'),
      ),
      if (data!.flag('handoverComplete'))
        TextButton(
          onPressed: () => _open('complete'),
          child: const Text('View handover record'),
        ),
    ];
  }

  List<Widget> _booking() => [
    Text(data!.text('address'), style: const TextStyle(color: AppColors.muted)),
    _hint(
      'The check is on or after ${data!.map('notice')?['date']}. A requested slot is not confirmation from the broker.',
    ),
    OutlinedButton.icon(
      onPressed: busy
          ? null
          : () async {
              final noticeDate = DateTime.parse(
                data!.map('notice')!['date'] as String,
              );
              final today = DateTime.parse(data!.text('today'));
              final first = today.isAfter(noticeDate) ? today : noticeDate;
              final selected = await showDatePicker(
                context: context,
                initialDate:
                    bookingDate != null && !bookingDate!.isBefore(first)
                    ? bookingDate!
                    : first,
                firstDate: first,
                lastDate: first.add(const Duration(days: 180)),
              );
              if (selected != null && mounted && data != null) {
                setState(() {
                  bookingDate = selected;
                  dirty = true;
                });
              }
            },
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        bookingDate == null
            ? 'Pick a date'
            : DateFormat('d MMM yyyy').format(bookingDate!),
      ),
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      initialValue: slot,
      decoration: const InputDecoration(labelText: 'Time window'),
      items: [
        for (final value in ['09:00–12:00', '12:00–15:00', '15:00–18:00'])
          DropdownMenuItem(value: value, child: Text(value)),
      ],
      onChanged: busy
          ? null
          : (value) => setState(() {
              slot = value!;
              dirty = true;
            }),
    ),
    if (data!.map('booking') != null)
      _hint(
        'Saved request: ${data!.map('booking')!['date']} · ${data!.map('booking')!['slot']}',
      ),
  ];

  List<Widget> _rooms() => [
    const Text(
      'Match the move-in photos item by item.',
      style: TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 18),
    for (final entry in data!.rows('rooms'))
      _card([
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.room_outlined, color: AppColors.primary),
          title: Text(entry['room'] as String),
          subtitle: Text(
            '${(entry['items'] as List).where((item) => (item as Map)['comparison'] != null).length} of ${(entry['items'] as List).length} compared',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open('items', roomName: entry['room'] as String),
        ),
      ]),
  ];

  List<Widget> _items() => [
    for (final item
        in data!
            .rows('rooms')
            .where((entry) => entry['room'] == room)
            .expand((entry) => (entry['items'] as List).whereType<Map>()))
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          item['comparison'] == null
              ? Icons.image_outlined
              : Icons.check_circle,
          color: AppColors.primary,
        ),
        title: Text(item['title'] as String),
        subtitle: Text(
          item['beforeId'] == null
              ? 'Not present in the frozen move-in record'
              : item['comparison'] == null
              ? 'Needs comparison'
              : conditions[(item['comparison'] as Map)['condition']] ??
                    'Compared',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: item['beforeId'] == null
            ? null
            : () => _open('compare', item: item['id'] as String),
      ),
  ];

  Widget _photo(
    String? id,
    String label, {
    VoidCallback? capture,
    bool compact = false,
  }) {
    Widget content;
    if (id == null) {
      content = const Center(
        child: Icon(
          Icons.add_a_photo_outlined,
          color: Color(0xFF98B3DF),
          size: 28,
        ),
      );
    } else {
      content = FutureBuilder<DocumentFile>(
        future: thumbnails.putIfAbsent(
          id,
          () => photos.photo(data!.text('propertyId'), id),
        ),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!.bytes,
                fit: BoxFit.cover,
                gaplessPlayback: false,
              )
            : Center(
                child: Icon(
                  snapshot.hasError
                      ? Icons.broken_image_outlined
                      : Icons.image_outlined,
                  color: const Color(0xFF98B3DF),
                ),
              ),
      );
    }
    return Expanded(
      child: InkWell(
        onTap: busy
            ? null
            : id == null
            ? capture
            : () => _review(id),
        child: Container(
          height: compact ? 44 : 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: label == 'Move-in'
                ? const Color(0xFFDCE6F8)
                : const Color(0xFFF8DEDA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (!compact)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(5),
                    color: const Color(0xB3425265),
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _compare() {
    final item = selectedItem;
    if (item == null) return [const Text('Choose a room item first.')];
    return [
      Row(
        children: [
          _photo(item['beforeId'] as String?, 'Move-in'),
          const SizedBox(width: 10),
          _photo(
            item['afterId'] as String?,
            'Move-out',
            capture: editable
                ? () async {
                    await _capture(
                      'move_out',
                      room!,
                      item['title'] as String,
                      itemId!,
                    );
                  }
                : null,
          ),
        ],
      ),
      if (editable)
        TextButton.icon(
          onPressed: () async {
            await _capture('move_out', room!, item['title'] as String, itemId!);
          },
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(
            item['afterId'] == null
                ? 'Take move-out photo'
                : 'Retake move-out photo',
          ),
        ),
      const SizedBox(height: 12),
      const Text('How is it now?', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      for (final pair in [
        conditions.entries.take(2),
        conditions.entries.skip(2),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              for (final entry in pair)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: condition == entry.key
                            ? const Color(0xFFEAF0FF)
                            : Colors.white,
                        side: BorderSide(
                          color: condition == entry.key
                              ? AppColors.primary
                              : AppColors.border,
                          width: condition == entry.key ? 2 : 1,
                        ),
                      ),
                      onPressed: !editable || busy
                          ? null
                          : () => setState(() {
                              condition = entry.key;
                              dirty = true;
                              if (condition == 'same') cost.text = '0';
                            }),
                      child: Text(entry.value),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (condition != 'same')
        _field(
          cost,
          'Proposed repair cost (₹)',
          numeric: true,
          enabled: editable,
        ),
      _field(note, 'Note', maxLines: 2, enabled: editable),
      if (condition != 'same')
        _hint(
          'This is a proposed deduction. The owner and tenants review it; it is not a completed payment.',
        ),
    ];
  }

  List<Widget> _meters() => [
    const Text(
      'Photograph and save the actual final readings.',
      style: TextStyle(color: AppColors.muted),
    ),
    const SizedBox(height: 16),
    for (final kind in [
      'electricity',
      'water',
      if (data!.map('beforeMeters')?['noGas'] != true) 'gas',
    ])
      _card([
        Text(
          '${kind[0].toUpperCase()}${kind.substring(1)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          'Move-in: ${(data!.map('beforeMeters')?[kind] as Map?)?['reading'] ?? 'Not recorded'}',
          style: const TextStyle(color: AppColors.muted),
        ),
        _field(
          readings[kind]!,
          'Final $kind reading',
          numeric: true,
          enabled: editable,
        ),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  if (!editable) {
                    if (meterPhotos[kind] != null) {
                      await _review(meterPhotos[kind]!);
                    }
                    return;
                  }
                  final id = await _capture(
                    'move_out_meter',
                    'Meters',
                    '$kind final meter',
                    kind,
                  );
                  if (id != null && mounted && data != null) {
                    setState(() {
                      meterPhotos[kind] = id;
                      dirty = true;
                    });
                  }
                },
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(
            meterPhotos[kind] == null
                ? 'Take meter photo'
                : editable
                ? 'Retake meter photo'
                : 'View meter photo',
          ),
        ),
      ]),
    if (data!.map('beforeMeters')?['noGas'] == true)
      _hint('No gas meter was recorded at move-in.'),
  ];

  List<Widget> _keys() {
    final saved = data!.map('returnedKeys');
    final challenge = data!.map('keyChallenge');
    final canIssue =
        widget.role == 'tenant' &&
        challenge?['personId'] == data!.text('myPersonId');
    return [
      Text(
        data!.flag('keysConfirmed')
            ? 'Returned keys confirmed by the tenant.'
            : 'Count the keys and cards with the departing tenant.',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      for (final kind in counts.keys)
        _card([
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      keyNames[kind]!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${data!.map('givenKeys')?[kind] ?? 0} given',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (editable &&
                  challenge == null &&
                  !data!.flag('keysConfirmed')) ...[
                IconButton(
                  onPressed: counts[kind]! > 0
                      ? () => setState(() {
                          counts[kind] = counts[kind]! - 1;
                          dirty = true;
                        })
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${counts[kind]}'),
                IconButton(
                  onPressed:
                      counts[kind]! <
                          ((data!.map('givenKeys')?[kind] as num?)?.toInt() ??
                              0)
                      ? () => setState(() {
                          counts[kind] = counts[kind]! + 1;
                          dirty = true;
                        })
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ] else
                Text('${saved?[kind] ?? '—'} returned'),
            ],
          ),
        ]),
      if (editable && challenge == null && !data!.flag('keysConfirmed')) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: personId,
          decoration: const InputDecoration(
            labelText: 'Tenant confirming the keys',
          ),
          items: [
            for (final person in data!.rows('people'))
              DropdownMenuItem(
                value: person['personId'] as String,
                child: Text(person['name'] as String),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() {
                  personId = value;
                  dirty = true;
                }),
        ),
      ],
      if (challenge != null && widget.role == 'broker') ...[
        _hint(
          'Ask ${challenge['name']} to confirm the counts on their app and give you their current code.',
        ),
        _field(code, 'Tenant’s six-digit code', numeric: true),
        TextButton(
          onPressed: busy
              ? null
              : () => _record('keys', {'counts': counts, 'personId': personId}),
          child: const Text('Prepare a new confirmation'),
        ),
      ],
      if (canIssue) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: countsConfirmed,
          onChanged: busy
              ? null
              : (value) => setState(() => countsConfirmed = value == true),
          title: const Text('I returned exactly these keys and access cards.'),
        ),
        if (privateCode != null) ...[
          SelectableText(
            privateCode!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 38,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          _hint(
            'Tell this code only to your broker after checking the keys. Expires ${DateFormat('h:mm:ss a').format(DateTime.fromMillisecondsSinceEpoch(codeExpiry!))}.',
          ),
        ],
      ],
      _hint(
        'This private app code confirms physical key return. It is not a legal signature or an Aadhaar OTP.',
      ),
    ];
  }

  Future<void> _question(
    Map<String, dynamic> line, {
    bool decision = false,
  }) async {
    if (busy || data == null) return;
    var reason = '';
    var amount = ((line['amountPaise'] as num) / 100).toStringAsFixed(2);
    String? evidence;
    final reportVersion = report['version'];
    final active = generation;
    try {
      privateDialog = true;
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              decision
                  ? 'Review ${line['title']}'
                  : 'Question ${line['title']}',
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (decision)
                      TextFormField(
                        initialValue: amount,
                        onChanged: (value) => amount = value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Keep or reduce to (₹); 0 removes it',
                        ),
                      ),
                    TextFormField(
                      initialValue: reason,
                      onChanged: (value) => reason = value,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'Evidence-based reason (at least 10 characters)',
                      ),
                    ),
                    if (!decision)
                      const Text(
                        'Optional photo can be added from the report before submitting.',
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (reason.trim().length < 10 ||
                      decision &&
                          (_paise(amount) == null ||
                              _paise(amount)! > (line['amountPaise'] as num))) {
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
      privateDialog = false;
      if (submitted != true ||
          !mounted ||
          active != generation ||
          data == null) {
        return;
      }
      if (!decision) {
        privateDialog = true;
        final addPhoto = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add a supporting photo?'),
            content: const Text(
              'Take a private photo now, or submit your explanation without one.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Without photo'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Take photo'),
              ),
            ],
          ),
        );
        privateDialog = false;
        if (!mounted || active != generation || data == null) return;
        if (addPhoto == true) {
          evidence = await _capture(
            'move_out_dispute',
            line['room'] as String? ?? 'Move-out',
            line['title'] as String,
            line['id'] as String,
          );
          if (evidence == null) return;
        }
      }
      if (!mounted || active != generation || data == null) return;
      if (reportVersion != report['version']) {
        setState(
          () => error =
              'The report changed. Review the latest evidence before responding.',
        );
        return;
      }
      await _record(
        decision ? 'decide' : 'respond',
        _reportPayload({
          'itemId': line['id'],
          if (decision) 'amountPaise': _paise(amount) else 'status': 'disputed',
          if (decision)
            'reason': reason.trim()
          else ...{
            'reason': reason.trim(),
            'checkId': evidence,
          },
        }),
      );
    } finally {
      privateDialog = false;
    }
  }

  Future<void> _charge() async {
    if (!editable || busy) return;
    var title = '';
    var amount = '';
    var reason = '';
    var kind = 'key';
    var meter = 'electricity';
    final active = generation;
    try {
      privateDialog = true;
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Propose a key or utility deduction'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      items: const [
                        DropdownMenuItem(
                          value: 'key',
                          child: Text('Missing keys'),
                        ),
                        DropdownMenuItem(
                          value: 'utility',
                          child: Text('Utility charge'),
                        ),
                      ],
                      onChanged: (value) => update(() => kind = value!),
                    ),
                    if (kind == 'utility')
                      DropdownButtonFormField<String>(
                        initialValue: meter,
                        items: [
                          for (final value in [
                            'electricity',
                            'water',
                            if (data!.map('beforeMeters')?['noGas'] != true)
                              'gas',
                          ])
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) => update(() => meter = value!),
                      ),
                    TextFormField(
                      initialValue: title,
                      onChanged: (value) => title = value,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextFormField(
                      initialValue: amount,
                      onChanged: (value) => amount = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Proposed amount (₹)',
                      ),
                    ),
                    TextFormField(
                      initialValue: reason,
                      onChanged: (value) => reason = value,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Reason and bill reference',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (title.trim().length < 3 ||
                      reason.trim().length < 10 ||
                      (_paise(amount) ?? 0) <= 0) {
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Propose'),
              ),
            ],
          ),
        ),
      );
      privateDialog = false;
      if (result != true || !mounted || active != generation || data == null) {
        return;
      }
      final savedMeter = data!.map('meters')?[meter] as Map?;
      await _record('charge', {
        'kind': kind,
        'title': title.trim(),
        'amountPaise': _paise(amount),
        'note': reason.trim(),
        if (kind == 'utility') ...{
          'meter': meter,
          'checkId': savedMeter?['checkId'],
        },
      });
    } finally {
      privateDialog = false;
    }
  }

  Future<void> _proposal({Map<String, dynamic>? proposal}) async {
    if (busy || data == null || retry != null) return;
    final active = generation;
    final reportVersion = report['version'];
    final available = data!.items
        .where(
          (item) =>
              item['beforeId'] != null &&
              item['afterId'] != null &&
              !lines.any((line) => line['id'] == item['id']),
        )
        .toList();
    if (proposal == null && available.isEmpty) {
      setState(
        () => error = 'No inspected, undeducted room item is available.',
      );
      return;
    }
    var selected = available.firstOrNull?['id'] as String?;
    var amount = proposal == null
        ? ''
        : ((proposal['amountPaise'] as num) / 100).toStringAsFixed(2);
    var reason = '';
    var decision = 'accept';
    privateDialog = true;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              proposal == null
                  ? 'Add a missed item'
                  : 'Review ${proposal['title']}',
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (proposal == null)
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Inspected room item',
                        ),
                        items: [
                          for (final item in available)
                            DropdownMenuItem(
                              value: item['id'] as String,
                              child: Text(
                                item['title'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => update(() => selected = value),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: decision,
                        items: const [
                          DropdownMenuItem(
                            value: 'accept',
                            child: Text('Accept reviewed cost'),
                          ),
                          DropdownMenuItem(
                            value: 'reject',
                            child: Text('Reject proposal'),
                          ),
                        ],
                        onChanged: (value) => update(() => decision = value!),
                      ),
                    if (decision == 'accept')
                      TextFormField(
                        initialValue: amount,
                        onChanged: (value) => amount = value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Proposed amount (₹)',
                        ),
                      ),
                    TextFormField(
                      initialValue: reason,
                      onChanged: (value) => reason = value,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText:
                            'Evidence-based reason (at least 10 characters)',
                      ),
                    ),
                    const Text(
                      'An accepted addition creates a new report. All owners and tenants must review it again.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (reason.trim().length < 10 ||
                      decision == 'accept' && (_paise(amount) ?? 0) <= 0) {
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
      privateDialog = false;
      if (accepted != true ||
          !mounted ||
          active != generation ||
          data == null) {
        return;
      }
      if (reportVersion != report['version']) {
        setState(
          () => error =
              'The report changed. Reopen its current evidence before proposing a change.',
        );
        return;
      }
      await _record(
        proposal == null ? 'propose' : 'review_proposal',
        _reportPayload({
          'reason': reason.trim(),
          'amountPaise': _paise(amount),
          if (proposal == null)
            'itemId': selected
          else ...{
            'proposalId': proposal['id'],
            'decision': decision,
          },
        }),
      );
    } finally {
      privateDialog = false;
    }
  }

  List<Widget> _report() {
    final proposed = lines.isNotEmpty
        ? lines
        : [
            for (final room in data!.rows('rooms'))
              for (final item in (room['items'] as List).whereType<Map>())
                if (((item['comparison'] as Map?)?['costPaise'] as num? ?? 0) >
                    0)
                  {
                    'id': item['id'],
                    'title': item['title'],
                    'room': room['room'],
                    'amountPaise': (item['comparison'] as Map)['costPaise'],
                    'beforeId': item['beforeId'],
                    'afterId': item['afterId'],
                    'note': (item['comparison'] as Map)['note'],
                  },
            ...data!.rows('charges'),
          ];
    final deposit = data!
        .rows('shares')
        .fold<int>(
          0,
          (sum, share) => sum + (share['depositPaise'] as num).toInt(),
        );
    final total = proposed.fold<int>(
      0,
      (sum, line) => sum + (line['amountPaise'] as num).toInt(),
    );
    if (widget.role == 'broker' && report.isEmpty) {
      return [
        Text(
          'From the ${_money(deposit)} deposit',
          style: const TextStyle(fontSize: 16, color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        _card([
          if (proposed.isEmpty) const Text('No deductions recorded.'),
          for (final line in proposed) ...[
            if (line != proposed.first)
              const Divider(height: 25, color: Color(0xFFEDF1F6)),
            Row(
              children: [
                if (line['beforeId'] != null || line['afterId'] != null) ...[
                  SizedBox(
                    width: 92,
                    child: Row(
                      children: [
                        _photo(
                          line['beforeId'] as String?,
                          'Move-in',
                          compact: true,
                        ),
                        const SizedBox(width: 6),
                        _photo(
                          line['afterId'] as String?,
                          'Move-out',
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line['title'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        line['room'] as String? ?? 'Move-out',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(line['amountPaise']),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ]),
        _card([
          _total('Deposit held', deposit),
          const Divider(height: 24),
          _total('Taken out', total),
          const Divider(height: 24),
          _total('Back to tenants', deposit - total, green: true),
        ]),
        const Text(
          'Owner decides on key-return day. Refund target: within 7 days after verified handover. Publishing only shares this report in the app; it does not send money.',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        if (editable)
          TextButton.icon(
            onPressed: _charge,
            icon: const Icon(Icons.add),
            label: const Text('Add key or utility charge'),
          ),
        if (!data!.flag('inspectionComplete'))
          _hint(
            'Complete every room comparison, meter reading and key confirmation before publishing.',
          ),
      ];
    }
    final responses = data!.map('responses') ?? {};
    final decisions = data!.map('decisions') ?? {};
    return [
      Text(
        'From ${_money(deposit)} ${widget.role == 'tenant' ? 'your deposit' : 'deposit'}',
        style: const TextStyle(color: AppColors.muted),
      ),
      if (report.isEmpty)
        _hint(
          'Draft deductions: review all private evidence before publishing.',
        ),
      if (proposed.isEmpty) _hint('No deductions recorded.'),
      for (final line in proposed)
        _card([
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line['title'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      line['room'] as String? ?? 'Move-out',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _money(
                  widget.role == 'tenant'
                      ? ((line['shares'] as Map?)?[data!.text('myPersonId')] ??
                            0)
                      : line['amountPaise'],
                ),
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if ((line['note'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(line['note'] as String),
            ),
          if (line['beforeId'] != null || line['afterId'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (line['beforeId'] != null)
                    _photo(line['beforeId'] as String, 'Move-in'),
                  if (line['beforeId'] != null && line['afterId'] != null)
                    const SizedBox(width: 10),
                  if (line['afterId'] != null)
                    _photo(line['afterId'] as String, 'Move-out'),
                ],
              ),
            ),
          if (decisions[line['id']] is Map)
            _hint(
              'Team decision: ${_money((decisions[line['id']] as Map)['amountPaise'])} · ${(decisions[line['id']] as Map)['reason']}',
            ),
          if (widget.role == 'tenant' && report.isNotEmpty) ...[
            if ((responses[data!.text('myPersonId')] as Map?)?[line['id']]
                is Map)
              _hint(
                'Your response: ${((responses[data!.text('myPersonId')] as Map)[line['id']] as Map)['status']}',
              )
            else if (decisions[line['id']] == null)
              Wrap(
                spacing: 10,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _record(
                            'respond',
                            _reportPayload({
                              'itemId': line['id'],
                              'status': 'agreed',
                            }),
                          ),
                    child: const Text('I agree'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _question(line),
                    child: const Text('Question item'),
                  ),
                ],
              ),
          ],
          if (widget.role == 'admin' || widget.role == 'owner')
            for (final person in data!.rows('people'))
              if ((responses[person['personId']] as Map?)?[line['id']]
                  is Map) ...[
                _hint(
                  '${person['name']}: ${((responses[person['personId']] as Map)[line['id']] as Map)['status']} · ${((responses[person['personId']] as Map)[line['id']] as Map)['reason'] ?? ''}',
                ),
                if (((responses[person['personId']] as Map)[line['id']]
                        as Map)['checkId']
                    is String)
                  TextButton(
                    onPressed: () => _review(
                      ((responses[person['personId']] as Map)[line['id']]
                              as Map)['checkId']
                          as String,
                    ),
                    child: const Text('View tenant evidence'),
                  ),
              ],
          if (widget.role == 'admin' &&
              report.isNotEmpty &&
              decisions[line['id']] == null &&
              data!
                  .rows('people')
                  .any(
                    (person) =>
                        ((responses[person['personId']] as Map?)?[line['id']]
                            as Map?)?['status'] ==
                        'disputed',
                  ))
            _button(
              'Keep, reduce or remove',
              () => _question(line, decision: true),
            ),
        ]),
      for (final proposal in data!.rows('proposals'))
        _card([
          Text(
            '${proposal['title']} · ${_money(proposal['amountPaise'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(proposal['reason'] as String),
          _hint(
            'Owner proposal: ${proposal['status']}. Not an accepted deduction yet.',
          ),
          if (widget.role == 'admin' && proposal['status'] == 'pending')
            _button('Review missed item', () => _proposal(proposal: proposal)),
        ]),
      if (widget.role == 'owner' && report.isNotEmpty)
        TextButton.icon(
          onPressed: busy ? null : () => _proposal(),
          icon: const Icon(Icons.add),
          label: const Text('Add a missed item'),
        ),
      if (editable)
        TextButton.icon(
          onPressed: _charge,
          icon: const Icon(Icons.add),
          label: const Text('Add key or utility charge'),
        ),
      if (report.isEmpty)
        _card([
          _total('Deposit held', deposit),
          _total('Proposed deductions', total),
          const Divider(),
          _total('Proposed back to tenants', deposit - total, green: true),
        ]),
      for (final share in data!.rows('shares'))
        _card([
          Text(
            share['name'] as String,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _total('Captured deposit', share['depositPaise']),
          _total('Agreed deductions', share['deductionsPaise']),
          _total('Held for review', share['heldPaise']),
          _total('Refundable now', share['refundableNowPaise'], green: true),
          if (share['depositVerified'] != true)
            _hint(
              'Live captured deposit must be reconciled before a financial report.',
            ),
          if (share['refundStatus'] != 'not_requested')
            _hint(
              'Refund: ${share['refundStatus']}. No transfer is complete without provider confirmation.',
            ),
          if (widget.role == 'admin' &&
              share['refundStatus'] == 'not_requested' &&
              (share['refundableNowPaise'] as num) > 0)
            TextButton(
              onPressed: busy
                  ? null
                  : () => _record(
                      'refund_request',
                      _reportPayload({'personId': share['personId']}),
                    ),
              child: const Text('Request undisputed refund'),
            ),
        ]),
      if (report.isNotEmpty)
        _hint(
          'Owner review: ${data!.flag('ownersApproved') ? 'all owners approved' : 'waiting'}. Owner decides on key-return day. Refund target: within 7 days; disputed items are reviewed within 2 days. Targets are not completed transfers.',
        ),
      if (data!.flag('pendingOwnerReview'))
        _hint(
          'A missed-item proposal is waiting for team review. Refund preparation pauses until it is resolved; the proposal is not an accepted deduction.',
        ),
      if (widget.role == 'owner' && report.isNotEmpty)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: reviewed,
          onChanged: busy
              ? null
              : (value) => setState(() {
                  reviewed = value == true;
                  dirty = true;
                }),
          title: const Text('I reviewed every deduction and its evidence.'),
        ),
      if (widget.role == 'tenant' && report.isNotEmpty)
        _button('Choose refund destination', () => _open('destination')),
      if (widget.role == 'broker' &&
          report.isNotEmpty &&
          !data!.flag('handoverComplete')) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: physicalHandover,
          onChanged: busy
              ? null
              : (value) => setState(() {
                  physicalHandover = value == true;
                  dirty = true;
                }),
          title: const Text('The home was physically handed back.'),
        ),
        _button(
          'Complete physical handover',
          physicalHandover
              ? () => _record(
                  'complete',
                  _reportPayload({'confirmedPhysicalHandover': true}),
                  next: 'complete',
                )
              : null,
        ),
      ],
      if (widget.role == 'admin')
        _hint(
          'Refund requests enter provider reconciliation. This button does not charge, transfer money or mark a refund completed.',
        ),
    ];
  }

  Widget _total(String label, Object? value, {bool green = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: green ? FontWeight.w700 : FontWeight.w400,
              color: AppColors.muted,
            ),
          ),
        ),
        Text(
          _money(value),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: green ? const Color(0xFF087F5B) : AppColors.heading,
          ),
        ),
      ],
    ),
  );

  List<Widget> _destination() => [
    const Text(
      'Where should we send your deposit?',
      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
    ),
    _hint(
      'Choose a destination in your name. Saving this does not initiate a bank transfer.',
    ),
    RadioGroup<String>(
      groupValue: destination,
      onChanged: (value) {
        if (!busy && value != null) {
          setState(() {
            destination = value;
            dirty = true;
          });
        }
      },
      child: Column(
        children: [
          for (final option in {
            'original_payment': 'Original payment method',
            'bank_review': 'Another bank account',
          }.entries)
            _card([
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: option.key,
                enabled: !busy,
                title: Text(option.value),
                subtitle: Text(
                  option.key == 'original_payment'
                      ? 'Provider verification required'
                      : 'Name must be yours; team verification required',
                ),
              ),
            ]),
        ],
      ),
    ),
    if (destination == 'bank_review') ...[
      _field(bankName, 'Account holder name'),
      _field(account, 'Bank account number', numeric: true, secret: true),
      _field(
        accountAgain,
        'Confirm bank account number',
        numeric: true,
        secret: true,
      ),
      _field(ifsc, 'IFSC'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: ownBank,
        onChanged: busy
            ? null
            : (value) => setState(() {
                ownBank = value == true;
                dirty = true;
              }),
        title: const Text('This account is in my name.'),
      ),
    ],
    if (data!.map('destination') != null)
      _hint(
        'Saved: ${data!.map('destination')!['method']} ${data!.map('destination')!['maskedAccount'] ?? ''} · ${data!.map('destination')!['verificationStatus']}',
      ),
    _hint(
      'Full account details are private. Other tenants, owners and brokers cannot read them.',
    ),
  ];

  List<Widget> _complete() => [
    const SizedBox(height: 30),
    Icon(
      data!.flag('handoverComplete') ? Icons.check_circle : Icons.schedule,
      size: 76,
      color: const Color(0xFF27AE60),
    ),
    const SizedBox(height: 22),
    Text(
      data!.flag('handoverComplete')
          ? 'Physical handover recorded'
          : 'Move-out in progress',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 12),
    Text(
      data!.text('address'),
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.muted),
    ),
    _hint(
      'Photos, final readings and key confirmation remain in the record. Deposit settlement is separate and remains open until provider confirmation.',
    ),
    _button('View deductions and deposit', () => _open('report')),
  ];

  Widget? _footer() {
    if (page == 'booking' && !data!.flag('keysConfirmed')) {
      return _button(
        'Request this check',
        bookingDate == null
            ? null
            : () => _record('book', {
                'date': DateFormat('yyyy-MM-dd').format(bookingDate!),
                'slot': slot,
              }, next: 'checklist'),
      );
    }
    if (page == 'compare' && editable && selectedItem?['afterId'] != null) {
      return _button(
        'Save comparison',
        () => _record('compare', {
          'itemId': itemId,
          'checkId': selectedItem!['afterId'],
          'condition': condition,
          'costPaise': condition == 'same' ? 0 : _paise(cost.text),
          'note': note.text.trim(),
        }, next: 'items'),
      );
    }
    if (page == 'meters' && editable) {
      return _button(
        'Save final readings',
        () => _record('meters', {
          for (final kind in [
            'electricity',
            'water',
            if (data!.map('beforeMeters')?['noGas'] != true) 'gas',
          ])
            kind: {
              'reading': readings[kind]!.text.trim(),
              'checkId': meterPhotos[kind],
            },
        }, next: 'checklist'),
      );
    }
    if (page == 'keys' && !data!.flag('keysConfirmed')) {
      final challenge = data!.map('keyChallenge');
      if (widget.role == 'broker' && editable) {
        return _button(
          challenge == null
              ? 'Prepare tenant confirmation'
              : 'Confirm returned keys',
          () => _record(
            challenge == null ? 'keys' : 'confirm_keys',
            challenge == null
                ? {'counts': counts, 'personId': personId}
                : {'challengeId': challenge['id'], 'code': code.text.trim()},
          ),
        );
      }
      if (widget.role == 'tenant' &&
          challenge?['personId'] == data!.text('myPersonId')) {
        return _button(
          'Get my confirmation code',
          countsConfirmed ? _issue : null,
        );
      }
    }
    if (page == 'report' && editable) {
      return _button(
        'Send to owner and tenants',
        () => _record('publish', {}, next: 'report'),
      );
    }
    if (page == 'report' && widget.role == 'owner' && report.isNotEmpty) {
      return _button(
        'Approve these deductions',
        reviewed
            ? () => _record(
                'owner_approve',
                _reportPayload({'reviewedAllItems': true}),
              )
            : null,
      );
    }
    if (page == 'destination' && widget.role == 'tenant') {
      return _button('Save refund destination', () {
        if (destination == 'bank_review' &&
            account.text.trim() != accountAgain.text.trim()) {
          setState(() => error = 'The two bank account numbers do not match.');
          return;
        }
        _record(
          'destination',
          _reportPayload({
            'method': destination,
            if (destination == 'bank_review') ...{
              'name': bankName.text.trim(),
              'account': account.text.trim(),
              'ifsc': ifsc.text.trim().toUpperCase(),
              'inMyName': ownBank,
            },
          }),
          next: 'report',
        );
      });
    }
    return null;
  }
}
