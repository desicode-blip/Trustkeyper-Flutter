import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/broker/presentation/approved_broker_home.dart';
import 'tk2_listing.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

// Four ways to show a property (card on home + the page it opens), one under
// the other on home so Aman can pick. A: Classic · B: Wide photo · C: Price
// first · D: Ticket.

const tk2Designs = ['e', 'a', 'b', 'c', 'd'];
const tk2DesignNames = {
  'a': 'A · Classic row',
  'b': 'B · Wide photo',
  'c': 'C · Price first',
  'd': 'D · Ticket',
  'e': 'E · Ticket, refined',
};

final _shadow = [BoxShadow(color: AppColors.heading.withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8))];

/// Icon facts customers may see (no door number, no owner details).
List<(IconData, String)> tk2Facts(Tk2Listing l, {bool long = false}) {
  final p = l.property;
  return [
    if (p.sizeSqFt != null) (Icons.square_foot_outlined, '${p.sizeSqFt!.toStringAsFixed(0)} sft'),
    (Icons.chair_outlined, l.furnishingText),
    (Icons.group_outlined, l.tenants == 'Anyone' ? 'Family or bachelors' : '${l.tenants} only'),
    (Icons.pets_outlined, l.pets ? 'Pets OK' : 'No pets'),
    (Icons.event_available_outlined, l.availableFrom.isEmpty ? 'Available now' : 'From ${tk2Date(l.availableFrom)}'),
    if (long && p.totalFloors > 0) (Icons.layers_outlined, 'Floor ${p.floor} of ${p.totalFloors}'),
    if (long && (p.facing ?? '').isNotEmpty) (Icons.explore_outlined, '${p.facing} facing'),
    if (long && p.carParking + p.bikeParking > 0)
      (Icons.local_parking_outlined, [if (p.carParking > 0) '${p.carParking} car', if (p.bikeParking > 0) '${p.bikeParking} bike'].join(' · ')),
  ];
}

Widget _iconText(IconData icon, String text, {Color color = AppColors.muted, double size = 13.5}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: size + 3, color: color),
    const SizedBox(width: 4),
    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: color))),
  ],
);

Widget _area(Tk2Listing l, {double size = 13.5}) =>
    l.area.isEmpty ? const SizedBox.shrink() : _iconText(Icons.place_outlined, l.area, size: size);

Widget _tappable({required VoidCallback onTap, required Widget child, double radius = 20, Color color = Colors.white}) => DecoratedBox(
  decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: _shadow),
  child: Material(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: child),
  ),
);

