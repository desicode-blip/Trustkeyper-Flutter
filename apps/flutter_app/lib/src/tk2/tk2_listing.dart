import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
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
  late String availableFrom = start?.availableFrom ?? '';
  late int fee = start?.visitFee ?? 150;
  late final maintenance = TextEditingController(text: (start?.maintenance ?? 0) > 0 ? '${start!.maintenance}' : '');
  late bool included = start?.maintenanceIncluded ?? true;
  late String tenants = start?.tenants ?? 'Anyone';
  late bool pets = start?.pets ?? true;
  late List<String> photos = [...?start?.photos];
  String? error;
  bool saving = false;

  @override
  void dispose() {
    rent.dispose();
    deposit.dispose();
    maintenance.dispose();
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
    final d = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: now,
      lastDate: now.add(const Duration(days: 330)),
      helpText: 'Available from',
    );
    if (d != null) {
      setState(() => availableFrom = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    final l = start;
    if (l == null) return;
    if (_num(rent) <= 0) {
      setState(() => error = 'Type the monthly rent');
      return;
    }
    setState(() => saving = true);
    await widget.store.saveListing(l.copyWith(rent: _num(rent), deposit: _num(deposit), availableFrom: availableFrom, photos: photos, visitFee: fee, maintenance: included ? 0 : _num(maintenance), maintenanceIncluded: included, tenants: tenants, pets: pets));
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, surfaceTintColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        children: [
          Tk2Appear(child: Tk2Title(widget.isNew ? 'Rent and details' : 'Edit rent and details', subtitle: l.name)),
          const SizedBox(height: 28),
          Tk2Appear(
            index: 1,
            child: Row(
              children: [
                Expanded(child: _moneyField(rent, 'Rent / month', autofocus: widget.isNew && rent.text.isEmpty)),
                const SizedBox(width: 12),
                Expanded(child: _moneyField(deposit, 'Deposit')),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 15)),
          ],
          const SizedBox(height: 18),
          _label('Maintenance'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Included in rent'), selected: included, onSelected: (_) => setState(() => included = true)),
              ChoiceChip(label: const Text('Extra'), selected: !included, onSelected: (_) => setState(() => included = false)),
            ],
          ),
          if (!included) ...[
            const SizedBox(height: 12),
            _moneyField(maintenance, 'Maintenance / month'),
          ],
          const SizedBox(height: 18),
          _label('Who can rent'),
          Wrap(
            spacing: 8,
            children: [
              for (final t in const ['Family', 'Bachelors', 'Anyone'])
                ChoiceChip(label: Text(t), selected: tenants == t, onSelected: (_) => setState(() => tenants = t)),
            ],
          ),
          const SizedBox(height: 18),
          _label('Pets'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Pets OK'), selected: pets, onSelected: (_) => setState(() => pets = true)),
              ChoiceChip(label: const Text('No pets'), selected: !pets, onSelected: (_) => setState(() => pets = false)),
            ],
          ),
          const SizedBox(height: 18),
          Tk2Appear(
            index: 2,
            child: _row(
              icon: Icons.event_outlined,
              title: 'Available from',
              value: availableFrom.isEmpty ? 'Now' : tk2Date(availableFrom),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 26),
          Tk2Appear(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Visit fee', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
                const SizedBox(height: 4),
                const Text('The customer pays this to book. You get it after the visit. If the visit does not happen, they get it back.', style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final f in const [100, 150, 200]) ...[
                      Expanded(
                        child: _feeChip(f),
                      ),
                      if (f != 200) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Tk2Appear(
            index: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading))),
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
                            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.primaryBorder)),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: AppColors.primaryDark),
                                SizedBox(height: 6),
                                Text('Add photos', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                              ],
                            ),
                          ),
                        ),
                      for (var i = 0; i < photos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Stack(
                            children: [
                              SizedBox(width: 104, child: Tk2Photo(listing: l.copyWith(photos: photos), index: i, height: 104, radius: 18)),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() => photos = [...photos]..removeAt(i)),
                                  child: const CircleAvatar(radius: 13, backgroundColor: Color(0xCC172231), child: Icon(Icons.close, size: 15, color: Colors.white)),
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
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: PrimaryButton(label: widget.isNew ? 'Save property' : 'Save', loading: saving, onPressed: saving ? null : _save),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
  );

  Widget _moneyField(TextEditingController c, String label, {bool autofocus = false}) => TextField(
    controller: c,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
    onChanged: (_) => setState(() => error = null),
    decoration: InputDecoration(labelText: label, prefixText: '₹ '),
  );

  Widget _feeChip(int f) {
    final on = fee == f;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        color: on ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.primary : AppColors.border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => fee = f),
        child: Center(
          child: Text(Tk2Store.money(f), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.heading)),
        ),
      ),
    );
  }

  Widget _row({required IconData icon, required String title, required String value, required VoidCallback onTap}) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, color: AppColors.heading))),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
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
    body: const Center(child: Text('This property is not here any more.', style: TextStyle(fontSize: 16, color: AppColors.muted))),
  );
}

/// One property, full view for the broker.
class Tk2PropertyDetail extends StatefulWidget {
  const Tk2PropertyDetail({required this.store, required this.id, super.key});
  final Tk2Store store;
  final String id;

  @override
  State<Tk2PropertyDetail> createState() => _Tk2PropertyDetailState();
}

class _Tk2PropertyDetailState extends State<Tk2PropertyDetail> {
  int page = 0;

