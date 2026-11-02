import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

/// After the house facts: rent, deposit, move-in date, visit fee and photos.
class Tk2ListingForm extends StatefulWidget {
  const Tk2ListingForm({required this.store, required this.id, this.isNew = false, super.key});
  final Tk2Store store;
  final String id;
  final bool isNew;

  @override
  State<Tk2ListingForm> createState() => _Tk2ListingFormState();
}

class _Tk2ListingFormState extends State<Tk2ListingForm> {
  late final Tk2Listing? start = widget.store.listing(widget.id);
  late final rent = TextEditingController(text: (start?.rent ?? 0) > 0 ? '${start!.rent}' : '');
  late final deposit = TextEditingController(text: (start?.deposit ?? 0) > 0 ? '${start!.deposit}' : '');
  late final brokerage = TextEditingController(text: (start?.brokerage ?? 0) > 0 ? '${start!.brokerage}' : '');
  late String availableFrom = start?.availableFrom ?? '';
  late final fee = TextEditingController(text: '${start?.visitFee ?? 150}');
  late final society = TextEditingController(text: start?.society ?? '');
  late final locality = TextEditingController(text: start?.locality ?? '');
  late final door = TextEditingController(text: start?.door ?? '');
  late final ownerName = TextEditingController(text: start?.ownerName ?? '');
  late final ownerPhone = TextEditingController(text: start?.ownerPhone ?? '');
  late final note = TextEditingController(text: start?.note ?? '');
  late String keys = start?.keys ?? '';
  String? feeError;
  late final maintenance = TextEditingController(text: (start?.maintenance ?? 0) > 0 ? '${start!.maintenance}' : '');
  late bool included = start?.maintenanceIncluded ?? true;
  late Set<String> who = Tk2Listing.tenantSet(start?.tenants ?? 'Anyone');
  // none · 15 · 30 · amount
  late String brokerageWay = (start?.brokerage ?? 0) == 0
      ? 'none'
      : start!.brokerageDays == 15
      ? '15'
      : start!.brokerageDays == 30
      ? '30'
      : 'amount';
  late bool availableNow = (start?.availableFrom ?? '').isEmpty;
  late String visitDays = start?.visitDays ?? 'all';
  int step = 0;
  static const _titles = ['Rent details', 'Visits', 'Photos', 'Only for you'];
  late bool pets = start?.pets ?? true;
  late List<String> photos = [...?start?.photos];

  /// Sections that need attention (shown in red): place, rent, maintenance.
  final Set<String> missing = {};
  late int visitFrom = start?.visitFrom ?? 7;
  late int visitTo = start?.visitTo ?? 23;
  bool saving = false;

  @override
  void dispose() {
    rent.dispose();
    deposit.dispose();
    brokerage.dispose();
    maintenance.dispose();
    for (final c in [fee, society, locality, door, ownerName, ownerPhone, note]) {
      c.dispose();
    }
    super.dispose();
  }

