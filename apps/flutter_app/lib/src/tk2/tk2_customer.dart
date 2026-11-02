import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_store.dart';
import 'tk2_widgets.dart';

// What the customer sees when they open the shared link. In this build it
// is a preview inside the app; the same screens become the web page later.

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: AppColors.heading,
    child: const Row(
      children: [
        Icon(Icons.visibility_outlined, size: 16, color: Colors.white),
        SizedBox(width: 8),
        Expanded(child: Text('Customer view · what your customer sees', style: TextStyle(fontSize: 13.5, color: Colors.white))),
      ],
    ),
  );
}

class Tk2CustomerPage extends StatelessWidget {
  const Tk2CustomerPage({required this.store, required this.id, super.key});
  final Tk2Store store;
  final String id;

  @override
  Widget build(BuildContext context) {
    final l = store.listing(id);
    if (l == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This property is no longer listed.')));
    final p = l.property;
    final facts = [
      p.rooms,
      l.furnishingText,
      if (p.sizeSqFt != null) '${p.sizeSqFt!.toStringAsFixed(0)} sft',
      if (p.floor > 0) 'Floor ${p.floor}',
      if ((p.facing ?? '').isNotEmpty) '${p.facing} facing',
    ];
    final things = [for (final e in p.inventory.entries) if (e.value > 0) '${e.value} ${e.key}${e.value == 1 ? '' : 's'}'];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('TrustKeeper', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        centerTitle: true,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(34), child: _PreviewBanner()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Tk2Appear(child: _Gallery(listing: l)),
          const SizedBox(height: 18),
          Tk2Appear(index: 1, child: Tk2Title(l.publicTitle, subtitle: l.area.isEmpty ? null : l.area)),
          const SizedBox(height: 14),
          Tk2Appear(
            index: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l.hasRent ? Tk2Store.money(l.rent) : 'Ask for rent', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.heading)),
                if (l.hasRent) const Padding(padding: EdgeInsets.only(left: 4, bottom: 3), child: Text('/ month', style: TextStyle(fontSize: 15, color: AppColors.muted))),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      if (l.maintenanceIncluded || l.maintenance == 0) 'Incl. maintenance' else '+ ${Tk2Store.money(l.maintenance)} maint.',
                      if (l.deposit > 0) 'Deposit ${Tk2Store.money(l.deposit)}',
                      if (l.brokerage > 0) 'Brokerage ${Tk2Store.money(l.brokerage)}',
                    ].join('\n'),
                    textAlign: TextAlign.right,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Tk2Appear(index: 3, child: Wrap(spacing: 6, runSpacing: 6, children: [for (final f in facts) Tk2Pill(f), Tk2Pill(l.availableFrom.isEmpty ? 'Available now' : 'From ${tk2Date(l.availableFrom)}', kind: 'ok'), Tk2Pill(l.tenants == 'Anyone' ? 'Family or bachelors' : '${l.tenants} only'), Tk2Pill(l.pets ? 'Pets OK' : 'No pets')])),
          if (things.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text('In the house', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
            const SizedBox(height: 8),
            Text(things.join(' · '), style: const TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.body)),
          ],
          const SizedBox(height: 22),
          Tk2Appear(
            index: 4,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(18)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined, color: AppColors.primaryDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.visitFee == 0 ? 'Booking a visit is free. Pick a time and the broker will call you.' : 'Book a visit for ${Tk2Store.money(l.visitFee)}. TrustKeeper keeps it safe and gives it to the broker only after your visit. If the visit does not happen, you get it back.',
                      style: const TextStyle(fontSize: 15, height: 21 / 15, color: AppColors.primaryDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (store.brokerName.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: AppColors.surfaceMuted, child: Text(tk2Initials(store.brokerName), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.brokerName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
                      const Text('Broker · shows you the house', style: TextStyle(fontSize: 13.5, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryButton(label: 'Book a visit · ${l.feeText}', onPressed: () => context.push('/customer/${l.id}/book')),
        ),
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.listing});
  final Tk2Listing listing;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final count = widget.listing.photos.isEmpty ? 1 : widget.listing.photos.length;
    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: count,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (context, i) => Tk2Photo(listing: widget.listing, index: i, height: 240, radius: 22),
          ),
          if (count > 1) Positioned(right: 12, bottom: 12, child: Tk2Pill('${page + 1} / $count', kind: 'dark')),
        ],
      ),
    );
  }
}

/// Pick a day and time, give name and phone, pay the visit fee.
class Tk2BookVisit extends StatefulWidget {
  const Tk2BookVisit({required this.store, required this.id, super.key});
  final Tk2Store store;
  final String id;

  @override
  State<Tk2BookVisit> createState() => _Tk2BookVisitState();
}

class _Tk2BookVisitState extends State<Tk2BookVisit> {
  final name = TextEditingController();
  final phone = TextEditingController();
  late final List<DateTime> days = [for (var i = 0; i < 7; i++) DateUtils.dateOnly(DateTime.now()).add(Duration(days: i))];
  static const slots = [10, 11, 12, 14, 15, 16, 17, 18, 19];
  DateTime? day;
  int? hour;
  String? error;
  bool paying = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  bool _slotGone(DateTime d, int h) => DateUtils.isSameDay(d, DateTime.now()) && DateTime.now().hour >= h - 1;

