import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_listing.dart';
import 'tk2_send.dart';
import 'tk2_sort.dart';
import 'tk2_status.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

// Four ways to show a property (card on home + the page it opens), one under
// the other on home so Aman can pick. A: Classic · B: Wide photo · C: Price
// first · D: Ticket.

/// Design B is final for the home cards; E is kept for the customer page ticket.
const tk2Designs = ['e', 'b'];
const tk2DesignNames = {'b': 'B · Wide photo', 'e': 'E · Ticket, refined'};

final _shadow = [BoxShadow(color: AppColors.heading.withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8))];

/// Icon facts customers may see (no door number, no owner details).
List<(IconData, String)> tk2Facts(Tk2Listing l, {bool long = false, bool outlined = false}) {
  final p = l.property;
  // Design E uses one outlined icon family (same stroke); A–D keep their icons.
  IconData ic(IconData classic, IconData line) => outlined ? line : classic;
  return [
    if (p.sizeSqFt != null) (ic(Icons.square_foot, Icons.square_foot_outlined), '${p.sizeSqFt!.toStringAsFixed(0)} sft'),
    (Icons.chair_outlined, l.furnishingText),
    (ic(Icons.people_outline, Icons.group_outlined), l.tenantsLabel),
    (outlined ? Icons.pets_outlined : (l.pets ? Icons.pets : Icons.do_not_disturb_alt), l.pets ? 'Pets OK' : 'No pets'),
    (Icons.event_available_outlined, l.availableFrom.isEmpty ? 'Available now' : 'From ${tk2Date(l.availableFrom)}'),
    if (long && p.totalFloors > 0) (Icons.layers_outlined, 'Floor ${p.floor} of ${p.totalFloors}'),
    if (long && (p.facing ?? '').isNotEmpty) (Icons.explore_outlined, '${p.facing} facing'),
    if (long && p.carParking + p.bikeParking > 0)
      (ic(Icons.local_parking, Icons.local_parking_outlined), [if (p.carParking > 0) '${p.carParking} car', if (p.bikeParking > 0) '${p.bikeParking} bike'].join(' · ')),
  ];
}

/// Address parts with the house / flat / plot numbers taken out.
List<String> _publicParts(Tk2Listing l) {
  final door = RegExp(r'^(flat|house|h\.?\s?no|door|plot|apt|apartment|unit|block|tower|wing|floor|#|no\.?)\b', caseSensitive: false);
  final parts = l.property.address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  // Drop leading bits like "Flat 402", "H.No 5-6-7", "#12", "3rd floor".
  while (parts.isNotEmpty && (door.hasMatch(parts.first) || RegExp(r'\d').hasMatch(parts.first))) {
    parts.removeAt(0);
  }
  return parts;
}

/// The complete address without door numbers – safe to show and share.
String tk2PublicAddress(Tk2Listing l) {
  final parts = _publicParts(l);
  if (l.society.trim().isNotEmpty && !parts.any((p) => p.toLowerCase() == l.society.trim().toLowerCase())) {
    parts.insert(0, l.society.trim());
  }
  if (l.locality.trim().isNotEmpty && !parts.join(', ').toLowerCase().contains(l.locality.split(',').first.trim().toLowerCase())) {
    parts.add(l.locality.trim());
  }
  return parts.join(', ');
}

/// Card heading: society name, else the area – never the broker's own label
/// and never empty.
String tk2CardHeading(Tk2Listing l) {
  if (l.society.trim().isNotEmpty) return l.society.trim();
  if (l.locality.trim().isNotEmpty) return l.locality.split(',').first.trim();
  final parts = _publicParts(l);
  if (parts.length >= 2) return parts[parts.length - 2];
  if (parts.isNotEmpty) return parts.first;
  return '${l.property.rooms} property';
}

Widget _address(Tk2Listing l, {double size = 13}) {
  final a = tk2PublicAddress(l);
  return a.isEmpty ? const SizedBox.shrink() : _iconText(Icons.place_outlined, a, size: size, lines: 2);
}

/// Swipeable card photos with dots. No photos yet → the app's house
/// illustration as a placeholder (3 pages, so the swipe can be felt).
class _SwipePhotos extends StatefulWidget {
  const _SwipePhotos({required this.listing});
  final Tk2Listing listing;

  @override
  State<_SwipePhotos> createState() => _SwipePhotosState();
}

