import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/trustkeyper_ui.dart';
import '../../../core/widgets/app_brand.dart';
import '../data/manager_callbacks.dart';

const callbackWindows = {
  'soon': 'In 10 minutes',
  'today_evening': 'Today 6 – 8 pm',
  'tomorrow_morning': 'Tomorrow morning',
  'tomorrow_evening': 'Tomorrow evening',
};
const callbackTopics = {
  'property': 'Add my property',
  'plan': 'Plan and fee',
  'tenant': 'Finding a tenant',
};
String callbackTime(Object? timestamp) => timestamp is num
    ? '${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(timestamp.toInt(), isUtc: true).add(const Duration(minutes: 330)))} IST'
    : 'Not confirmed yet';

class ManagerCallbackScreen extends StatefulWidget {
  const ManagerCallbackScreen({
    this.gateway,
    this.ownerUid,
    this.managers = const [],
    this.offline = false,
    this.contactLauncher,
    super.key,
  });
  final ManagerCallbackGateway? gateway;
  final Future<bool> Function(Uri)? contactLauncher;
  final String? ownerUid;
  final List<Map<String, String>> managers;
  final bool offline;
  @override
  State<ManagerCallbackScreen> createState() => _ManagerCallbackScreenState();
}

class _ManagerCallbackScreenState extends State<ManagerCallbackScreen> {
  late final gateway = widget.gateway ?? FirebaseManagerCallbackGateway();
  StreamSubscription<Map<String, dynamic>>? subscription;
  Map<String, dynamic>? data;
  Map<String, dynamic>? retry;
  String? error;
  String window = 'tomorrow_morning';
  String topic = 'property';
  String? selectedManager;
  bool saving = false;
  bool editing = false;
  bool stale = false;
  final workPhone = TextEditingController();
  final workEmail = TextEditingController();
  final outcome = TextEditingController();
  final scroll = ScrollController();
  bool get admin => widget.ownerUid != null;
  Map<String, dynamic>? get callback => data?['callback'] is Map
      ? Map<String, dynamic>.from(data!['callback'] as Map)
      : null;
  Map<String, dynamic>? get manager => data?['manager'] is Map
      ? Map<String, dynamic>.from(data!['manager'] as Map)
      : null;
  String get status => callback?['status'] as String? ?? 'none';
  @override
  void initState() {
    super.initState();
    subscription = gateway
        .watch(widget.ownerUid)
        .listen(
          (value) {
            if (!mounted) return;
            setState(() {
              if (editing &&
                  data != null &&
                  data!['version'] != value['version']) {
                stale = true;
              } else {
                data = value;
                if (!editing) _restoreChoices();
              }
              error = null;
            });
          },
          onError: (Object failure) {
            if (!mounted) return;
            setState(() {
              data = null;
              retry = null;
              error = _message(failure);
              editing = false;
            });
            workPhone.clear();
            workEmail.clear();
            outcome.clear();
          },
        );
  }

  @override
  void dispose() {
    subscription?.cancel();
    workPhone.dispose();
    workEmail.dispose();
    outcome.dispose();
    scroll.dispose();
    super.dispose();
  }

  String _message(Object failure) => failure is FirebaseFunctionsException
      ? failure.message ?? 'Could not load the callback. Retry.'
      : failure is StateError
      ? failure.message.toString()
      : 'Could not save. Check your connection and retry.';

  void _restoreChoices() {
    final current = callback;
    if (callbackTopics.containsKey(current?['topic'])) {
      topic = current!['topic'] as String;
    }
    final available = List<String>.from(
      data?['availableWindows'] as List? ?? [],
    );
    if (available.contains(current?['window'])) {
      window = current!['window'] as String;
    } else if (!available.contains(window) && available.isNotEmpty) {
      window = available.first;
    }
  }

  void _beginEdit() {
    setState(() {
      _restoreChoices();
      editing = true;
    });
  }