  Future<void> _remove(Tk2Listing l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove this property?'),
        content: Text('${l.name} will be removed from your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.removeListing(l.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final l = store.listing(widget.id);
      if (l == null) return const Tk2Missing();
      final p = l.property;
      final visits = store.visitsFor(l.id);
      final photoCount = l.photos.isEmpty ? 1 : l.photos.length;
      final things = [for (final e in p.inventory.entries) if (e.value > 0) '${e.value} ${e.key}${e.value == 1 ? '' : 's'}'];
      final facts = <(IconData, String, String)>[
        (Icons.bed_outlined, 'Rooms', p.rooms),
        (Icons.chair_outlined, 'Furnishing', l.furnishingText),
        if (p.sizeSqFt != null) (Icons.square_foot, 'Size', '${p.sizeSqFt!.toStringAsFixed(0)} sft'),
        if (p.floor > 0) (Icons.layers_outlined, 'Floor', p.totalFloors > 0 ? '${p.floor} of ${p.totalFloors}' : '${p.floor}'),
        if ((p.facing ?? '').isNotEmpty) (Icons.explore_outlined, 'Facing', p.facing!),
        if (p.carParking + p.bikeParking > 0) (Icons.local_parking, 'Parking', [if (p.carParking > 0) '${p.carParking} car', if (p.bikeParking > 0) '${p.bikeParking} bike'].join(' · ')),
        (Icons.event_outlined, 'Available', l.availableFrom.isEmpty ? 'Now' : tk2Date(l.availableFrom)),
        (Icons.people_outline, 'For', l.tenants == 'Anyone' ? 'Family or bachelors' : l.tenants),
        (Icons.pets_outlined, 'Pets', l.pets ? 'Allowed' : 'Not allowed'),
      ];
      return Scaffold(
        backgroundColor: Colors.white,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              leading: Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(backgroundColor: Colors.white, child: BackButton(color: AppColors.heading, onPressed: () => context.canPop() ? context.pop() : context.go('/home'))),
              ),
              actions: [
                if (!l.sample)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: AppColors.heading),
                        onSelected: (v) => switch (v) {
                          'facts' => context.push('/edit/${l.id}'),
                          'rent' => context.push('/listing/${l.id}'),
                          _ => _remove(l),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rent', child: Text('Edit rent and photos')),
                          PopupMenuItem(value: 'facts', child: Text('Edit house details')),
                          PopupMenuItem(value: 'remove', child: Text('Remove property', style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'photo-${l.id}',
                      child: PageView.builder(
                        itemCount: photoCount,
                        onPageChanged: (i) => setState(() => page = i),
                        itemBuilder: (context, i) => Tk2Photo(listing: l, index: i, height: 340, radius: 0),
                      ),
                    ),
                    if (photoCount > 1)
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < photoCount; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == page ? 18 : 7,
                                height: 7,
                                decoration: BoxDecoration(color: i == page ? Colors.white : Colors.white70, borderRadius: BorderRadius.circular(4)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              sliver: SliverList.list(
                children: [
                  if (l.sample) const Tk2Appear(child: Align(alignment: Alignment.centerLeft, child: Tk2Pill('Example property', kind: 'info'))),
                  if (l.sample) const SizedBox(height: 10),
                  Tk2Appear(child: Tk2Title(l.name, subtitle: p.address.trim().isEmpty || p.address.trim() == l.name ? null : p.address)),
                  const SizedBox(height: 16),
                  Tk2Appear(
                    index: 1,
                    child: Row(
                      children: [
                        _money(l.hasRent ? Tk2Store.money(l.rent) : '—', l.maintenanceIncluded || l.maintenance == 0 ? 'Rent incl. maint.' : '+ ${Tk2Store.money(l.maintenance)} maint.'),
                        const SizedBox(width: 10),
                        _money(l.deposit > 0 ? Tk2Store.money(l.deposit) : '—', 'Deposit'),
                        const SizedBox(width: 10),
                        _money(Tk2Store.money(l.visitFee), 'Visit fee'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Tk2Appear(
                    index: 2,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [for (final f in facts) _fact(f.$1, f.$2, f.$3)],
                    ),
                  ),
                  if (things.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('What is in the house', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final t in things) Tk2Pill(t)]),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(child: Text('Visits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading))),
                      if (visits.isNotEmpty) Text('${visits.length}', style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (visits.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                      child: Text(
                        l.sample ? 'Try it: open Customer view and book a visit as a customer.' : 'No visits yet. Share this property and customers can book.',
                        style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
                      ),
                    )
                  else
                    for (final v in visits) Padding(padding: const EdgeInsets.only(bottom: 10), child: Tk2VisitRow(visit: v, store: store)),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/customer/${l.id}'),
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      label: const Text('Customer view'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.border),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => showTk2Share(context, store, l),
                      icon: tk2WhatsAppLogo(size: 20),
                      label: const Text('Share'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _money(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.heading)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ],
      ),
    ),
  );

  Widget _fact(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryDark),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
          ],
        ),
      ],
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
      VisitStatus.noShow => ('Did not come · refunded', 'mute'),
      _ => ('${Tk2Store.money(v.fee)} held', 'wait'),
    };
    final property = showProperty ? store.listing(v.listingId)?.name : null;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
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
                    Text('${at.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: v.upcoming ? AppColors.primaryDark : AppColors.muted)),
                    Text(const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][at.month - 1], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
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
            const Text('Share this property', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
            const SizedBox(height: 4),
            const Text('Customers open the link, see the house and book a visit.', style: TextStyle(fontSize: 15, color: AppColors.muted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE7F8EF), borderRadius: BorderRadius.circular(16)),
              child: Text(text, style: const TextStyle(fontSize: 14.5, height: 21 / 14.5, color: AppColors.body)),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('WhatsApp did not open. Message copied, paste it anywhere.')));
                    }
                  }
                },
                icon: tk2WhatsAppLogo(size: 22),
                label: const Text('Share on WhatsApp'),
                style: FilledButton.styleFrom(backgroundColor: tk2Green, shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
                style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