class _SwipePhotosState extends State<_SwipePhotos> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final count = l.sample ? 1 : (l.photos.isEmpty ? 3 : l.photos.length);
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: count,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (context, i) => l.sample
                ? const Tk2ExamplePhoto(height: 150, radius: 0)
                : l.photos.isEmpty
                ? Container(
                    color: const Color(0xFFFFF1E3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SvgPicture.asset('assets/onboarding/welcome-home.svg', fit: BoxFit.contain),
                  )
                : Tk2Photo(listing: l, index: i, height: 150, radius: 0),
          ),
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == page ? AppColors.heading : AppColors.heading.withValues(alpha: 0.25)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Icon in the app's line style. Material has no line paw, so pets uses our own.
Widget tk2Glyph(IconData icon, {required double size, required Color color}) => icon == Icons.pets_outlined
    ? Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SvgPicture.asset('assets/design/tk2-paw.svg', width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
      )
    : Icon(icon, size: size, color: color);

/// Design B first line: "2 BHK  ·  ₹32,000/m" and the maintenance note
/// right after it, smaller and grey. It stays on one line: when it would come
/// closer than 16 px to the Share button, the note gets shorter step by step:
///   (maintenance included) → (maintenance inc.) → (all inclusive)
///   + maintenance → + maint…
/// (On a very narrow screen the note is left out rather than cut off.)
Widget _rentHeading(Tk2Listing l) {
  const strong = TextStyle(fontSize: 16.5, height: 22 / 16.5, fontWeight: FontWeight.w700, color: AppColors.heading);
  const per = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.body);
  const light = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: AppColors.muted);
  final extra = !(l.maintenanceIncluded || l.maintenance == 0);
  final notes = !l.hasRent
      ? const ['']
      : extra
      ? const [' + maintenance', ' + maint…']
      : const [' (maintenance included)', ' (maintenance inc.)', ' (all inclusive)'];
  TextSpan span(TextStyle base, String note) => TextSpan(
    style: base.merge(strong),
    children: [
      TextSpan(text: l.property.rooms),
      const TextSpan(text: '  ·  ', style: TextStyle(color: AppColors.muted)),
      if (!l.hasRent)
        const TextSpan(text: 'Add rent')
      else ...[
        TextSpan(text: Tk2Store.money(l.rent)),
        const TextSpan(text: '/m', style: per),
        TextSpan(text: note, style: light),
      ],
    ],
  );
  return LayoutBuilder(
    builder: (context, box) {
      // Measure with the same font the Text will use.
      final base = DefaultTextStyle.of(context).style;
      final scaler = MediaQuery.textScalerOf(context);
      // Very narrow screens: the rent alone rather than a cut-off note.
      final note = [...notes, ''].firstWhere((n) {
        final tp = TextPainter(text: span(base, n), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
        final fits = tp.width <= box.maxWidth;
        tp.dispose();
        return fits;
      }, orElse: () => '');
      return Text.rich(span(base, note), maxLines: 1, overflow: TextOverflow.ellipsis);
    },
  );
}

Widget _iconText(IconData icon, String text, {Color color = AppColors.muted, double size = 13.5, int lines = 1}) => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
  children: [
    tk2Glyph(icon, size: size + 3, color: color),
    const SizedBox(width: 4),
    Flexible(
      child: Text(
        text,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, color: color),
      ),
    ),
  ],
);