  Future<void> _save(String action, Map<String, dynamic> payload) async {
    if (saving || stale || data == null) return;
    final operation =
        retry ??
        {
          'action': action,
          'version': data!['version'],
          'payload': payload,
          'operationId': List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
          if (admin) 'ownerUid': widget.ownerUid,
        };
    setState(() {
      saving = true;
      error = null;
      retry = operation;
    });
    try {
      final result = await gateway.record(operation);
      if (!mounted || data == null) return;
      setState(() {
        data = result;
        retry = null;
        editing = false;
        stale = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = _message(failure);
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reload() async {
    setState(() {
      editing = false;
      stale = false;
      retry = null;
      error = null;
    });
    await gateway.refresh();
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F9FD),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
  Future<void> _contact(String kind) async {
    final contact = manager;
    if (contact == null || widget.offline) return;
    final phone = contact['phone'] as String;
    final uri = kind == 'email'
        ? Uri(scheme: 'mailto', path: contact['email'] as String)
        : kind == 'whatsapp'
        ? Uri.https('wa.me', phone.substring(1))
        : Uri(scheme: 'tel', path: phone);
    try {
      final opened = widget.contactLauncher != null
          ? await widget.contactLauncher!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    setState(
      () => error = 'Could not open $kind. Use the contact shown below.',
    );
  }

  Widget _managerCard() {
    final name = manager?['name'] as String? ?? 'TrustKeyper team';
    return _card(
      Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              name
                  .trim()
                  .split(' ')
                  .where((word) => word.isNotEmpty)
                  .take(2)
                  .map((word) => word[0])
                  .join(),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  manager == null
                      ? 'A manager will be assigned by the team'
                      : 'Your TrustKeyper manager · 9 am – 8 pm',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = data != null;
    final showForm =
        !admin &&
        (editing ||
            ['none', 'cancelled', 'completed', 'missed'].contains(status));
    final available = (data?['availableWindows'] as List? ?? const [])
        .cast<String>()
        .where(
          (choice) =>
              choice == callback?['window'] ||
              (status == 'missed'
                  ? choice != 'today_evening'
                  : choice != 'tomorrow_evening'),
        )
        .toList();
    final page = TkPage(
      scrollController: scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      titleStyle: TextStyle(
        fontSize: showForm ? 22 : 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
      ),
      title: admin
          ? 'Owner callback'
          : status == 'missed'
          ? 'We could not reach you'
          : showForm
          ? 'Our manager will do it for you'
          : status == 'confirmed'
          ? '${manager?['name'] ?? 'Your manager'} will call you'
          : 'Call requested',
      onBack: showForm && !admin ? null : () => Navigator.maybePop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.offline)
            const Text(
              'OFFLINE TEST · No call, message or Firebase request is sent',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          if (error != null) ...[
            Text(
              error!,
              key: const ValueKey('callback-error'),
              style: const TextStyle(color: Colors.red),
            ),
            TextButton(
              onPressed: saving ? null : _reload,
              child: const Text('Reload callback'),
            ),
          ],
          if (stale) ...[
            const Text('This request changed. Reload before saving.'),
            TextButton(
              onPressed: saving ? null : _reload,
              child: const Text('Reload changed request'),
            ),
          ],
          if (!ready && error == null)
            const Center(child: CircularProgressIndicator()),
          if (ready) ...[
            _managerCard(),
            const SizedBox(height: 18),
            if (admin)
              _adminForm()
            else ...[
              if (status == 'missed') ...[
                Text(
                  '${manager?['name'] ?? 'The team'} called at ${callbackTime(callback?['attemptedAtMs'])}.',
                ),
                if (callback?['outcome'] != null)
                  Text(callback!['outcome'] as String),
                const SizedBox(height: 16),
              ],
              if (showForm) ...[
                const Text(
                  'When should we call?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in available)
                      ChoiceChip(
                        showCheckmark: false,
                        selectedColor: AppColors.primarySoft,
                        labelStyle: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: window == choice
                              ? AppColors.primaryDark
                              : AppColors.body,
                        ),
                        shape: const StadiumBorder(),
                        label: Text(callbackWindows[choice] ?? choice),
                        selected: window == choice,
                        onSelected: saving || retry != null
                            ? null
                            : (_) => setState(() {
                                window = choice;
                                editing = true;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'About',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in callbackTopics.entries)
                      ChoiceChip(
                        showCheckmark: false,
                        selectedColor: AppColors.primarySoft,
                        labelStyle: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: topic == choice.key
                              ? AppColors.primaryDark
                              : AppColors.body,
                        ),
                        shape: const StadiumBorder(),
                        label: Text(choice.value),
                        selected: topic == choice.key,
                        onSelected: saving || retry != null
                            ? null
                            : (_) => setState(() {
                                topic = choice.key;
                                editing = true;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _card(
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          data!['phone'] as String? ?? 'Verify your phone',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Text(
                        'Verified',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The team will confirm availability in the app. A requested time is not a guaranteed booking.',
                  style: TextStyle(fontSize: 13.5, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      saving ||
                          stale ||
                          retry != null ||
                          !available.contains(window)
                      ? null
                      : () => _save('request', {
                          'topic': topic,
                          'window': window,
                        }),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(status == 'missed' ? 'Call me again' : 'Call me'),
                ),
              ] else ...[
                Text(
                  status == 'confirmed'
                      ? '${callbackTime(callback?['scheduledAtMs'])} on ${data!['phone']}'
                      : status == 'completed'
                      ? 'Call completed'
                      : '${callbackWindows[callback?['window']]} on ${data!['phone']}',
                ),
                const SizedBox(height: 18),
                const Text(
                  'Keep this ready',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                for (final item in [
                  'Address of the home',
                  'Rent you want',
                  'Photos (if you have)',
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primary,
                    ),
                    title: Text(item),
                  ),
                const Text(
                  'You do not need to fill everything now. Your manager helps you add it and you check it.',
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: saving || retry != null ? null : _beginEdit,
                  child: const Text('Change time'),
                ),
                if (['requested', 'confirmed'].contains(status))
                  TextButton(
                    onPressed: saving || retry != null
                        ? null
                        : () => _save('cancel', {}),
                    child: const Text('Cancel callback'),
                  ),
              ],
              if (manager != null && !showForm) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final contact in ['call', 'whatsapp', 'email'])
                      TextButton(
                        onPressed: widget.offline
                            ? null
                            : () => _contact(contact),
                        child: Text(
                          contact == 'call'
                              ? 'Call manager'
                              : contact == 'email'
                              ? 'Email manager'
                              : 'WhatsApp manager',
                        ),
                      ),
                  ],
                ),
                Text(
                  '${manager!['phone']} · ${manager!['email']}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
              TextButton(
                onPressed: widget.offline
                    ? null
                    : () => TkPage.showHelpSheet(context),
                child: const Text('Or call us now: +91 80885 16875'),
              ),
            ],
            if (retry != null && !saving) ...[
              FilledButton(
                onPressed: stale
                    ? null
                    : () => _save(
                        retry!['action'] as String,
                        Map<String, dynamic>.from(retry!['payload'] as Map),
                      ),
                child: const Text('Retry same request'),
              ),
              TextButton(
                onPressed: _reload,
                child: const Text('Discard retry and reload'),
              ),
            ],
            if (saving) const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
    if (admin || !showForm) return page;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppBrand(height: 32),
                        const SizedBox(height: 26),
                        const Text(
                          'Welcome home',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text('Your manager can help you get started.'),
                        const SizedBox(height: 20),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: 'Close callback',
                      child: GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: .28),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: min(200.0, constraints.maxHeight * .26),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: ColoredBox(
                        color: Colors.white,
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 5,
                              margin: const EdgeInsets.only(top: 12, bottom: 4),
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Expanded(
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                child: page,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Status: $status · ${data!['phone']}'),
      if (callback?['window'] != null)
        Text(
          'Requested: ${callbackWindows[callback!['window']]} · ${callbackTopics[callback!['topic']]}',
        ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: selectedManager,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Active manager'),
        items: widget.managers
            .map(
              (entry) => DropdownMenuItem(
                value: entry['uid'],
                child: Text(entry['name'] ?? 'Team member'),
              ),
            )
            .toList(),
        onChanged: saving || retry != null
            ? null
            : (value) => setState(() {
                selectedManager = value;
                editing = true;
              }),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: workPhone,
        enabled: !saving && retry == null,
        decoration: const InputDecoration(
          labelText: 'Published work phone (+91…)',
        ),
        keyboardType: TextInputType.phone,
        onChanged: (_) => editing = true,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: workEmail,
        enabled: !saving && retry == null,
        decoration: const InputDecoration(labelText: 'Company email'),
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => editing = true,
      ),
      OutlinedButton(
        onPressed: saving || stale || retry != null || selectedManager == null
            ? null
            : () => _save('assign', {
                'managerUid': selectedManager,
                'phone': workPhone.text.trim(),
                'email': workEmail.text.trim(),
              }),
        child: const Text('Assign manager'),
      ),
      if (status == 'requested' && manager != null)
        FilledButton(
          onPressed: saving || stale || retry != null ? null : _confirm,
          child: const Text('Confirm call time'),
        ),
      if (status == 'confirmed') ...[
        Text('Confirmed: ${callbackTime(callback?['scheduledAtMs'])}'),
        TextField(
          controller: outcome,
          enabled: !saving && retry == null,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'What actually happened on the call',
          ),
          onChanged: (_) => editing = true,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: saving || stale || retry != null
              ? null
              : () => _save('missed', {'note': outcome.text}),
          child: const Text('Record no answer'),
        ),
        FilledButton(
          onPressed: saving || stale || retry != null
              ? null
              : () => _save('complete', {'note': outcome.text}),
          child: const Text('Record completed call'),
        ),
      ],
      if (callback?['outcome'] != null) Text(callback!['outcome'] as String),
    ],
  );
  Future<void> _confirm() async {
    final version = data?['version'];
    final earliest = callback?['requestedFromMs'] as num?;
    if (earliest == null) return;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      ((earliest.toInt() + 59999) ~/ 60000) * 60000,
      isUtc: true,
    ).add(const Duration(minutes: 330));
    final choice = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: timestamp.hour, minute: timestamp.minute),
    );
    if (!mounted || choice == null || stale || data == null) return;
    if (data!['version'] != version) {
      setState(
        () => error =
            'This request changed while choosing the time. Reload before confirming.',
      );
      return;
    }
    final scheduled = DateTime.utc(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      choice.hour,
      choice.minute,
    ).subtract(const Duration(minutes: 330));
    await _save('confirm', {'scheduledAtMs': scheduled.millisecondsSinceEpoch});
  }
}

class AdminCallbackQueue extends StatefulWidget {
  const AdminCallbackQueue({
    required this.owners,
    required this.managers,
    this.gateway,
    super.key,
  });
  final List<Map<String, String>> owners;
  final List<Map<String, String>> managers;
  final ManagerCallbackGateway? gateway;
  @override
  State<AdminCallbackQueue> createState() => _AdminCallbackQueueState();
}

class _AdminCallbackQueueState extends State<AdminCallbackQueue> {
  late final gateway = widget.gateway ?? FirebaseManagerCallbackGateway();
  late Future<List<Map<String, dynamic>>> records = gateway.list();
  String? selectedOwner;
  Future<void> _open(String ownerUid) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerCallbackScreen(
          gateway: gateway,
          ownerUid: ownerUid,
          managers: widget.managers,
        ),
      ),
    );
    if (mounted) setState(() => records = gateway.list());
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Owner callbacks',
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      ),
      const Text(
        'Assign an active team member, confirm actual availability and record call outcomes. No call is placed automatically.',
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        initialValue: selectedOwner,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Owner'),
        items: widget.owners
            .map(
              (entry) => DropdownMenuItem(
                value: entry['uid'],
                child: Text(entry['name'] ?? 'Owner'),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => selectedOwner = value),
      ),
      OutlinedButton(
        onPressed: selectedOwner == null ? null : () => _open(selectedOwner!),
        child: const Text('Open owner support'),
      ),
      TextButton(
        onPressed: () => setState(() => records = gateway.list()),
        child: const Text('Refresh callbacks'),
      ),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: records,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load callbacks. Refresh to retry.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Text('No callback requests yet.');
          }
          return Column(
            children: [
              for (final record in snapshot.data!)
                ListTile(
                  title: Text(record['ownerName'] as String? ?? 'Owner'),
                  subtitle: Text(
                    '${record['status']} · ${callbackWindows[record['window']] ?? 'Manager assignment'} · ${record['phone']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(record['ownerUid'] as String),
                ),
            ],
          );
        },
      ),
    ],
  );
}
