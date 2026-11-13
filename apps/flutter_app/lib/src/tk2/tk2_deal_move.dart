import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_cloud.dart';
import 'tk2_deal.dart';
import 'tk2_deal_screens.dart';
import 'tk2_send.dart';
import 'tk2_status.dart';
import 'tk2_store.dart';

// Screens for stages 7–9 of a deal: key handover, the 7-day repair window
// and the society's move-in steps.

const _meters = ['Electricity', 'Gas', 'Water'];

// ---------------------------------------------------------------- handover

/// Broker, at the house with the tenant: photos and a video, meter readings
/// and the key count. Opened again later it proposes a change, which the
/// owner and the tenant must approve.
class DealHandover extends StatefulWidget {
  const DealHandover({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealHandover> createState() => _DealHandoverState();
}

class _DealHandoverState extends State<DealHandover> {
  late final Map<String, dynamic> h = widget.deal.handover;
  late final photos = [...(h['photos'] as List? ?? const []).cast<String>()];
  late String video = h['video'] as String? ?? '';
  late String keysPhoto = h['keysPhoto'] as String? ?? '';
  late int keys = h['keys'] as int? ?? 2;
  late final readings = {for (final m in _meters) m: TextEditingController(text: (h['meters'] as Map? ?? const {})[m] as String? ?? '')};
  late final meterPhotos = Map<String, String>.from(h['meterPhotos'] as Map? ?? const {});
  final note = TextEditingController();
  final bad = <String>{};

  Tk2Deal get d => widget.deal;
  bool get editing => d.handoverAt > 0;

  @override
  void dispose() {
    for (final c in [...readings.values, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _readings => {
    for (final m in _meters)
      if (readings[m]!.text.trim().isNotEmpty) m: readings[m]!.text.trim(),
  };

  Future<void> _save() async {
    bad
      ..clear()
      ..addAll({
        if (!editing && photos.isEmpty) 'photos',
        if (readings['Electricity']!.text.trim().isEmpty) 'Electricity',
        if (keysPhoto.isEmpty) 'keys',
        if (editing && note.text.trim().length < 3) 'note',
      });
    if (bad.isNotEmpty) return setState(() {});
    if (editing) {
      // A later change never edits the record directly: it waits for both approvals.
      d.b['edit'] = {'v': (d.edit?['v'] as int? ?? 0) + 1, 'text': note.text.trim(), 'keys': keys, 'meters': _readings};
    } else {
      d.b['handover'] = {
        'photos': photos,
        'video': video,
        'meters': _readings,
        'meterPhotos': meterPhotos,
        'keys': keys,
        'keysPhoto': keysPhoto,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
    }
    await widget.store.saveDeal(d, DealRole.broker);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pick(void Function(String path) set, {bool video = false}) async {
    final p = await dealPickPhoto(context, d, video: video);
    if (p != null && mounted) setState(() => set(p));
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: editing ? 'Change the handover record' : 'Key handover',
    subtitle: editing ? 'The owner and the tenant must approve the change' : 'Do this at the house, with ${d.nameOf(DealRole.tenant).split(' ').first}',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: editing ? 'Ask owner and tenant to approve' : 'Hand over', icon: Icons.chevron_right, onPressed: _save)],
    children: [
      if (!editing) ...[
        dealHeading('Photos and video'),
        dealText('Every room, and each thing in the house. The owner, the tenant and you can see these later. Move-out is compared with them.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, p) in photos.indexed)
              Stack(
                children: [
                  DealPhoto(p),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setState(() => photos.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            Semantics(
              button: true,
              label: 'Add photo',
              child: InkWell(
                onTap: () => _pick((p) {
                  photos.add(p);
                  bad.remove('photos');
                }),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: bad.contains('photos') ? AppColors.error : AppColors.primaryBorder),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryDark),
                ),
              ),
            ),
          ],
        ),
        if (bad.contains('photos'))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Add at least one photo', style: TextStyle(fontSize: 14, color: AppColors.error)),
          ),
        const SizedBox(height: 12),
        DealPhotoRow(
          title: 'Video of the house',
          subtitle: 'Walk through every room · up to 5 minutes',
          path: video,
          onPick: () => _pick((p) => video = p, video: true),
        ),
      ],
      dealHeading('Meter readings'),
      for (final m in _meters)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OnbTextField(
                  label: m == 'Electricity' ? '$m reading *' : '$m reading',
                  controller: readings[m]!,
                  keyboard: TextInputType.number,
                  error: bad.contains(m) ? 'Type the reading' : null,
                  onChanged: (_) => setState(() => bad.remove(m)),
                ),
              ),
              if (!editing) ...[
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Photo of the $m meter',
                  child: InkWell(
                    onTap: () => _pick((p) => meterPhotos[m] = p),
                    borderRadius: BorderRadius.circular(14),
                    child: (meterPhotos[m] ?? '').isEmpty
                        ? Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryDark),
                          )
                        : DealPhoto(meterPhotos[m]!, size: 54),
                  ),
                ),
              ],
            ],
          ),
        ),
      dealHeading('Keys'),
      Row(
        children: [
          const Expanded(
            child: Text('How many keys', style: TextStyle(fontSize: 16, color: AppColors.heading)),
          ),
          IconButton(
            tooltip: 'One key less',
            onPressed: keys > 1 ? () => setState(() => keys--) : null,
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.primaryDark),
          ),
          Text(
            '$keys',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.heading),
          ),
          IconButton(
            tooltip: 'One key more',
            onPressed: keys < 30 ? () => setState(() => keys++) : null,
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryDark),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (!editing)
        DealPhotoRow(
          title: 'Photo of the keys',
          subtitle: 'All the keys together',
          path: keysPhoto,
          need: bad.contains('keys'),
          onPick: () => _pick((p) {
            keysPhoto = p;
            bad.remove('keys');
          }),
        ),
      if (editing) ...[
        const SizedBox(height: 8),
        OnbTextField(
          label: 'What changed, and why *',
          controller: note,
          maxLines: 2,
          capitalization: TextCapitalization.sentences,
          error: bad.contains('note') ? 'Say what changed' : null,
          onChanged: (_) => setState(() => bad.remove('note')),
        ),
      ],
    ],
  );
}

