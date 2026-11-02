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
  const Tk2ListingForm({required this.store, required this.id, this.isNew = false, this.ownerMode = false, this.onDone, super.key});
  final Tk2Store store;
  final String id;
  final bool isNew;

  /// House owner on the web: no visit fee, no "Only for you" (brokerage is the broker's).
  final bool ownerMode;

  /// Called after saving instead of the broker app's routes.
  final VoidCallback? onDone;

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
  // Who pays the broker (Owner · Tenant · Both · None) and how much each.
  late String payer = start?.brokeragePayer ?? 'None';
  late final ownerFee = TextEditingController(text: (start?.ownerBrokerage ?? 0) > 0 ? '${start!.ownerBrokerage}' : '');
  late Set<int> visitDays = Tk2Listing.visitDaySet(start?.visitDays ?? 'all');
  int step = 0;
  static const _all = {'rent': 'Rent details', 'times': 'Visit times', 'fee': 'Visit fee', 'photos': 'Photos', 'private': 'Only for you'};
  late final List<String> _keys = widget.ownerMode ? const ['rent', 'times', 'photos'] : _all.keys.toList();
  List<String> get _titles => [for (final k in _keys) _all[k]!];
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
    ownerFee.dispose();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Could not open your photos. Allow photo access in Settings.')));
    }
  }

  Future<void> _pickDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final current = DateTime.tryParse(availableFrom) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: now,
      lastDate: now.add(const Duration(days: 330)),
      helpText: 'Property available from',
    );
    if (d != null) {
      // Today means "available now".
      setState(() => availableFrom = DateUtils.isSameDay(d, now) ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  /// Parts of this step that still need an answer (shown in red).
  Set<String> _check(int at) {
    final k = _keys[at];
    return {
      if (k == 'rent' && _num(rent) <= 0) 'rent',
      if (k == 'rent' && !included && _num(maintenance) <= 0) 'maintenance',
      if (k == 'rent' && who.isEmpty) 'who',
      if (k == 'times' && visitDays.isEmpty) 'days',
      if (k == 'fee' && _num(fee) > Tk2Listing.maxVisitFee) 'fee',
      if (k == 'private' && (payer == 'Owner' || payer == 'Both') && _num(ownerFee) <= 0) 'ownerFee',
      if (k == 'private' && (payer == 'Tenant' || payer == 'Both') && _num(brokerage) <= 0) 'tenantFee',
    };
  }

  int get _tenantFee => payer == 'Tenant' || payer == 'Both' ? _num(brokerage) : 0;
  int get _ownerFee => payer == 'Owner' || payer == 'Both' ? _num(ownerFee) : 0;

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
        brokerage: _tenantFee,
        brokerageDays: Tk2Listing.daysFor(_num(rent), _tenantFee),
        brokeragePayer: payer,
        ownerBrokerage: _ownerFee,
        visitDays: Tk2Listing.visitDayText(visitDays),
        visitFrom: visitFrom,
        visitTo: visitTo,
        availableFrom: availableFrom,
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
    if (widget.onDone != null) {
      setState(() => saving = false);
      widget.onDone!();
    } else if (widget.isNew) {
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
              OnbHeader(
                title: _titles[step],
                subtitle: widget.ownerMode ? 'Step ${step + 1} of ${_titles.length}' : 'Step ${step + 1} of ${_titles.length} · ${l.name}',
                onBack: _back,
              ),
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
                        ...switch (_keys[step]) {
                          'rent' => _rentStep(),
                          'times' => _visitStep(),
                          'fee' => _feeStep(),
                          'photos' => _photoStep(l),
                          _ => _privateStep(),
                        },
                        // The button scrolls with the page, so the keyboard never hides it.
                        const SizedBox(height: 28),
                        PrimaryButton(
                          label: last
                              ? (widget.ownerMode
                                    ? 'Next'
                                    : widget.isNew
                                    ? 'Save property'
                                    : 'Save')
                              : 'Next',
                          icon: last && !widget.ownerMode ? Icons.check : Icons.chevron_right,
                          loading: saving,
                          onPressed: saving ? null : _next,
                        ),
                        if (_keys[step] == 'photos' && photos.isEmpty) ...[
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
    const SizedBox(height: 8),
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
    // Tap opens the calendar with today already picked.
    _row(icon: Icons.event_outlined, title: 'Property available from', value: availableFrom.isEmpty ? 'Today' : tk2Date(availableFrom), onTap: _pickDate),
  ];

  List<Widget> _visitStep() => [
    _label('Days for visits'),
    // Every day first, then each day; pick any. All 7 picked = Every day.
    AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(missing.contains('days') ? 12 : 0),
      decoration: BoxDecoration(
        color: missing.contains('days') ? AppColors.errorSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: missing.contains('days') ? AppColors.error : Colors.transparent, width: 1.4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var d = 0; d <= 7; d++)
            FilterChip(
              label: Text(d == 0 ? 'Every day' : Tk2Listing.dayNames[d - 1]),
              selected: d == 0 ? visitDays.length == 7 : visitDays.contains(d),
              onSelected: (_) => setState(() {
                visitDays = Tk2Listing.toggleVisitDay(visitDays, d);
                missing.remove('days');
              }),
            ),
        ],
      ),
    ),
    if (missing.contains('days')) _needed('Pick at least one day'),
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
  ];

  List<Widget> _feeStep() => [
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
    Row(
      children: [
        const Expanded(
          child: Text(
            'Good photos get more visits. Tap ★ or drag a photo to the first place to make it the cover.',
            style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
          ),
        ),
        const SizedBox(width: 12),
        Text('${photos.length}/10', style: const TextStyle(color: AppColors.muted)),
      ],
    ),
    const SizedBox(height: 14),
    Tk2PhotoGrid(listing: l, photos: photos, onAdd: photos.length < 10 ? _addPhotos : null, onChanged: (next) => setState(() => photos = next)),
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
            children: [
              for (final k in Tk2Listing.keyChoices)
                ChoiceChip(label: Text(k), selected: keys == k, onSelected: (_) => setState(() => keys = keys == k ? '' : k)),
            ],
          ),
          const SizedBox(height: 16),
          _text(note, 'Note for yourself', Icons.sticky_note_2_outlined, filled: true),
          // Brokerage: same flow as the main app (who pays, how much each).
          const SizedBox(height: 20),
          _label('Your brokerage · who pays you?'),
          Wrap(
            spacing: 8,
            children: [
              for (final choice in const ['Owner', 'Tenant', 'Both', 'None'])
                ChoiceChip(
                  label: Text(choice),
                  selected: payer == choice,
                  onSelected: (_) => setState(() {
                    payer = choice;
                    missing.removeAll(const ['ownerFee', 'tenantFee']);
                  }),
                ),
            ],
          ),
          if (payer == 'Owner' || payer == 'Both') ...[
            const SizedBox(height: 16),
            _moneyField(ownerFee, 'From owner', bad: missing.contains('ownerFee'), filled: true),
            if (missing.contains('ownerFee')) _needed('Type the owner\'s brokerage'),
            _feePresets(ownerFee),
          ],
          if (payer == 'Tenant' || payer == 'Both') ...[
            const SizedBox(height: 16),
            _moneyField(brokerage, 'From tenant', bad: missing.contains('tenantFee'), filled: true),
            if (missing.contains('tenantFee')) _needed('Type the tenant\'s brokerage'),
            _feePresets(brokerage),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('Tenants see this amount before they book.', style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Expanded(
                  child: Text('You will get', style: TextStyle(color: Color(0xFF008763), fontSize: 16)),
                ),
                Text(
                  Tk2Store.money(_tenantFee + _ownerFee),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ];

  /// ½ month / 1 month rent shortcuts (as in the main app); any other amount can be typed.
  Widget _feePresets(TextEditingController c) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 8,
      children: [
        ActionChip(label: const Text('½ month rent'), onPressed: () => setState(() => c.text = '${Tk2Listing.brokerageFor(_num(rent), 15)}')),
        ActionChip(label: const Text('1 month rent'), onPressed: () => setState(() => c.text = '${_num(rent)}')),
      ],
    ),
  );

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
        missing.remove('maintenance');
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
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: filled,
      fillColor: Colors.white,
      enabledBorder: bad ? _redBorder : null,
      focusedBorder: bad ? _redBorder : null,
    ),
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

  Widget _moneyField(TextEditingController c, String label, {bool autofocus = false, bool bad = false, bool filled = false}) => TextField(
    controller: c,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
    onChanged: (_) => setState(() => missing.clear()),
    decoration: InputDecoration(
      labelText: label,
      prefixText: '₹ ',
      filled: filled,
      fillColor: Colors.white,
      enabledBorder: bad ? _redBorder : null,
      focusedBorder: bad ? _redBorder : null,
    ),
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
      VisitStatus.customerCancelledLate => ('Customer cancelled · ${Tk2Store.money(v.brokerShare)} yours', 'ok'),
      VisitStatus.noShow => ('Did not come · ${Tk2Store.money(v.brokerShare)} yours', 'ok'),
      _ when v.gatePass.isEmpty => ('${Tk2Store.money(v.fee)} held · add gate pass', 'wait'),
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
                    Text(
                      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][at.month - 1],
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
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
            if (l.sample) ...[
              const SizedBox(height: 10),
              const Text('This is the example. Add your own property to share real details.', style: TextStyle(fontSize: 14, color: AppColors.warning)),
            ],
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('WhatsApp did not open. Message copied, paste it anywhere.')),
                      );
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