  int _num(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _addPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600, limit: 10);
      if (picked.isEmpty || !mounted) return;
      setState(() => photos = [...photos, ...picked.map((p) => p.path)].take(10).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Could not open your photos. Allow photo access in Settings.')));
    }
  }

  Future<void> _pickDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final current = DateTime.tryParse(availableFrom) ?? now;
    final d = await showDatePicker(context: context, initialDate: current.isBefore(now) ? now : current, firstDate: now, lastDate: now.add(const Duration(days: 330)), helpText: 'Available from');
    if (d != null) {
      setState(() => availableFrom = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  /// Parts of this step that still need an answer (shown in red).
  Set<String> _check(int at) => {
    if (at == 0 && _num(rent) <= 0) 'rent',
    if (at == 0 && !included && _num(maintenance) <= 0) 'maintenance',
    if (at == 0 && brokerageWay == 'amount' && _num(brokerage) <= 0) 'brokerage',
    if (at == 0 && who.isEmpty) 'who',
    if (at == 0 && !availableNow && availableFrom.isEmpty) 'date',
    if (at == 1 && _num(fee) > Tk2Listing.maxVisitFee) 'fee',
  };

  int get _brokerageAmount => switch (brokerageWay) {
    '15' => Tk2Listing.brokerageFor(_num(rent), 15),
    '30' => Tk2Listing.brokerageFor(_num(rent), 30),
    'amount' => _num(brokerage),
    _ => 0,
  };

  void _next() {
    final need = _check(step);
    if (need.isNotEmpty) {
      setState(
        () => missing
          ..clear()
          ..addAll(need),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    if (step < _titles.length - 1) {
      setState(() {
        missing.clear();
        step++;
      });
    } else {
      _save();
    }
  }

  void _back() {
    if (step > 0) {
      setState(() {
        missing.clear();
        step--;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _save() async {
    final l = start;
    if (l == null) return;
    setState(() => saving = true);
    await widget.store.saveListing(
      l.copyWith(
        rent: _num(rent),
        deposit: _num(deposit),
        brokerage: _brokerageAmount,
        brokerageDays: brokerageWay == '15'
            ? 15
            : brokerageWay == '30'
            ? 30
            : 0,
        visitDays: visitDays,
        visitFrom: visitFrom,
        visitTo: visitTo,
        availableFrom: availableNow ? '' : availableFrom,
        photos: photos,
        visitFee: _num(fee),
        society: society.text.trim(),
        locality: locality.text.trim(),
        door: door.text.trim(),
        ownerName: ownerName.text.trim(),
        ownerPhone: ownerPhone.text.trim(),
        keys: keys,
        note: note.text.trim(),
        maintenance: included ? 0 : _num(maintenance),
        maintenanceIncluded: included,
        tenants: Tk2Listing.tenantText(who),
        pets: pets,
      ),
    );
    if (!mounted) return;
    if (widget.isNew) {
      context.go('/home');
      context.push('/p/${l.id}?added=1');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = start;
    if (l == null) return const Tk2Missing();
    final last = step == _titles.length - 1;
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              OnbHeader(title: _titles[step], subtitle: 'Step ${step + 1} of ${_titles.length} · ${l.name}', onBack: _back),
              Expanded(
                child: OnbShadowBody(
                  // Each step slides in from the right, like a new screen.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: ListView(
                      key: ValueKey(step),
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      children: [
                        ...switch (step) {
                          0 => _rentStep(),
                          1 => _visitStep(),
                          2 => _photoStep(l),
                          _ => _privateStep(),
                        },
                        // The button scrolls with the page, so the keyboard never hides it.
                        const SizedBox(height: 28),
                        PrimaryButton(
                          label: last ? (widget.isNew ? 'Save property' : 'Save') : 'Next',
                          icon: last ? Icons.check : Icons.chevron_right,
                          loading: saving,
                          onPressed: saving ? null : _next,
                        ),
                        if (step == 2 && photos.isEmpty) ...[
                          const SizedBox(height: 4),
                          Center(
                            child: TextButton(onPressed: _next, child: const Text('Skip for now')),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _rentStep() => [
    // Rent and maintenance side by side; "Extra" opens the amount.
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _moneyField(rent, 'Rent / month', autofocus: widget.isNew && rent.text.isEmpty, bad: missing.contains('rent')),
        ),
        const SizedBox(width: 12),
        Expanded(child: _pick<bool>('Maintenance', included, const {true: 'Included', false: 'Extra'}, (v) => included = v)),
      ],
    ),
    if (missing.contains('rent')) _needed('Type the monthly rent'),
    if (!included) ...[const SizedBox(height: 12), _moneyField(maintenance, 'Maintenance / month', bad: missing.contains('maintenance'))],
    if (missing.contains('maintenance')) _needed('Type the maintenance amount'),
    const SizedBox(height: 12),
    _moneyField(deposit, 'Security deposit'),
    const SizedBox(height: 12),
    // Brokerage: none, part of rent, or a fixed amount (opens the amount).
    _pick<String>('Brokerage (paid by tenant)', brokerageWay, const {'none': 'No brokerage', '15': '15 days rent', '30': '1 month rent', 'amount': 'Fixed amount'}, (v) => brokerageWay = v),
    if (brokerageWay == '15' || brokerageWay == '30')
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(_num(rent) > 0 ? 'Tenant pays ${Tk2Store.money(_brokerageAmount)}' : 'Type the rent to see the amount', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
      ),
    if (brokerageWay == 'amount') ...[const SizedBox(height: 12), _moneyField(brokerage, 'Brokerage amount', bad: missing.contains('brokerage'))],
    if (missing.contains('brokerage')) _needed('Type the brokerage amount'),
    const SizedBox(height: 20),
    _label('Who can rent'),
    _box('Anyone', who.length == Tk2Listing.tenantTypes.length),
    for (final t in Tk2Listing.tenantTypes) _box(t, who.contains(t)),
    if (missing.contains('who')) _needed('Tick at least one'),
    const SizedBox(height: 16),
    _label('Pets'),
    Wrap(
      spacing: 8,
      children: [
        ChoiceChip(label: const Text('Pets OK'), selected: pets, onSelected: (_) => setState(() => pets = true)),
        ChoiceChip(label: const Text('No pets'), selected: !pets, onSelected: (_) => setState(() => pets = false)),
      ],
    ),
    const SizedBox(height: 20),
    // "From a date" opens the date.
    _pick<bool>('Available', availableNow, const {true: 'Now', false: 'From a date'}, (v) {
      availableNow = v;
      if (!v && availableFrom.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _pickDate());
    }),
    if (!availableNow) ...[
      const SizedBox(height: 12),
      _row(icon: Icons.event_outlined, title: 'Available from', value: availableFrom.isEmpty ? 'Pick a date' : tk2Date(availableFrom), onTap: _pickDate),
    ],
    if (missing.contains('date')) _needed('Pick the date'),
  ];

  List<Widget> _visitStep() => [
    _label('Days for visits'),
    Wrap(
      spacing: 8,
      children: [
        for (final d in const {'all': 'Every day', 'weekdays': 'Mon – Fri', 'weekends': 'Sat, Sun'}.entries)
          ChoiceChip(label: Text(d.value), selected: visitDays == d.key, onSelected: (_) => setState(() => visitDays = d.key)),
      ],
    ),
    const SizedBox(height: 20),
    _label('Times for visits'),
    Row(
      children: [
        Expanded(
          child: _hourPick(
            'From',
            visitFrom,
            (h) => setState(() {
              visitFrom = h;
              if (visitTo < h) visitTo = h;
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _hourPick(
            'To',
            visitTo,
            (h) => setState(() {
              visitTo = h;
              if (visitFrom > h) visitFrom = h;
            }),
          ),
        ),
      ],
    ),
    const SizedBox(height: 6),
    const Text('Customers can book only on these days and times.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
    const SizedBox(height: 26),
    const Text(
      'Visit fee',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
    const SizedBox(height: 4),
    const Text(
      'The customer pays this to book. You get it after the visit. Type 0 for a free visit.',
      style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: fee,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      onChanged: (_) => setState(() => feeError = _num(fee) > Tk2Listing.maxVisitFee ? 'Visit fee can be up to ₹${Tk2Listing.maxVisitFee}' : null),
      decoration: InputDecoration(
        labelText: 'Visit fee',
        prefixText: '₹ ',
        helperText: _num(fee) == 0 ? 'Free visit – customers book without paying' : 'Up to ₹${Tk2Listing.maxVisitFee}. Type 0 for a free visit.',
        errorText: feeError,
      ),
    ),
  ];

  List<Widget> _photoStep(Tk2Listing l) => [
    Tk2Appear(
      index: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Photos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
                ),
              ),
              Text('${photos.length}/10', style: const TextStyle(color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Good photos get more visits. Start with the living room.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (photos.length < 10)
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _addPhotos,
                    child: Container(
                      width: 104,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: AppColors.primaryDark),
                          SizedBox(height: 6),
                          Text(
                            'Add photos',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (var i = 0; i < photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Tk2Photo(
                            listing: l.copyWith(photos: photos),
                            index: i,
                            height: 104,
                            radius: 18,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => photos = [...photos]..removeAt(i)),
                            child: const CircleAvatar(
                              radius: 13,
                              backgroundColor: Color(0xCC172231),
                              child: Icon(Icons.close, size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                        if (i == 0) const Positioned(left: 6, bottom: 6, child: Tk2Pill('Cover', kind: 'dark')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _privateStep() => [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFE6CF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: AppColors.success),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confidential · only for you',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.success),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'This is never shared with customers – not in the message, not on the link.',
                      style: TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _text(ownerName, 'Owner name', Icons.person_outline, filled: true),
          const SizedBox(height: 12),
          _text(ownerPhone, 'Owner phone', Icons.call_outlined, phone: true, filled: true),
          const SizedBox(height: 16),
          _label('Keys'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final k in Tk2Listing.keyChoices) ChoiceChip(label: Text(k), selected: keys == k, onSelected: (_) => setState(() => keys = keys == k ? '' : k))],
          ),
          const SizedBox(height: 16),
          _text(note, 'Note for yourself', Icons.sticky_note_2_outlined, filled: true),
        ],
      ),
    ),
  ];

  /// Tick box row for "Who can rent".
  Widget _box(String label, bool on) => CheckboxListTile(
    value: on,
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
    onChanged: (_) => setState(() {
      who = Tk2Listing.toggleTenant(who, label);
      missing.remove('who');
    }),
  );

  /// A small drop-down in the same field style.
  Widget _pick<T>(String label, T value, Map<T, String> options, void Function(T) onChanged) => DropdownButtonFormField<T>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [for (final o in options.entries) DropdownMenuItem(value: o.key, child: Text(o.value))],
    onChanged: (v) {
      if (v == null) return;
      setState(() {
        onChanged(v);
        missing.removeAll(const ['maintenance', 'brokerage', 'date']);
      });
    },
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
  );

  Widget _text(TextEditingController c, String label, IconData icon, {bool phone = false, bool bad = false, bool filled = false}) => TextField(
    controller: c,
    keyboardType: phone ? TextInputType.phone : TextInputType.text,
    textCapitalization: phone ? TextCapitalization.none : TextCapitalization.words,
    onChanged: (_) => setState(() => missing.clear()),
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), filled: filled, fillColor: Colors.white, enabledBorder: bad ? _redBorder : null, focusedBorder: bad ? _redBorder : null),
  );

  static final _redBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppColors.error, width: 1.6),
  );

  /// Short red line under a field that needs attention.
  Widget _needed(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(text, style: const TextStyle(color: AppColors.error, fontSize: 14)),
  );

  Widget _hourPick(String label, int value, ValueChanged<int> onChanged) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [for (final h in Tk2Listing.visitHours) DropdownMenuItem(value: h, child: Text(tk2Time(DateTime(2000, 1, 1, h))))],
    onChanged: (h) => onChanged(h ?? value),
  );

  Widget _moneyField(TextEditingController c, String label, {bool autofocus = false, bool bad = false}) => TextField(
    controller: c,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
    onChanged: (_) => setState(() => missing.clear()),
    decoration: InputDecoration(labelText: label, prefixText: '₹ ', enabledBorder: bad ? _redBorder : null, focusedBorder: bad ? _redBorder : null),
  );

  Widget _row({required IconData icon, required String title, required String value, required VoidCallback onTap}) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 16, color: AppColors.heading)),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class Tk2Missing extends StatelessWidget {
  const Tk2Missing({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const Center(
      child: Text('This property is not here any more.', style: TextStyle(fontSize: 16, color: AppColors.muted)),
    ),
  );
}

/// One visit line: who, when, and where the fee is.
class Tk2VisitRow extends StatelessWidget {
  const Tk2VisitRow({required this.visit, required this.store, this.showProperty = false, this.onTap, super.key});
  final Tk2Visit visit;
  final Tk2Store store;
  final bool showProperty;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final at = DateTime.fromMillisecondsSinceEpoch(v.at);
    final (pill, kind) = switch (v.status) {
      VisitStatus.done => ('${Tk2Store.money(v.fee)} yours', 'ok'),
      VisitStatus.cancelled => ('Cancelled · refunded', 'mute'),
      VisitStatus.customerCancelled => ('Customer cancelled', 'mute'),
      VisitStatus.noShow => ('Did not come · ${Tk2Store.money(v.brokerShare)} yours', 'ok'),
      _ => ('${Tk2Store.money(v.fee)} held', 'wait'),
    };
    final property = showProperty ? store.listing(v.listingId)?.name : null;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: v.upcoming ? AppColors.primarySoft : AppColors.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text(
                      '${at.day}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: v.upcoming ? AppColors.primaryDark : AppColors.muted),
                    ),
                    Text(const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][at.month - 1], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [tk2Day(at), tk2Time(at), ?property].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Tk2Pill(pill, kind: kind),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Share sheet: the message preview, WhatsApp in one tap, or copy.
Future<void> showTk2Share(BuildContext context, Tk2Store store, Tk2Listing l) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (sheet) {
    final text = store.shareText(l);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share this property',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
            ),
            const SizedBox(height: 4),
            const Text('Customers open the link, see the house and book a visit.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE7F8EF), borderRadius: BorderRadius.circular(16)),
              child: Text(
                text,
                style: const TextStyle(fontSize: 14.5, height: 21 / 14.5, color: AppColors.body),
              ),
            ),
            if (l.sample) ...[const SizedBox(height: 10), const Text('This is the example. Add your own property to share real details.', style: TextStyle(fontSize: 14, color: AppColors.warning))],
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () async {
                  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
                  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet);
                  if (!opened && context.mounted) {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('WhatsApp did not open. Message copied, paste it anywhere.')));
                    }
                  }
                },
                icon: tk2WhatsAppLogo(size: 22),
                label: const Text('Share on WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: tk2Green,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Message copied')));
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy message'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Test build: the link page is not live yet. Use Customer view to see what customers will see.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  },
);