/// Tenant, at handover: tick every thing in the house, then confirm the keys.
class DealCheck extends StatefulWidget {
  const DealCheck({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealCheck> createState() => _DealCheckState();
}

class _DealCheckState extends State<DealCheck> {
  late final ticks = Map<String, dynamic>.from(widget.deal.ticks);
  final notes = <String, TextEditingController>{};
  late bool keysOk = widget.deal.t['keysOk'] == true;
  bool showError = false;

  Tk2Deal get d => widget.deal;

  @override
  void dispose() {
    for (final c in notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _done() async {
    for (final e in notes.entries) {
      if (ticks[e.key] != 'ok') ticks[e.key] = e.value.text.trim().isEmpty ? 'Problem' : e.value.text.trim();
    }
    if (!d.items.every((i) => ticks.containsKey(i.name)) || !keysOk) return setState(() => showError = true);
    d.t.addAll({'items': ticks, 'keysOk': true, 'keysAt': DateTime.now().millisecondsSinceEpoch});
    await widget.store.saveDeal(d, DealRole.tenant);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _choice(String item, bool ok) {
    final on = ok ? ticks[item] == 'ok' : (ticks.containsKey(item) && ticks[item] != 'ok');
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(ok ? 'OK' : 'Problem'),
        selected: on,
        showCheckmark: false,
        selectedColor: ok ? AppColors.successSoft : AppColors.errorSoft,
        side: BorderSide(color: on ? (ok ? AppColors.success : AppColors.error) : AppColors.border),
        onSelected: (_) => setState(() {
          ticks[item] = ok ? 'ok' : 'Problem';
          if (!ok) notes.putIfAbsent(item, TextEditingController.new);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = d.handover['keys'] as int? ?? 0;
    return OnbPage(
      title: 'Check the house',
      subtitle: 'Look at each thing with the broker',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [PrimaryButton(label: 'All checked', icon: Icons.check, onPressed: _done)],
      children: [
        OnbReadFullButton(
          label: 'See photos and meter readings',
          onPressed: () => dealPush(context, DealRecord(store: widget.store, deal: d, role: DealRole.tenant)),
        ),
        dealHeading('Things in the house'),
        for (final i in d.items) ...[
          Row(
            children: [
              Expanded(
                child: Text(i.count > 1 ? '${i.count} × ${i.name}' : i.name, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
              ),
              _choice(i.name, true),
              _choice(i.name, false),
            ],
          ),
          if (ticks.containsKey(i.name) && ticks[i.name] != 'ok')
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: OnbTextField(
                label: 'What is wrong with it?',
                controller: notes.putIfAbsent(i.name, TextEditingController.new),
                capitalization: TextCapitalization.sentences,
              ),
            ),
          const Divider(height: 14, color: AppColors.border),
        ],
        dealHeading('Keys'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: keysOk,
          onChanged: (v) => setState(() => keysOk = v ?? false),
          title: Text('I got $keys ${keys == 1 ? 'key' : 'keys'}', style: const TextStyle(fontSize: 16, color: AppColors.heading)),
        ),
        if (showError) const Text('Tick every thing, and confirm the keys', style: TextStyle(fontSize: 14, color: AppColors.error)),
        const SizedBox(height: 8),
        const OnbBanner(
          'For 7 days after this you can report anything broken. Old problems are the owner\'s to fix.',
          kind: 'info',
          icon: Icons.build_outlined,
        ),
      ],
    );
  }
}

/// The handover record everyone can open later: photos, video, readings,
/// keys, the tenant's check and repairs done since. Lives in the app, not as a document.
class DealRecord extends StatelessWidget {
  const DealRecord({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final h = deal.handover;
      final photos = (h['photos'] as List? ?? const []).cast<String>();
      final video = h['video'] as String? ?? '';
      final meters = Map<String, dynamic>.from(h['meters'] as Map? ?? const {});
      final ticks = deal.ticks;
      final fixed = deal.repairs.where((r) => r.fixed).toList();
      final edit = deal.edit;
      final pending = edit != null && !(deal.editOk(DealRole.tenant) && deal.editOk(DealRole.owner));
      return OnbPage(
        title: 'Handover record',
        subtitle: '${deal.title} · ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(deal.handoverAt))}',
        onBack: () => Navigator.of(context).maybePop(),
        footer: [
          if (role == DealRole.broker && !pending)
            OnbSecondaryButton(
              label: 'Change something',
              onPressed: () => dealPush(context, DealHandover(store: store, deal: deal)),
            ),
        ],
        children: [
          if (pending) ...[
            OnbBanner(
              'Change waiting for approval: ${edit['text']} '
              '(${[
                for (final r in [DealRole.tenant, DealRole.owner]) '${Tk2Deal.who(r)} ${deal.editOk(r) ? 'said yes' : 'has not replied'}',
              ].join(', ')})',
              kind: 'wait',
              icon: Icons.hourglass_top,
            ),
            const SizedBox(height: 12),
          ],
          if (photos.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [for (final p in photos) DealPhoto(p)]),
            const SizedBox(height: 12),
          ],
          if (video.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OnbRow(
                icon: Icons.play_circle_outline,
                title: 'Video of the house',
                subtitle: Tk2Cloud.isPrivateFile(video) ? 'Tap to save' : 'Video unavailable on this device',
                chevron: Tk2Cloud.isPrivateFile(video),
                onTap: Tk2Cloud.isPrivateFile(video) ? () => saveTk2PrivateFile(context, video, maxBytes: 200 * 1024 * 1024) : null,
              ),
            ),
          OnbCard(
            child: Column(
              children: [
                for (final e in meters.entries) OnbKeyValue('${e.key} meter', '${e.value}'),
                OnbKeyValue('Keys given', '${h['keys'] ?? 0}', last: true),
              ],
            ),
          ),
          dealHeading('Things in the house'),
          OnbCard(
            child: Column(
              children: [
                for (final (n, i) in deal.items.indexed)
                  OnbKeyValue(
                    i.count > 1 ? '${i.count} × ${i.name}' : i.name,
                    !ticks.containsKey(i.name) ? 'Not checked yet' : (ticks[i.name] == 'ok' ? 'OK' : 'Problem: ${ticks[i.name]}'),
                    last: n == deal.items.length - 1,
                  ),
              ],
            ),
          ),
          if (fixed.isNotEmpty) ...[
            dealHeading('Repaired after move-in'),
            for (final r in fixed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OnbRow(
                  icon: Icons.build_outlined,
                  tone: 'ok',
                  title: r.text,
                  subtitle: 'Fixed on ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(r.quote['done'] as int))}',
                  trailing: DealPhoto(r.donePhoto, size: 44),
                  chevron: false,
                ),
              ),
          ],
        ],
      );
    },
  );
}

/// Tenant or owner: say yes to a later change of the handover record.
class DealEditApprove extends StatelessWidget {
  const DealEditApprove({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  Widget build(BuildContext context) {
    final e = deal.edit ?? const {};
    final meters = Map<String, dynamic>.from(e['meters'] as Map? ?? const {});
    return OnbPage(
      title: 'Approve a change',
      subtitle: 'The broker changed the handover record',
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        PrimaryButton(
          label: 'Yes, this is right',
          icon: Icons.check,
          onPressed: () async {
            deal.part(role)['editOk'] = e['v'];
            await store.saveDeal(deal, role);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      children: [
        OnbBanner('${e['text']}', kind: 'info', icon: Icons.edit_note),
        const SizedBox(height: 12),
        OnbCard(
          child: Column(
            children: [for (final m in meters.entries) OnbKeyValue('${m.key} meter', '${m.value}'), OnbKeyValue('Keys given', '${e['keys']}', last: true)],
          ),
        ),
        const SizedBox(height: 12),
        dealText('The record changes only when both the owner and the tenant say yes. If this is not right, call the broker.'),
      ],
    );
  }
}

// ----------------------------------------------------------------- repairs

/// Tenant: report something broken (7 days after handover).
class DealRaise extends StatefulWidget {
  const DealRaise({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealRaise> createState() => _DealRaiseState();
}

class _DealRaiseState extends State<DealRaise> {
  final text = TextEditingController();
  String photo = '';
  final bad = <String>{};

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    bad
      ..clear()
      ..addAll({if (text.text.trim().length < 4) 'text', if (photo.isEmpty) 'photo'});
    if (bad.isNotEmpty) return setState(() {});
    final d = widget.deal;
    final at = DateTime.now().millisecondsSinceEpoch;
    d.t['repairs'] = [
      ...(d.t['repairs'] as List? ?? const []),
      {'id': 'r${at.toRadixString(36)}', 'text': text.text.trim(), 'photo': photo, 'at': at},
    ];
    await widget.store.saveDeal(d, DealRole.tenant);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Report something broken',
    subtitle: '${widget.deal.repairDaysLeft(DateTime.now())} days left in your 7 days',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Send to the broker', icon: Icons.chevron_right, onPressed: _send)],
    children: [
      OnbTextField(
        label: 'What is broken?',
        controller: text,
        maxLines: 3,
        capitalization: TextCapitalization.sentences,
        error: bad.contains('text') ? 'Say what is broken' : null,
        onChanged: (_) => setState(() => bad.remove('text')),
      ),
      const SizedBox(height: 12),
      DealPhotoRow(
        title: 'Photo of it',
        path: photo,
        need: bad.contains('photo'),
        onPick: () async {
          final p = await dealPickPhoto(context, widget.deal);
          if (p != null && mounted) {
            setState(() {
              photo = p;
              bad.remove('photo');
            });
          }
        },
      ),
      const SizedBox(height: 6),
      const OnbBanner('The broker checks it and tells you how long the fix takes. The owner pays for old problems.', kind: 'info', icon: Icons.info_outline),
    ],
  );
}

/// All repair requests of a deal.
class DealRepairs extends StatelessWidget {
  const DealRepairs({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final open = deal.repairWindowOpen(now);
      return OnbPage(
        title: '7-day repairs',
        subtitle: open ? '${deal.repairDaysLeft(now)} days left' : 'The 7 days are over',
        onBack: () => Navigator.of(context).maybePop(),
        footer: [
          if (role == DealRole.tenant && open)
            PrimaryButton(
              label: 'Report something broken',
              icon: Icons.add,
              onPressed: () => dealPush(context, DealRaise(store: store, deal: deal)),
            ),
        ],
        children: [
          if (deal.repairs.isEmpty)
            OnbCentered(
              icon: Icons.build_outlined,
              title: 'Nothing reported',
              message: open
                  ? (role == DealRole.tenant
                        ? 'If something does not work, report it here within 7 days of getting the keys.'
                        : 'The tenant can report anything broken for 7 days after handover.')
                  : 'After 7 days, repairs go through the normal repair requests.',
            ),
          for (final r in deal.repairs.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OnbRow(
                icon: r.open ? (r.waitingOn == role ? Icons.priority_high : Icons.build_outlined) : Icons.check,
                tone: !r.open ? (r.paid ? 'ok' : 'mute') : (r.waitingOn == role ? 'need' : 'wait'),
                title: r.text,
                subtitle: r.status(role),
                onTap: () => dealPush(context, DealRepair(store: store, deal: deal, role: role, id: r.id)),
              ),
            ),
        ],
      );
    },
  );
}

/// One repair request: what each person sees and does.
class DealRepair extends StatefulWidget {
  const DealRepair({required this.store, required this.deal, required this.role, required this.id, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;
  final String id;

  @override
  State<DealRepair> createState() => _DealRepairState();
}

class _DealRepairState extends State<DealRepair> {
  final min = TextEditingController(),
      max = TextEditingController(),
      days = TextEditingController(),
      amount = TextEditingController(),
      message = TextEditingController();
  bool notOwner = false;
  String photo = '';
  final bad = <String>{};

  Tk2Deal get d => widget.deal;
  DealRole get role => widget.role;
  String get id => widget.id;
  Tk2Repair get r => d.repairs.firstWhere((x) => x.id == id);

  @override
  void dispose() {
    for (final c in [min, max, days, amount, message]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
  Map<String, dynamic> _sub(Map<String, dynamic> part, String key) => Map<String, dynamic>.from(part[key] as Map? ?? const {});

  Future<void> _save(DealRole who, {bool close = true}) async {
    await widget.store.saveDeal(d, who);
    if (!mounted) return;
    close ? Navigator.of(context).pop() : setState(() {});
  }

  Future<void> _quote() async {
    bad
      ..clear()
      ..addAll({if (_n(min) <= 0) 'min', if (_n(max) < _n(min)) 'max', if (_n(days) <= 0) 'days'});
    if (bad.isNotEmpty) return setState(() {});
    d.b['quotes'] = _sub(d.b, 'quotes')..[id] = {'min': _n(min), 'max': _n(max), 'days': _n(days), if (notOwner) 'notOwner': true};
    await _save(DealRole.broker);
  }

  Future<void> _fixed() async {
    bad
      ..clear()
      ..addAll({if (_n(amount) <= 0) 'amount', if (photo.isEmpty) 'photo'});
    if (bad.isNotEmpty) return setState(() {});
    d.b['quotes'] = _sub(d.b, 'quotes')..[id] = {...r.quote, 'done': DateTime.now().millisecondsSinceEpoch, 'photo': photo, 'amount': _n(amount)};
    await _save(DealRole.broker);
  }

  Future<void> _answer(bool ok) async {
    if (!ok &&
        !await onbConfirm(
          context,
          title: 'Do not fix this?',
          message: 'The request is closed. The tenant and the broker are told.',
          yes: 'Close the request',
          danger: true,
        )) {
      return;
    }
    d.o['rep'] = _sub(d.o, 'rep')..[id] = {'ok': ok};
    await _save(DealRole.owner);
  }

  Future<void> _withdraw() async {
    if (!await onbConfirm(context, title: 'Take back this request?', message: 'Nothing more happens with it.', yes: 'Take it back', danger: true)) return;
    d.t['repairs'] = [
      for (final x in (d.t['repairs'] as List).cast<Map>()) x['id'] == id ? {...x, 'off': true} : x,
    ];
    await _save(DealRole.tenant);
  }

  Future<void> _say() async {
    if (message.text.trim().isEmpty) return;
    final me = d.part(role);
    me['msgs'] = [
      ...(me['msgs'] as List? ?? const []),
      {'r': id, 'text': message.text.trim(), 'at': DateTime.now().millisecondsSinceEpoch},
    ];
    message.clear();
    await _save(role, close: false);
  }

  Widget _money(TextEditingController c, String key, String label, String error) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OnbTextField(
      label: label,
      controller: c,
      keyboard: TextInputType.number,
      prefix: key == 'days' ? null : '₹ ',
      formatters: [FilteringTextInputFormatter.digitsOnly],
      error: bad.contains(key) ? error : null,
      onChanged: (_) => setState(() => bad.remove(key)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = this.r;
    final mine = r.open && r.waitingOn == role;
    final chat = d.chat(id);
    final canTalk = role != DealRole.broker && r.open;
    final (String? label, VoidCallback? action) = !mine
        ? (null, null)
        : switch (r.taskKey) {
            'quote' => ('Send to the owner', _quote),
            'approve' => ('Yes, fix it', () => _answer(true)),
            'fixed' => ('Fixed · ask the owner to pay', _fixed),
            _ => (
              'Pay ${Tk2Store.money(r.amount)}',
              () async {
                await dealPush(
                  context,
                  DealPay(
                    title: 'Pay for the repair',
                    intro: 'The broker got this fixed and paid for it. This pays them back the exact amount.',
                    lines: [(r.text, r.amount)],
                    onPaid: () {
                      d.o['rep'] = _sub(d.o, 'rep')..[id] = {...r.answer, 'paid': true, 'at': DateTime.now().millisecondsSinceEpoch};
                      return widget.store.saveDeal(d, DealRole.owner);
                    },
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          };
    return OnbPage(
      title: 'Repair',
      subtitle: r.status(role),
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        if (label != null) PrimaryButton(label: label, icon: Icons.chevron_right, onPressed: action),
        if (mine && r.taskKey == 'approve') ...[
          const SizedBox(height: 10),
          OnbSecondaryButton(label: 'Do not fix this', danger: true, onPressed: () => _answer(false)),
        ],
        if (role == DealRole.tenant && r.open && !r.fixed) ...[
          if (label != null) const SizedBox(height: 10),
          OnbSecondaryButton(label: 'Take back this request', danger: true, onPressed: _withdraw),
        ],
      ],
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DealPhoto(r.photo),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.text,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
                  Text('Reported on ${tk2DateOf(DateTime.fromMillisecondsSinceEpoch(r.at))}', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (r.quoted)
          OnbCard(
            child: Column(
              children: [
                // The owner decides on the cost; the tenant mainly needs the time.
                if (role != DealRole.tenant) OnbKeyValue('Cost, about', r.range),
                OnbKeyValue('Time to fix, about', '${r.days} ${r.days == 1 ? 'day' : 'days'}', last: !r.fixed),
                if (r.fixed && role != DealRole.tenant) OnbKeyValue('Final cost', Tk2Store.money(r.amount)),
                if (r.fixed) OnbKeyValue('Status', r.paid ? 'Fixed and paid' : 'Fixed', last: true),
              ],
            ),
          ),
        if (r.fixed) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              DealPhoto(r.donePhoto),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Photo of the finished work. It is added to the handover record.', style: TextStyle(fontSize: 14.5, color: AppColors.muted)),
              ),
            ],
          ),
        ],
        if (r.notOwners && r.open) ...[
          const SizedBox(height: 12),
          OnbBanner(
            role == DealRole.broker
                ? 'You marked this as not the owner\'s to fix. The owner and the tenant talk here to agree.'
                : 'The broker says this may not be the owner\'s to fix. Talk here to agree who pays.',
            kind: 'need',
            icon: Icons.forum_outlined,
          ),
        ],
        if (mine && r.taskKey == 'quote') ...[
          dealHeading('Cost and time'),
          dealText('The owner sees the cost. The tenant sees the time.'),
          const SizedBox(height: 12),
          _money(min, 'min', 'Cost from', 'Type the lowest cost'),
          _money(max, 'max', 'Cost up to', 'Must be the same or more'),
          _money(days, 'days', 'Days to fix', 'Type how many days'),
          DealSwitch(
            title: 'This is not the owner\'s to fix',
            subtitle: 'Something new, or not a fair ask. The owner and tenant talk it out.',
            value: notOwner,
            onChanged: (v) => setState(() => notOwner = v),
          ),
        ],
        if (mine && r.taskKey == 'approve') ...[
          const SizedBox(height: 12),
          dealText('Old problems and things that came with the house are yours to fix. The broker gets it done and you pay the exact amount after.'),
        ],
        if (mine && r.taskKey == 'fixed') ...[
          dealHeading('Finished work'),
          _money(amount, 'amount', 'Exact amount spent', 'Type what it cost'),
          DealPhotoRow(
            title: 'Photo of the finished work',
            path: photo,
            need: bad.contains('photo'),
            onPick: () async {
              final p = await dealPickPhoto(context, d);
              if (p != null && mounted) {
                setState(() {
                  photo = p;
                  bad.remove('photo');
                });
              }
            },
          ),
        ],
        if (chat.isNotEmpty || (canTalk && r.quoted)) ...[
          dealHeading(role == DealRole.broker ? 'Owner and tenant' : 'Talk to the ${role == DealRole.tenant ? 'owner' : 'tenant'}'),
          for (final m in chat)
            Align(
              alignment: m.from == role ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(color: m.from == role ? AppColors.primarySoft : AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.from != role)
                      Text(
                        d.nameOf(m.from).split(' ').first,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                    Text(m.text, style: const TextStyle(fontSize: 15.5, color: AppColors.heading)),
                  ],
                ),
              ),
            ),
          if (canTalk)
            Row(
              children: [
                Expanded(
                  child: OnbTextField(label: 'Message', controller: message, capitalization: TextCapitalization.sentences),
                ),
                const SizedBox(width: 10),
                IconButton.filled(tooltip: 'Send', onPressed: _say, icon: const Icon(Icons.send)),
              ],
            ),
          if (role != DealRole.broker)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('The broker can read this.', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------- society

IconData _kindIcon(String kind) => switch (kind) {
  'email' => Icons.mail_outline,
  'approval' => Icons.thumb_up_alt_outlined,
  'reply' => Icons.reply_outlined,
  'visit' => Icons.directions_walk,
  'upload' => Icons.upload_file_outlined,
  'gate' => Icons.sensor_door_outlined,
  _ => Icons.payments_outlined,
};

/// Broker: the society's move-in steps, written once and reused for every
/// tenant moving into that society.
class DealPlaybook extends StatefulWidget {
  const DealPlaybook({required this.store, required this.deal, super.key});
  final Tk2Store store;
  final Tk2Deal deal;

  @override
  State<DealPlaybook> createState() => _DealPlaybookState();
}

class _DealPlaybookState extends State<DealPlaybook> {
  late final name = TextEditingController(
    text: widget.deal.societyName.isNotEmpty ? widget.deal.societyName : widget.store.listing(widget.deal.listingId)?.society ?? '',
  );
  late List<Map<String, dynamic>> steps = _load();
  late bool saved = widget.store.playbooks.containsKey(name.text.trim().toLowerCase());
  String? error;

  List<Map<String, dynamic>> _load() {
    final mine = widget.deal.societySteps.map((s) => s.data).toList();
    if (mine.isNotEmpty) return mine;
    final kept = widget.store.playbooks[name.text.trim().toLowerCase()];
    return [for (final s in kept ?? Tk2SocietyStep.starter) Map<String, dynamic>.from(s as Map)];
  }

  @override
  void initState() {
    super.initState();
    // Backend: another broker may already have written this society's steps.
    if (!saved && widget.deal.societySteps.isEmpty) {
      widget.store.sync?.fetchPlaybook(name.text).then((shared) {
        if (shared == null || shared.isEmpty || !mounted) return;
        setState(() {
          steps = [for (final s in shared) Map<String, dynamic>.from(s as Map)];
          saved = true;
        });
      }).ignore();
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _edit([int? at]) async {
    var kind = at == null ? null : steps[at]['k'] as String;
    if (at == null) {
      kind = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tk2SheetTitle('Add a step', 'What kind of step is it?'),
                for (final e in Tk2SocietyStep.kinds.entries)
                  tk2SheetRow(
                    leading: Icon(_kindIcon(e.key), size: 26, color: AppColors.primaryDark),
                    title: e.value.$1,
                    sub: e.value.$2,
                    onTap: () => Navigator.of(sheet).pop(e.key),
                  ),
              ],
            ),
          ),
        ),
      );
      if (kind == null || !mounted) return;
    }
    final step = await dealPush<Map<String, dynamic>>(context, _StepEdit(kind: kind!, step: at == null ? null : steps[at]));
    if (step == null || !mounted) return;
    setState(() => at == null ? steps.add(step) : steps[at] = step);
  }

  Future<void> _save({bool none = false}) async {
    final d = widget.deal;
    if (!none && name.text.trim().length < 2) return setState(() => error = 'Type the society name');
    if (!none && steps.isEmpty) return setState(() => error = 'Add at least one step, or say there are none');
    d.b['soc'] = none ? {'none': true} : {'name': name.text.trim(), 'steps': steps};
    if (!none) await widget.store.savePlaybook(name.text.trim(), steps);
    await widget.store.saveDeal(d, DealRole.broker);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: 'Society move-in steps',
    subtitle: 'Write them once. We use them for every tenant moving in here.',
    onBack: () => Navigator.of(context).maybePop(),
    footer: [
      PrimaryButton(label: 'Start these steps', icon: Icons.chevron_right, onPressed: _save),
      const SizedBox(height: 10),
      OnbSecondaryButton(label: 'This house has no society steps', onPressed: () => _save(none: true)),
    ],
    children: [
      OnbTextField(
        label: 'Society name *',
        controller: name,
        capitalization: TextCapitalization.words,
        error: error,
        onChanged: (_) => setState(() => error = null),
      ),
      const SizedBox(height: 10),
      OnbBanner(
        saved
            ? 'These are the steps saved for this society. Change them if the rules changed.'
            : 'A common set to start from. Change it to match this society.',
        kind: 'info',
        icon: Icons.lightbulb_outline,
      ),
      const SizedBox(height: 14),
      for (final (i, s) in steps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OnbRow(
            icon: _kindIcon(s['k'] as String),
            title: '${i + 1}. ${s['title']}',
            subtitle: '${Tk2SocietyStep.kinds[s['k']]!.$1} · done by the ${s['who']}',
            chevron: false,
            onTap: () => _edit(i),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0)
                  IconButton(
                    tooltip: 'Move up',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => steps.insert(i - 1, steps.removeAt(i))),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => steps.removeAt(i)),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
      OnbSecondaryButton(label: 'Add a step', onPressed: _edit),
    ],
  );
}

class _StepEdit extends StatefulWidget {
  const _StepEdit({required this.kind, this.step});
  final String kind;
  final Map<String, dynamic>? step;

  @override
  State<_StepEdit> createState() => _StepEditState();
}

class _StepEditState extends State<_StepEdit> {
  late final info = Tk2SocietyStep.kinds[widget.kind]!;
  late final title = TextEditingController(text: widget.step?['title'] as String? ?? info.$1);
  late final text = TextEditingController(text: widget.step?['text'] as String? ?? '');
  late final to = TextEditingController(text: widget.step?['to'] as String? ?? '');
  late String who = widget.step?['who'] as String? ?? info.$3;
  final bad = <String>{};

  @override
  void dispose() {
    for (final c in [title, text, to]) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    final email = widget.kind == 'email';
    bad
      ..clear()
      ..addAll({if (title.text.trim().length < 3) 'title', if (email && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(to.text.trim())) 'to'});
    if (bad.isNotEmpty) return setState(() {});
    Navigator.of(
      context,
    ).pop(<String, dynamic>{'k': widget.kind, 'who': who, 'title': title.text.trim(), 'text': text.text.trim(), if (email) 'to': to.text.trim()});
  }

  @override
  Widget build(BuildContext context) => OnbPage(
    title: info.$1,
    subtitle: info.$2,
    onBack: () => Navigator.of(context).maybePop(),
    footer: [PrimaryButton(label: 'Save step', icon: Icons.check, onPressed: _done)],
    children: [
      OnbTextField(
        label: 'Short name of the step *',
        controller: title,
        capitalization: TextCapitalization.sentences,
        error: bad.contains('title') ? 'Give the step a name' : null,
        onChanged: (_) => setState(() => bad.remove('title')),
      ),
      const SizedBox(height: 12),
      if (widget.kind == 'email') ...[
        OnbTextField(
          label: 'Society office email *',
          controller: to,
          keyboard: TextInputType.emailAddress,
          error: bad.contains('to') ? 'Type a valid email' : null,
          onChanged: (_) => setState(() => bad.remove('to')),
        ),
        const SizedBox(height: 12),
      ],
      OnbTextField(
        label: switch (widget.kind) {
          'email' => 'What the email says',
          'reply' => 'The ready-made reply',
          'visit' => 'Where to go and what to carry',
          'fee' => 'What the fee is and how much',
          _ => 'What to do',
        },
        controller: text,
        maxLines: 4,
        capitalization: TextCapitalization.sentences,
      ),
      dealHeading('Who does this step?'),
      Wrap(
        spacing: 8,
        children: [
          for (final w in ['broker', 'tenant', 'owner'])
            ChoiceChip(
              label: Text(w == 'broker' ? 'Me (broker)' : 'The $w'),
              selected: who == w,
              showCheckmark: false,
              selectedColor: AppColors.primarySoft,
              side: BorderSide(color: who == w ? AppColors.primary : AppColors.border),
              onSelected: (_) => setState(() => who = w),
            ),
        ],
      ),
      if (widget.kind == 'email') ...[
        const SizedBox(height: 12),
        const OnbBanner(
          'We add the tenant names, the flat and the move-in date. The broker, owner and tenant are in CC.',
          kind: 'info',
          icon: Icons.info_outline,
        ),
      ],
    ],
  );
}

/// The society's steps, in order, with who each one is waiting for.
class DealSociety extends StatelessWidget {
  const DealSociety({required this.store, required this.deal, required this.role, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final steps = deal.societySteps;
      final next = steps.where((s) => !s.done).firstOrNull;
      return OnbPage(
        title: 'Society move-in',
        subtitle: deal.societyName,
        onBack: () => Navigator.of(context).maybePop(),
        footer: [
          if (role == DealRole.broker && steps.every((s) => !s.done))
            OnbSecondaryButton(
              label: 'Change the steps',
              onPressed: () => dealPush(context, DealPlaybook(store: store, deal: deal)),
            ),
        ],
        children: [
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OnbRow(
                icon: s.done ? Icons.check : _kindIcon(s.kind),
                tone: s.done ? 'ok' : (s == next ? (s.who == role ? 'need' : 'wait') : 'mute'),
                title: '${s.index + 1}. ${s.title}',
                subtitle: s.done ? 'Done' : (s == next ? (s.who == role ? 'Your turn' : 'Waiting for the ${Tk2Deal.who(s.who)}') : 'After the step before it'),
                onTap: () => dealPush(context, DealSocietyStep(store: store, deal: deal, role: role, index: s.index)),
              ),
            ),
        ],
      );
    },
  );
}

/// One society step: what to do, and "done" for the person whose turn it is.
class DealSocietyStep extends StatefulWidget {
  const DealSocietyStep({required this.store, required this.deal, required this.role, required this.index, super.key});
  final Tk2Store store;
  final Tk2Deal deal;
  final DealRole role;
  final int index;

  @override
  State<DealSocietyStep> createState() => _DealSocietyStepState();
}

class _DealSocietyStepState extends State<DealSocietyStep> {
  String file = '';
  bool need = false;

  Tk2Deal get d => widget.deal;
  Tk2SocietyStep get s => d.societySteps[widget.index];

  String get _body {
    final start = DateTime.tryParse('${d.terms['start']}');
    return [
      'Dear Sir / Madam,',
      s.text,
      'Flat: ${d.terms['address'] ?? d.title}',
      'Tenant: ${d.nameOf(DealRole.tenant)} (${d.tenantPhone})',
      'Owner: ${d.nameOf(DealRole.owner)}',
      if (start != null) 'Move-in date: ${tk2DateOf(start)}',
      'Regards,\n${d.nameOf(DealRole.broker)}\nvia TrustKeyper',
    ].join('\n\n');
  }

  Future<void> _done() async {
    if (s.kind == 'upload' && file.isEmpty) return setState(() => need = true);
    final me = d.part(widget.role);
    me['soc'] = {...Map<String, dynamic>.from(me['soc'] as Map? ?? const {}), '${widget.index}': true};
    if (file.isNotEmpty) me['socFiles'] = {...Map<String, dynamic>.from(me['socFiles'] as Map? ?? const {}), '${widget.index}': file};
    await widget.store.saveDeal(d, widget.role);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _email() {
    final tenantEmail = Map<String, dynamic>.from(d.t['details'] as Map? ?? const {})['email'] as String? ?? '';
    return launchUrl(
      Uri(
        scheme: 'mailto',
        path: s.to,
        query: [
          if (tenantEmail.isNotEmpty) 'cc=${Uri.encodeComponent(tenantEmail)}',
          'subject=${Uri.encodeComponent('Tenant moving in · ${d.terms['address'] ?? d.title}')}',
          'body=${Uri.encodeComponent(_body)}',
        ].join('&'),
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = this.s;
    final steps = d.societySteps;
    final myTurn = !s.done && s.who == widget.role && steps.where((x) => !x.done).first.index == s.index;
    return OnbPage(
      title: s.title,
      step: 'Step ${s.index + 1} of ${steps.length}',
      subtitle: d.societyName,
      onBack: () => Navigator.of(context).maybePop(),
      footer: [
        if (myTurn && s.kind == 'email') ...[OnbSecondaryButton(label: 'Open the email', onPressed: _email), const SizedBox(height: 10)],
        if (myTurn)
          PrimaryButton(
            label: switch (s.kind) {
              'email' => 'I sent the email',
              'approval' => 'I approved',
              'reply' => 'I sent the reply',
              'visit' => 'I did this',
              'upload' => 'Send the file',
              'gate' => 'The gate app works',
              _ => 'Paid',
            },
            icon: Icons.check,
            onPressed: _done,
          ),
      ],
      children: [
        if (s.done)
          const OnbBanner('Done', kind: 'ok', icon: Icons.check_circle_outline)
        else if (!myTurn)
          OnbBanner(
            s.who == widget.role ? 'This opens after the step before it.' : 'Waiting for the ${Tk2Deal.who(s.who)}.',
            kind: 'wait',
            icon: Icons.hourglass_top,
          ),
        const SizedBox(height: 12),
        if (s.kind == 'email') ...[
          OnbCard(child: Column(children: [OnbKeyValue('To', s.to), const OnbKeyValue('CC', 'Broker, owner and tenant', last: true)])),
          const SizedBox(height: 12),
          OnbCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              _body,
              style: const TextStyle(fontSize: 14.5, height: 21 / 14.5, color: AppColors.body),
            ),
          ),
          if (myTurn) ...[
            const SizedBox(height: 12),
            const OnbBanner(
              'For now this opens your own mail app, with everyone in CC. Sending from a TrustKeyper address comes with the email service.',
              kind: 'wait',
              icon: Icons.science_outlined,
            ),
          ],
        ] else if (s.text.isNotEmpty)
          dealText(s.text),
        if (s.kind == 'reply' && myTurn && s.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          OnbSecondaryButton(
            label: 'Copy the reply',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: s.text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Reply copied')));
              }
            },
          ),
        ],
        if (s.kind == 'gate') ...[
          const SizedBox(height: 12),
          const OnbBanner(
            'We cannot add you on the gate app ourselves. The society office does it; tell us here when it works.',
            kind: 'info',
            icon: Icons.info_outline,
          ),
        ],
        if (s.kind == 'upload' && myTurn) ...[
          const SizedBox(height: 12),
          DealPhotoRow(
            title: 'Photo of the document',
            path: file,
            need: need,
            onPick: () async {
              final p = await dealPickPhoto(context, d);
              if (p != null && mounted) {
                setState(() {
                  file = p;
                  need = false;
                });
              }
            },
          ),
        ],
      ],
    );
  }
}