/// Photos in 3 columns (up to 10). The first is the cover (blue border, "Cover").
/// Tap ★ to make a photo the cover, or long-press and drag it to a new place;
/// photos slide to their new places.
class Tk2PhotoGrid extends StatefulWidget {
  const Tk2PhotoGrid({required this.listing, required this.photos, required this.onChanged, this.onAdd, super.key});
  final Tk2Listing listing;
  final List<String> photos;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onAdd;

  @override
  State<Tk2PhotoGrid> createState() => _Tk2PhotoGridState();
}

class _Tk2PhotoGridState extends State<Tk2PhotoGrid> {
  String? dragging;

  void _move(String path, int to) {
    final next = [...widget.photos]..remove(path);
    next.insert(to.clamp(0, next.length), path);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 10.0;
      final size = (c.maxWidth - gap * 2) / 3;
      final photos = widget.photos;
      final count = photos.length + (widget.onAdd != null ? 1 : 0);
      final rows = (count / 3).ceil().clamp(1, 4);
      Offset at(int i) => Offset((i % 3) * (size + gap), (i ~/ 3) * (size + gap));
      return SizedBox(
        height: rows * size + (rows - 1) * gap,
        child: Stack(
          children: [
            for (var i = 0; i < photos.length; i++)
              AnimatedPositioned(
                key: ValueKey(photos[i]),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: at(i).dx,
                top: at(i).dy,
                width: size,
                height: size,
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != photos[i],
                  onAcceptWithDetails: (d) => _move(d.data, i),
                  builder: (context, over, _) => LongPressDraggable<String>(
                    data: photos[i],
                    onDragStarted: () => setState(() => dragging = photos[i]),
                    onDragEnd: (_) => setState(() => dragging = null),
                    feedback: SizedBox(
                      width: size,
                      height: size,
                      child: Opacity(opacity: 0.85, child: _tile(i, size, lifted: true)),
                    ),
                    childWhenDragging: Container(
                      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                    ),
                    child: AnimatedScale(scale: over.isNotEmpty ? 0.94 : 1, duration: const Duration(milliseconds: 150), child: _tile(i, size)),
                  ),
                ),
              ),
            if (widget.onAdd != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: at(photos.length).dx,
                top: at(photos.length).dy,
                width: size,
                height: size,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onAdd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(16),
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
              ),
          ],
        ),
      );
    },
  );

  Widget _tile(int i, double size, {bool lifted = false}) {
    final cover = i == 0;
    return Material(
      color: Colors.transparent,
      elevation: lifted ? 8 : 0,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cover ? AppColors.primary : Colors.transparent, width: 3),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Tk2Photo(
              listing: widget.listing.copyWith(photos: widget.photos),
              index: i,
              height: size,
              radius: 13,
              compact: true,
            ),
            if (cover)
              const Positioned(left: 6, bottom: 6, child: Tk2Pill('Cover', kind: 'dark'))
            else
              Positioned(
                left: 4,
                bottom: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _move(widget.photos[i], 0),
                  child: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xCC172231),
                    child: Icon(Icons.star_border_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onChanged([...widget.photos]..removeAt(i)),
                child: const CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xCC172231),
                  child: Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