Widget _area(Tk2Listing l, {double size = 13.5}) => l.area.isEmpty ? const SizedBox.shrink() : _iconText(Icons.place_outlined, l.area, size: size);

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
  const Tk2DesignCard({required this.design, required this.listing, required this.onOpen, this.visits = 0, this.onSend, super.key});
  final String design;
  final Tk2Listing listing;
  final VoidCallback onOpen;
  final int visits;

  /// Design B: "Send" in the bottom-right corner (send to a tenant).
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    switch (design) {
      case 'b':
        return _tappable(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _SwipePhotos(listing: l),
                  if (visits > 0) Positioned(right: 12, top: 12, child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'}', kind: 'ok')),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _rentHeading(l),
                              const SizedBox(height: 3),
                              _address(l),
                            ],
                          ),
                        ),
                        // Secondary "Share": quiet outline, right of the heading.
                        if (onSend != null) ...[
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            key: ValueKey('send-${l.id}'),
                            onPressed: onSend,
                            icon: const Icon(Icons.share_outlined, size: 16),
                            label: const Text('Share'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryDark,
                              side: const BorderSide(color: AppColors.border),
                              shape: const StadiumBorder(),
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Facts in two columns, same as Design E.
                    Builder(
                      builder: (context) {
                        final factsB = tk2Facts(l, outlined: true);
                        Widget col(List<(IconData, String)> items) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [for (final f in items) Padding(padding: const EdgeInsets.only(bottom: 5), child: _iconText(f.$1, f.$2, size: 13, lines: 2))],
                        );
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 11, child: col(factsB.sublist(0, factsB.length - 2))),
                              const VerticalDivider(width: 17, thickness: 1, color: Color(0xFFE9EDF3)),
                              Expanded(flex: 10, child: col(factsB.sublist(factsB.length - 2))),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      default: // 'e' · Design E ticket (customer page; kept for reference)
        final factsE = tk2Facts(l, outlined: true);
        // Left: size, furnishing, who can rent. Right: pets, available from (room for more).
        final left = factsE.sublist(0, factsE.length - 2);
        final right = factsE.sublist(factsE.length - 2);
        Widget col(List<(IconData, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final f in items) Padding(padding: const EdgeInsets.only(bottom: 5), child: _iconText(f.$1, f.$2, size: 13, lines: 2))],
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
                      FittedBox(
                        child: Text(
                          l.property.rooms,
                          style: const TextStyle(fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        child: Text(
                          Tk2Store.money(l.rent),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Centred under the rent; the amount and "maint." on their own lines.
                      Text(
                        l.maintenanceIncluded || l.maintenance == 0 ? 'incl. maint.' : '+ ${Tk2Store.money(l.maintenance)}\nmaint.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, height: 15 / 11.5, color: AppColors.primaryDark),
                      ),
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
                        Text(
                          tk2CardHeading(l),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
                        ),
                        const SizedBox(height: 2),
                        _address(l),
                        if (visits > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Tk2Pill('$visits visit${visits == 1 ? '' : 's'} booked', kind: 'ok'),
                          ),
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
              Text(
                'Complete address and details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.success),
              ),
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

/// Public facts of a listing (rent, brokerage, fee, size …). Safe for customers.
List<(IconData, String, String)> tk2FactRows(Tk2Listing l, {bool line = true}) {
  final p = l.property;
  final o = line;
  IconData ic(IconData classic, IconData line) => o ? line : classic;
  return [
    (ic(Icons.currency_rupee, Icons.currency_rupee_outlined), 'Rent', l.rentLine),
    if (l.deposit > 0) (Icons.savings_outlined, 'Deposit', Tk2Store.money(l.deposit)),
    (Icons.handshake_outlined, 'Brokerage', l.brokerageText),
    (Icons.confirmation_number_outlined, 'Visit fee', l.feeText),
    if (p.sizeSqFt != null) (ic(Icons.square_foot, Icons.square_foot_outlined), 'Size', '${p.sizeSqFt!.toStringAsFixed(0)} sft'),
    (Icons.chair_outlined, 'Furnishing', l.furnishingText),
    if (p.totalFloors > 0) (Icons.layers_outlined, 'Floor', '${p.floor} of ${p.totalFloors}'),
    if ((p.facing ?? '').isNotEmpty) (Icons.explore_outlined, 'Facing', p.facing!),
    (ic(Icons.people_outline, Icons.group_outlined), 'Who can rent', l.tenantsLabel),
    (ic(Icons.pets, Icons.pets_outlined), 'Pets', l.pets ? 'Allowed' : 'Not allowed'),
    (Icons.event_available_outlined, 'Available', l.availableFrom.isEmpty ? 'Now' : tk2Date(l.availableFrom)),
  ];
}

/// White grouped list of facts (the broker's Design E page). Used on the customer page too.
class Tk2FactsGroup extends StatelessWidget {
  const Tk2FactsGroup({required this.items, super.key});
  final List<(IconData, String, String)> items;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              border: i == items.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: tk2Glyph(items[i].$1, size: 18, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 12),
                Text(items[i].$2, style: const TextStyle(fontSize: 15, color: AppColors.body)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    items[i].$3,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading),
                  ),
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
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(r.$1, size: 18, color: AppColors.primaryDark),
            ),
            title: Text(r.$2, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            subtitle: Text(
              r.$3,
              style: const TextStyle(fontSize: 15.5, height: 21 / 15.5, color: AppColors.heading),
            ),
            trailing: r.$4 == null
                ? null
                : IconButton(
                    tooltip: 'Call owner',
                    onPressed: () => launchUrl(Uri.parse('tel:${r.$4!.replaceAll(' ', '')}')).then((_) {}, onError: (_) {}),
                    icon: const Icon(Icons.call_outlined, color: AppColors.primary),
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
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Remove'),
            ),
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
        _ => _d(l), // Design E page, kept for reference (not linked from Home)
      };
      return Scaffold(
        backgroundColor: widget.design == 'd' || widget.design == 'e' ? AppColors.surfaceMuted : Colors.white,
        appBar: AppBar(
          backgroundColor: widget.design == 'd' || widget.design == 'e' ? AppColors.surfaceMuted : Colors.white,
          surfaceTintColor: Colors.transparent,
          actions: [
            // Active / Not active lives in the header; turning off asks why.
            if (!l.sample) Tk2ActiveToggle(store: store, listing: l),
            if (!l.sample)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: AppColors.heading),
                onSelected: (v) => _menu(l, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rent', child: Text('Edit rent and details')),
                  PopupMenuItem(value: 'facts', child: Text('Edit house details')),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove property', style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (store.inactive(l.id) case final off?) ...[Tk2InactiveBanner(info: off), const SizedBox(height: 12)],
            ...body,
            const SizedBox(height: 26),
            _heading('Visits${visits.isEmpty ? '' : ' · ${visits.length}'}'),
            if (visits.isEmpty)
              Text(
                l.sample ? 'Try it: tap Customer view below and book a visit as a customer.' : 'No visits yet. Share this property and customers can book.',
                style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.muted),
              )
            else
              for (final v in visits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Tk2VisitRow(visit: v, store: store),
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
                // Turned off: no sharing until it is active again.
                if (store.isActive(l.id)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(label: 'Share', onPressed: () => showTk2Share(context, store, l)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
  );

  Widget _titleBlock(Tk2Listing l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (l.sample)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Tk2Pill('Example property', kind: 'info'),
        ),
      Text(
        l.publicTitle,
        style: const TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, color: AppColors.heading),
      ),
      const SizedBox(height: 4),
      _area(l, size: 15),
    ],
  );

  Widget _things(Tk2Listing l) {
    final things = [
      for (final e in l.property.inventory.entries)
        if (e.value > 0) '${e.value} ${e.key}${e.value == 1 ? '' : 's'}',
    ];
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
        itemBuilder: (context, i) => Padding(
          padding: EdgeInsets.only(right: count > 1 ? 8 : 0),
          child: Tk2Photo(listing: l, index: i, height: height, radius: radius),
        ),
      ),
    );
  }

  List<(IconData, String, String)> _labelled(Tk2Listing l) => tk2FactRows(l, line: widget.design == 'e');

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
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              tk2Glyph(i.$1, size: 20, color: AppColors.primaryDark),
              const SizedBox(width: 12),
              Text(i.$2, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  i.$3,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading),
                ),
              ),
            ],
          ),
        ),
      _things(l),
    ] else
      Tk2PrivateDetails(listing: l),
  ];

  List<Widget> _d(Tk2Listing l) {
    Widget group(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
      child: Column(children: children),
    );
    Widget row(IconData icon, String label, String value, {bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: tk2Glyph(icon, size: 18, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.body)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading),
            ),
          ),
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
          itemBuilder: (_, i) => SizedBox(
            width: 128,
            child: Tk2Photo(listing: l, index: i, height: 96, radius: 14, compact: true),
          ),
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