/// Home card in the chosen design.
class Tk2DesignCard extends StatelessWidget {
  const Tk2DesignCard({required this.design, required this.listing, required this.onOpen, this.visits = 0, super.key});
  final String design;
  final Tk2Listing listing;
  final VoidCallback onOpen;
  final int visits;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final title = Text(l.publicTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, height: 21 / 16, fontWeight: FontWeight.w600, color: AppColors.heading));
    final rent = Text(l.rentLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark));
    final tags = [
      if (l.sample) const Flexible(child: Tk2Pill('Example', kind: 'info')),
      if (visits > 0) Flexible(child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'}', kind: 'ok')),
    ];
    final facts = tk2Facts(l);
    switch (design) {
      case 'b':
        return _tappable(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Tk2Photo(listing: l, height: 130, radius: 0),
                  Positioned(left: 12, bottom: 12, child: Tk2Pill(Tk2Store.money(l.rent), kind: 'dark')),
                  Positioned(right: 12, top: 12, child: Row(children: [if (l.sample) const Tk2Pill('Example', kind: 'info'), if (visits > 0) Padding(padding: const EdgeInsets.only(left: 6), child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'}', kind: 'ok'))])),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 2),
                    _area(l),
                    const SizedBox(height: 10),
                    Wrap(spacing: 14, runSpacing: 6, children: [for (final f in facts.take(4)) _iconText(f.$1, f.$2)]),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'c':
        return _tappable(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
                      child: Text(l.property.rooms.replaceAll(' ', '\n'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 14 / 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, _area(l)])),
                    ...tags,
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Tk2Store.money(l.rent), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.heading)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          l.maintenanceIncluded || l.maintenance == 0 ? '/ month · incl. maintenance' : '/ month + ${Tk2Store.money(l.maintenance)} maint.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 10),
                Wrap(spacing: 14, runSpacing: 6, children: [for (final f in facts) _iconText(f.$1, f.$2)]),
              ],
            ),
          ),
        );
      case 'e':
        final left = facts.where((f) => f.$1 != Icons.pets_outlined && f.$1 != Icons.event_available_outlined).toList();
        final right = facts.where((f) => f.$1 == Icons.pets_outlined || f.$1 == Icons.event_available_outlined).toList();
        Widget col(List<(IconData, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final f in items) Padding(padding: const EdgeInsets.only(bottom: 5), child: _iconText(f.$1, f.$2, size: 13))],
        );
        return _tappable(
          onTap: onOpen,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 100,
                  color: AppColors.primarySoft,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(child: Text(l.property.rooms, style: const TextStyle(fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark))),
                      const SizedBox(height: 6),
                      FittedBox(child: Text(Tk2Store.money(l.rent), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark))),
                      Text(l.maintenanceIncluded || l.maintenance == 0 ? 'incl. maint.' : '+ ${Tk2Store.money(l.maintenance)} maint.', style: const TextStyle(fontSize: 11.5, color: AppColors.primaryDark)),
                    ],
                  ),
                ),
                CustomPaint(painter: _DashPainter(), child: const SizedBox(width: 1)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.society.isNotEmpty ? l.society : l.area, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
                        if (l.society.isNotEmpty) _area(l, size: 13),
                        if (visits > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'} booked', kind: 'ok')),
                        const SizedBox(height: 10),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 11, child: col(left)),
                              const VerticalDivider(width: 17, thickness: 1, color: Color(0xFFE9EDF3)),
                              // Right column has room for more facts later.
                              Expanded(flex: 10, child: col(right)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'd':
        return _tappable(
          onTap: onOpen,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 104,
                  color: AppColors.primarySoft,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l.property.rooms, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                      const SizedBox(height: 4),
                      FittedBox(child: Text(Tk2Store.money(l.rent), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark))),
                      Text(l.maintenanceIncluded || l.maintenance == 0 ? 'incl. maint.' : '+ ${Tk2Store.money(l.maintenance)}', style: const TextStyle(fontSize: 12, color: AppColors.primaryDark)),
                    ],
                  ),
                ),
                CustomPaint(painter: _DashPainter(), child: const SizedBox(width: 1)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Expanded(child: Text(l.society.isNotEmpty ? l.society : l.area, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading))), ...tags]),
                        _area(l),
                        const SizedBox(height: 8),
                        for (final f in facts.take(3)) Padding(padding: const EdgeInsets.only(bottom: 3), child: _iconText(f.$1, f.$2)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        return _tappable(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 84, height: 84, child: Tk2Photo(listing: l, height: 84, radius: 14, compact: true)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Expanded(child: title), ...tags]),
                      _area(l),
                      const SizedBox(height: 4),
                      rent,
                      const SizedBox(height: 6),
                      Wrap(spacing: 10, runSpacing: 4, children: [for (final f in facts) _iconText(f.$1, f.$2, size: 12.5)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryBorder
      ..strokeWidth = 1.5;
    for (double y = 6; y < size.height - 6; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Only you can see this" – shown above the broker-only details.
class Tk2PrivateBanner extends StatelessWidget {
  const Tk2PrivateBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(16)),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, color: AppColors.success),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Complete address and details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.success)),
              SizedBox(height: 2),
              Text(
                'Only you can see this. It is never shared with tenants – not in the message, not on the link.',
                style: TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.success),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The broker-only block: full address, owner, keys, note.
class Tk2PrivateDetails extends StatelessWidget {
  const Tk2PrivateDetails({required this.listing, super.key});
  final Tk2Listing listing;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final rows = <(IconData, String, String, String?)>[
      (Icons.home_outlined, 'Full address', l.fullAddress.isEmpty ? 'Not added' : l.fullAddress, null),
      (Icons.person_outline, 'Owner', l.ownerName.isEmpty ? 'Not added' : l.ownerName, null),
      (Icons.call_outlined, 'Owner phone', l.ownerPhone.isEmpty ? 'Not added' : l.ownerPhone, l.ownerPhone.isEmpty ? null : l.ownerPhone),
      (Icons.key_outlined, 'Keys', l.keys.isEmpty ? 'Not added' : l.keys, null),
      if (l.note.isNotEmpty) (Icons.sticky_note_2_outlined, 'Note', l.note, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Tk2PrivateBanner(),
        const SizedBox(height: 8),
        for (final r in rows)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(r.$1, color: AppColors.primaryDark),
            title: Text(r.$2, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            subtitle: Text(r.$3, style: const TextStyle(fontSize: 15.5, height: 21 / 15.5, color: AppColors.heading)),
            trailing: r.$4 == null
                ? null
                : IconButton(
                    tooltip: 'Call owner',
                    onPressed: () => launchUrl(Uri.parse('tel:${r.$4!.replaceAll(' ', '')}')).then((_) {}, onError: (_) {}),
                    icon: const Icon(Icons.call, color: AppColors.primary),
                  ),
          ),
        if (!l.sample)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => context.push('/listing/${l.id}'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit these details')),
          ),
      ],
    );
  }
}

