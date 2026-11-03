import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import 'tk2_store.dart';

/// Simple sort and filter for "Your properties".

/// BHK as a number: "1 RK" = 0.5, "2.5 BHK" = 2.5, "4+ BHK" = 4.5.
double tk2Bhk(String rooms) {
  final r = rooms.toUpperCase();
  if (r.contains('RK')) return 0.5;
  final n = double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(r)?.group(0) ?? '') ?? 0;
  return r.contains('+') ? n + 0.5 : n;
}

/// Filter chips for BHK. 4.5 means "4.5 and above".
const tk2BhkChoices = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5];
String tk2BhkLabel(double b) => b == 0.5
    ? '1 RK'
    : b >= 4.5
    ? '4.5+'
    : (b == b.roundToDouble() ? b.toInt().toString() : b.toString());

const tk2Sorts = {
  'new': 'Recently added',
  'old': 'Oldest first',
  'rentLow': 'Rent: low to high',
  'rentHigh': 'Rent: high to low',
  'bhkLow': 'BHK: small to large',
  'bhkHigh': 'BHK: large to small',
  'visits': 'Most visits',
};

const tk2FurnishingChoices = {'Empty': 'Unfurnished', 'Semi': 'Semi-furnished', 'Full': 'Fully furnished'};

class Tk2ListFilter {
  const Tk2ListFilter({this.sort = 'new', this.bhk = const {}, this.furnishing = const {}, this.status = 'all'});
  final String sort;
  final Set<double> bhk;
  final Set<String> furnishing;

  /// all · active · off
  final String status;

  int get count => (bhk.isEmpty ? 0 : 1) + (furnishing.isEmpty ? 0 : 1) + (status == 'all' ? 0 : 1);

  Tk2ListFilter copyWith({String? sort, Set<double>? bhk, Set<String>? furnishing, String? status}) =>
      Tk2ListFilter(sort: sort ?? this.sort, bhk: bhk ?? this.bhk, furnishing: furnishing ?? this.furnishing, status: status ?? this.status);

  bool _bhkOk(Tk2Listing l) {
    if (bhk.isEmpty) return true;
    final b = tk2Bhk(l.property.rooms);
    return bhk.any((c) => c >= 4.5 ? b >= 4.5 : b == c);
  }

  List<Tk2Listing> apply(List<Tk2Listing> all, Tk2Store store) {
    final out = [
      for (final l in all)
        if (_bhkOk(l) &&
            (furnishing.isEmpty || furnishing.contains(l.property.furnishing.isEmpty ? 'Empty' : l.property.furnishing)) &&
            (status == 'all' || (status == 'active') == store.isActive(l.id)))
          l,
    ];
    int by(Tk2Listing a, Tk2Listing b) => switch (sort) {
      'old' => a.createdAt.compareTo(b.createdAt),
      'rentLow' => a.rent.compareTo(b.rent),
      'rentHigh' => b.rent.compareTo(a.rent),
      'bhkLow' => tk2Bhk(a.property.rooms).compareTo(tk2Bhk(b.property.rooms)),
      'bhkHigh' => tk2Bhk(b.property.rooms).compareTo(tk2Bhk(a.property.rooms)),
      'visits' => store.visitsFor(b.id).length.compareTo(store.visitsFor(a.id).length),
      _ => b.createdAt.compareTo(a.createdAt),
    };
    return out..sort(by);
  }
}

/// "Sort · Recently added" and "Filter" pills above the list.
class Tk2SortFilterBar extends StatelessWidget {
  const Tk2SortFilterBar({required this.value, required this.onChanged, super.key});
  final Tk2ListFilter value;
  final ValueChanged<Tk2ListFilter> onChanged;

  Widget _pill(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap, bool on = false}) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: on ? AppColors.primaryDark : AppColors.heading,
      backgroundColor: on ? AppColors.primarySoft : Colors.white,
      side: BorderSide(color: on ? AppColors.primary : AppColors.border),
      shape: const StadiumBorder(),
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: _pill(
          context,
          icon: Icons.swap_vert,
          label: tk2Sorts[value.sort]!,
          on: value.sort != 'new',
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              backgroundColor: Colors.white,
              builder: (sheet) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text(
                        'Sort by',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.heading),
                      ),
                    ),
                    for (final e in tk2Sorts.entries)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        title: Text(e.value),
                        trailing: e.key == value.sort ? const Icon(Icons.check, color: AppColors.primary) : null,
                        onTap: () => Navigator.pop(sheet, e.key),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
            if (picked != null) onChanged(value.copyWith(sort: picked));
          },
        ),
      ),
      const SizedBox(width: 8),
      _pill(
        context,
        icon: Icons.tune,
        label: value.count == 0 ? 'Filter' : 'Filter · ${value.count}',
        on: value.count > 0,
        onTap: () async {
          final next = await showModalBottomSheet<Tk2ListFilter>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: Colors.white,
            builder: (_) => _FilterSheet(start: value),
          );
          if (next != null) onChanged(next);
        },
      ),
    ],
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.start});
  final Tk2ListFilter start;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late var f = widget.start;

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filter',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.heading),
                ),
              ),
              if (f.count > 0)
                TextButton(
                  onPressed: () => setState(() => f = Tk2ListFilter(sort: f.sort)),
                  child: const Text('Clear all'),
                ),
            ],
          ),
          _title('BHK'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in tk2BhkChoices)
                FilterChip(
                  label: Text(tk2BhkLabel(b)),
                  selected: f.bhk.contains(b),
                  onSelected: (on) => setState(() => f = f.copyWith(bhk: on ? {...f.bhk, b} : ({...f.bhk}..remove(b)))),
                ),
            ],
          ),
          _title('Furnishing'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in tk2FurnishingChoices.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: f.furnishing.contains(e.key),
                  onSelected: (on) => setState(() => f = f.copyWith(furnishing: on ? {...f.furnishing, e.key} : ({...f.furnishing}..remove(e.key)))),
                ),
            ],
          ),
          _title('Status'),
          Wrap(
            spacing: 8,
            children: [
              for (final e in const {'all': 'All', 'active': 'Active', 'off': 'Not active'}.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: f.status == e.key,
                  onSelected: (_) => setState(() => f = f.copyWith(status: e.key)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Show properties', onPressed: () => Navigator.pop(context, f)),
        ],
      ),
    ),
  );
}