/// Home list: every property as a Design B card, with a simple sort and
/// filter. Active ones first; turned-off ones below, greyed, without Share.
class Tk2PropertyList extends StatefulWidget {
  const Tk2PropertyList({required this.store, super.key});
  final Tk2Store store;

  @override
  State<Tk2PropertyList> createState() => _Tk2PropertyListState();
}

class _Tk2PropertyListState extends State<Tk2PropertyList> {
  var filter = const Tk2ListFilter();

  Tk2Store get store => widget.store;

  Widget _card(BuildContext context, Tk2Listing l, {required bool active}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Opacity(
      // The example is greyed out so it never looks like a real listing.
      opacity: active && !l.sample ? 1 : 0.6,
      child: Tk2DesignCard(
        key: ValueKey('b-${l.id}'),
        design: 'b',
        listing: l,
        visits: store.visitsFor(l.id).where((v) => v.upcoming).length,
        onOpen: () => context.push('/p/${l.id}?d=b'),
        onSend: active ? () => showTk2Send(context, store, l) : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final list = filter.apply(store.shown, store);
    final active = [for (final l in list) if (store.isActive(l.id)) l];
    final off = [for (final l in list) if (!store.isActive(l.id)) l];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // Sort and filter once there is more than one property.
        if (store.listings.length > 1) ...[
          Tk2SortFilterBar(value: filter, onChanged: (f) => setState(() => filter = f)),
          const SizedBox(height: 12),
        ],
        for (final l in active) _card(context, l, active: true),
        if (off.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Not active · ${off.length}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          for (final l in off) _card(context, l, active: false),
        ],
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Text('No properties match', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
                TextButton(onPressed: () => setState(() => filter = Tk2ListFilter(sort: filter.sort)), child: const Text('Clear filters')),
              ],
            ),
          ),
      ],
    );
  }
}