  Future<void> _pay(Tk2Listing l) async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (day == null || hour == null) return setState(() => error = 'Pick a day and time');
    if (name.text.trim().length < 2) return setState(() => error = 'Type your name');
    if (digits.length != 10) return setState(() => error = 'Type your 10 digit phone number');
    FocusScope.of(context).unfocus();
    final paid = l.visitFee == 0 ? true : await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Pay visit fee', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 16),
              _line('Visit', '${tk2Day(day!)}, ${tk2Time(DateTime(2000, 1, 1, hour!))}'),
              _line('Property', l.publicTitle),
              _line('Fee', Tk2Store.money(l.visitFee), bold: true),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(14)),
                child: const Text('Test payment. No money moves in this build.', style: TextStyle(fontSize: 14, color: AppColors.warning)),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Pay ${Tk2Store.money(l.visitFee)}', onPressed: () => Navigator.pop(sheet, true)),
            ],
          ),
        ),
      ),
    );
    if (paid != true || !mounted) return;
    setState(() => paying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final visit = await widget.store.bookVisit(listingId: l.id, name: name.text, phone: '+91 $digits', at: day!.add(Duration(hours: hour!)));
    if (!mounted) return;
    context.pushReplacement('/booked/${visit.id}');
  }

  Widget _line(String a, String b, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(a, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(width: 16),
        Expanded(child: Text(b, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: bold ? 18 : 15, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: AppColors.heading))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = widget.store.listing(widget.id);
    if (l == null) return Scaffold(appBar: AppBar());
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(34), child: _PreviewBanner()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Tk2Appear(child: Tk2Title('Book a visit', subtitle: l.publicTitle)),
          const SizedBox(height: 24),
          const Text('Day', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = days[i];
                final on = day != null && DateUtils.isSameDay(day, d);
                final allGone = slots.every((h) => _slotGone(d, h));
                return Tk2Appear(
                  index: i,
                  child: _chip(
                    on: on,
                    disabled: allGone,
                    width: 68,
                    onTap: () => setState(() {
                      day = d;
                      if (hour != null && _slotGone(d, hour!)) hour = null;
                      error = null;
                    }),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(i == 0 ? 'Today' : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1], style: TextStyle(fontSize: 13, color: on ? Colors.white : AppColors.muted)),
                        const SizedBox(height: 2),
                        Text('${d.day}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.heading)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: day == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 22),
                      const Text('Time', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final h in slots)
                            _chip(
                              on: hour == h,
                              disabled: _slotGone(day!, h),
                              width: 96,
                              height: 46,
                              onTap: () => setState(() {
                                hour = h;
                                error = null;
                              }),
                              child: Center(child: Text(tk2Time(DateTime(2000, 1, 1, h)), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: hour == h ? Colors.white : AppColors.heading))),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() => error = null),
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onChanged: (_) => setState(() => error = null),
            decoration: const InputDecoration(labelText: 'Your phone', prefixText: '+91 ', helperText: 'The broker calls you on this number.'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 15)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: PrimaryButton(label: l.visitFee == 0 ? 'Book visit' : 'Pay ${Tk2Store.money(l.visitFee)} and book', loading: paying, onPressed: paying ? null : () => _pay(l)),
        ),
      ),
    );
  }

  Widget _chip({required bool on, required bool disabled, required VoidCallback onTap, required Widget child, double width = 68, double height = 76}) => Opacity(
    opacity: disabled ? 0.35 : 1,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: on ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.primary : AppColors.border, width: 1.5),
      ),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: disabled ? null : onTap, child: child),
    ),
  );
}

/// Booking done: the visit code and what happens to the fee.
class Tk2Booked extends StatelessWidget {
  const Tk2Booked({required this.store, required this.visitId, super.key});
  final Tk2Store store;
  final String visitId;

  @override
  Widget build(BuildContext context) {
    final v = store.visits.where((v) => v.id == visitId).firstOrNull;
    if (v == null) return Scaffold(appBar: AppBar());
    final l = store.listing(v.listingId);
    final at = DateTime.fromMillisecondsSinceEpoch(v.at);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const _PreviewBanner(),
            const SizedBox(height: 40),
            const Center(child: Tk2SuccessTick()),
            const SizedBox(height: 24),
            const Tk2Appear(child: Text('Visit booked!', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.heading))),
            const SizedBox(height: 6),
            Tk2Appear(
              index: 1,
              child: Text('${l?.publicTitle ?? 'Property'}\n${tk2Day(at)}, ${tk2Time(at)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16.5, height: 24 / 16.5, color: AppColors.muted)),
            ),
            const SizedBox(height: 28),
            Tk2Appear(
              index: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Text('Your visit code', style: TextStyle(fontSize: 15, color: AppColors.primaryDark)),
                    const SizedBox(height: 6),
                    Text(v.code.split('').join(' '), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 4, color: AppColors.primaryDark)),
                    const SizedBox(height: 6),
                    const Text('Tell this to the broker after you see the house.', style: TextStyle(fontSize: 14, color: AppColors.primaryDark)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Tk2Appear(
              index: 3,
              child: v.fee == 0
                  ? _step(Icons.call_outlined, 'The broker will call you before the visit.')
                  : Column(
                children: [
                  _step(Icons.lock_outline, '${Tk2Store.money(v.fee)} is kept safe with TrustKeeper.'),
                  _step(Icons.handshake_outlined, 'After the visit, the broker gets it.'),
                  _step(Icons.replay, 'If the visit does not happen, you get it back.'),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: PrimaryButton(label: 'Done', onPressed: () => context.go('/home')),
        ),
      ),
    );
  }

  Widget _step(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.success),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5, color: AppColors.body))),
      ],
    ),
  );
}
