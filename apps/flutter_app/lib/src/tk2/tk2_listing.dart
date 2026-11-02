import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_designs.dart';
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
    if (society.text.trim().isEmpty && locality.text.trim().isEmpty) {
      setState(() => error = 'Type the society or the area');
      return;
    }
    if (_num(rent) <= 0) {
      setState(() => error = 'Type the monthly rent');
      return;
    }
    if (_num(fee) > Tk2Listing.maxVisitFee) {
      setState(() => feeError = 'Visit fee can be up to ₹${Tk2Listing.maxVisitFee}');
      return;
    }
    setState(() => saving = true);
    await widget.store.saveListing(l.copyWith(rent: _num(rent), deposit: _num(deposit), availableFrom: availableFrom, photos: photos, visitFee: _num(fee), society: society.text.trim(), locality: locality.text.trim(), door: door.text.trim(), ownerName: ownerName.text.trim(), ownerPhone: ownerPhone.text.trim(), keys: keys, note: note.text.trim(), maintenance: included ? 0 : _num(maintenance), maintenanceIncluded: included, tenants: tenants, pets: pets));
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
          const SizedBox(height: 24),
          _label('Customers see'),
          _text(society, 'Society / building name', Icons.apartment_outlined),
          const SizedBox(height: 12),
          _text(locality, 'Area, city', Icons.place_outlined),
          const SizedBox(height: 16),
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
                const Text('The customer pays this to book. You get it after the visit. If the visit does not happen, they get it back. Leave 0 for free.', style: TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted)),
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
          const SizedBox(height: 28),
          const Tk2PrivateBanner(),
          const SizedBox(height: 14),
          _text(door, 'Flat / door number', Icons.door_front_door_outlined),
          const SizedBox(height: 12),
          _text(ownerName, 'Owner name', Icons.person_outline),
          const SizedBox(height: 12),
          _text(ownerPhone, 'Owner phone', Icons.call_outlined, phone: true),
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
          _text(note, 'Note for yourself', Icons.sticky_note_2_outlined),
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

  Widget _text(TextEditingController c, String label, IconData icon, {bool phone = false}) => TextField(
    controller: c,
    keyboardType: phone ? TextInputType.phone : TextInputType.text,
    textCapitalization: phone ? TextCapitalization.none : TextCapitalization.words,
    onChanged: (_) => setState(() => error = null),
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );

  Widget _moneyField(TextEditingController c, String label, {bool autofocus = false}) => TextField(
    controller: c,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
    onChanged: (_) => setState(() => error = null),
    decoration: InputDecoration(labelText: label, prefixText: '₹ '),
  );

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