/// The property page in the chosen design.
class Tk2DesignDetail extends StatefulWidget {
  const Tk2DesignDetail({required this.store, required this.id, required this.design, super.key});
  final Tk2Store store;
  final String id;
  final String design;

  @override
  State<Tk2DesignDetail> createState() => _Tk2DesignDetailState();
}

class _Tk2DesignDetailState extends State<Tk2DesignDetail> {
  int tab = 0;

  Future<void> _menu(Tk2Listing l, String v) async {
    if (v == 'facts') {
      context.push('/edit/${l.id}');
    } else if (v == 'rent') {
      context.push('/listing/${l.id}');
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Remove this property?'),
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
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final l = store.listing(widget.id);
      if (l == null) return const Tk2Missing();
      final visits = store.visitsFor(l.id);
      final body = switch (widget.design) {
        'b' => _b(l),
        'c' => _c(l),
        'd' || 'e' => _d(l),
        _ => _a(l),
      };
      return Scaffold(
        backgroundColor: widget.design == 'd' || widget.design == 'e' ? AppColors.surfaceMuted : Colors.white,
        appBar: AppBar(
          backgroundColor: widget.design == 'd' || widget.design == 'e' ? AppColors.surfaceMuted : Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(tk2DesignNames[widget.design] ?? '', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          centerTitle: true,
          actions: [
            if (!l.sample)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: AppColors.heading),
                onSelected: (v) => _menu(l, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rent', child: Text('Edit rent and details')),
                  PopupMenuItem(value: 'facts', child: Text('Edit house details')),
                  PopupMenuItem(value: 'remove', child: Text('Remove property', style: TextStyle(color: AppColors.error))),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            ...body,
            const SizedBox(height: 26),
            _heading('Visits${visits.isEmpty ? '' : ' · ${visits.length}'}'),
            if (visits.isEmpty)
              Text(
                l.sample ? 'Try it: tap Customer view below and book a visit as a customer.' : 'No visits yet. Share this property and customers can book.',
                style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
              )
            else
              for (final v in visits) Padding(padding: const EdgeInsets.only(bottom: 10), child: Tk2VisitRow(visit: v, store: store)),
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
                    child: OutlinedButton(
                      onPressed: () => context.push('/customer/${l.id}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryDark,
                        side: const BorderSide(color: AppColors.border),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Customer view'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: PrimaryButton(label: 'Share', onPressed: () => showTk2Share(context, store, l))),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
  );

  Widget _titleBlock(Tk2Listing l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (l.sample) const Padding(padding: EdgeInsets.only(bottom: 8), child: Tk2Pill('Example property', kind: 'info')),
      Text(l.publicTitle, style: const TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, color: AppColors.heading)),
      const SizedBox(height: 4),
      _area(l, size: 15),
    ],
  );

  Widget _things(Tk2Listing l) {
    final things = [for (final e in l.property.inventory.entries) if (e.value > 0) '${e.value} ${e.key}${e.value == 1 ? '' : 's'}'];
    if (things.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        _heading('In the house'),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final t in things) Tk2Pill(t)]),
      ],
    );
  }

  Widget _photos(Tk2Listing l, {double height = 220, double radius = 20}) {
    final count = l.photos.isEmpty ? 1 : l.photos.length;
    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: PageController(viewportFraction: count > 1 ? 0.92 : 1),
        padEnds: false,
        itemCount: count,
        itemBuilder: (context, i) => Padding(padding: EdgeInsets.only(right: count > 1 ? 8 : 0), child: Tk2Photo(listing: l, index: i, height: height, radius: radius)),
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
            ],
          ),
        ),
      ],
    ),
  );

  List<(IconData, String, String)> _labelled(Tk2Listing l) {
    final p = l.property;
    return [
      (Icons.currency_rupee_outlined, 'Rent', l.rentLine),
      if (l.deposit > 0) (Icons.savings_outlined, 'Deposit', Tk2Store.money(l.deposit)),
      (Icons.confirmation_number_outlined, 'Visit fee', l.feeText),
      if (p.sizeSqFt != null) (Icons.square_foot_outlined, 'Size', '${p.sizeSqFt!.toStringAsFixed(0)} sft'),
      (Icons.chair_outlined, 'Furnishing', l.furnishingText),
      if (p.totalFloors > 0) (Icons.layers_outlined, 'Floor', '${p.floor} of ${p.totalFloors}'),
      if ((p.facing ?? '').isNotEmpty) (Icons.explore_outlined, 'Facing', p.facing!),
      (Icons.group_outlined, 'Who can rent', l.tenants == 'Anyone' ? 'Family or bachelors' : l.tenants),
      (Icons.pets_outlined, 'Pets', l.pets ? 'Allowed' : 'Not allowed'),
      (Icons.event_available_outlined, 'Available', l.availableFrom.isEmpty ? 'Now' : tk2Date(l.availableFrom)),
    ];
  }

  Widget _grid(List<(IconData, String, String)> items) => LayoutBuilder(
    builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final i in items) SizedBox(width: w, child: _tile(i.$1, i.$2, i.$3))]);
    },
  );

  // A · Classic: photo, title, 2-column icon tiles, private block.
  List<Widget> _a(Tk2Listing l) => [
    _photos(l),
    const SizedBox(height: 18),
    _titleBlock(l),
    const SizedBox(height: 18),
    _grid(_labelled(l)),
    _things(l),
    const SizedBox(height: 26),
    Tk2PrivateDetails(listing: l),
  ];

  // B · Two tabs: "Customers see" and "Only you".
  List<Widget> _b(Tk2Listing l) => [
    _photos(l, height: 180),
    const SizedBox(height: 16),
    _titleBlock(l),
    const SizedBox(height: 16),
    SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, icon: Icon(Icons.visibility_outlined), label: Text('Customers see')),
        ButtonSegment(value: 1, icon: Icon(Icons.lock_outline), label: Text('Only you')),
      ],
      selected: {tab},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => tab = s.first),
    ),
    const SizedBox(height: 16),
    if (tab == 0) ...[
      for (final i in _labelled(l))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              Icon(i.$1, size: 20, color: AppColors.primaryDark),
              const SizedBox(width: 12),
              Text(i.$2, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
              const SizedBox(width: 12),
              Expanded(child: Text(i.$3, textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading))),
            ],
          ),
        ),
      _things(l),
    ] else
      Tk2PrivateDetails(listing: l),
  ];

  // C · Price first: big rent card on top, then grouped sections.
  List<Widget> _c(Tk2Listing l) {
    final all = _labelled(l);
    Widget section(String title, List<(IconData, String, String)> items) => Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          for (final i in items) Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: _iconText(i.$1, '${i.$2}: ${i.$3}', color: AppColors.heading, size: 15)),
        ],
      ),
    );
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]), borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.publicTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
            if (l.area.isNotEmpty) Text(l.area, style: const TextStyle(fontSize: 14, color: Color(0xDDFFFFFF))),
            const SizedBox(height: 14),
            Text(Tk2Store.money(l.rent), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(
              l.maintenanceIncluded || l.maintenance == 0 ? 'per month · maintenance included' : 'per month + ${Tk2Store.money(l.maintenance)} maintenance',
              style: const TextStyle(fontSize: 14, color: Color(0xDDFFFFFF)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tk2Pill(l.deposit > 0 ? 'Deposit ${Tk2Store.money(l.deposit)}' : 'No deposit set', kind: 'dark'),
                Tk2Pill('Visit ${l.feeText}', kind: 'dark'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _photos(l, height: 150, radius: 16),
      section('THE HOME', all.where((i) => const ['Size', 'Furnishing', 'Floor', 'Facing'].contains(i.$2)).toList()),
      section('WHO CAN RENT', all.where((i) => const ['Who can rent', 'Pets', 'Available'].contains(i.$2)).toList()),
      _things(l),
      const SizedBox(height: 22),
      Tk2PrivateDetails(listing: l),
    ];
  }

  // D · Ticket: calm grey page, white grouped lists like settings.
  List<Widget> _d(Tk2Listing l) {
    Widget group(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
      child: Column(children: children),
    );
    Widget row(IconData icon, String label, String value, {bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.body)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading))),
        ],
      ),
    );
    final items = _labelled(l);
    return [
      Tk2DesignCard(design: widget.design, listing: l, onOpen: () {}),
      const SizedBox(height: 12),
      SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: l.photos.isEmpty ? 1 : l.photos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 128, child: Tk2Photo(listing: l, index: i, height: 96, radius: 14, compact: true)),
        ),
      ),
      group([for (var i = 0; i < items.length; i++) row(items[i].$1, items[i].$2, items[i].$3, last: i == items.length - 1)]),
      _things(l),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
        child: Tk2PrivateDetails(listing: l),
      ),
    ];
  }
}

/// Home section that shows every design one under the other.
class Tk2DesignShowcase extends StatelessWidget {
  const Tk2DesignShowcase({required this.store, super.key});
  final Tk2Store store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final d in tk2Designs) ...[
        const SizedBox(height: 22),
        Row(
          children: [
            const HomeIcon('house', size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text('Design ${tk2DesignNames[d]}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted))),
          ],
        ),
        const SizedBox(height: 10),
        for (final l in store.shown) ...[
          Tk2DesignCard(
            key: ValueKey('$d-${l.id}'),
            design: d,
            listing: l,
            visits: store.visitsFor(l.id).where((v) => v.upcoming).length,
            onOpen: () => context.push('/p/${l.id}?d=$d'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ],
  );
}
