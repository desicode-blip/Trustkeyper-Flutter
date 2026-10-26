import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../data/broker_property_repository.dart';

class BrokerPropertyScreen extends StatefulWidget {
  const BrokerPropertyScreen({
    this.repository,
    this.initialProperty,
    this.onSelected,
    super.key,
  });

  final BrokerPropertyRepository? repository;
  final BrokerProperty? initialProperty;
  final ValueChanged<BrokerProperty>? onSelected;

  @override
  State<BrokerPropertyScreen> createState() => _BrokerPropertyScreenState();
}

class _BrokerPropertyScreenState extends State<BrokerPropertyScreen> {
  late final BrokerPropertyRepository repository;
  late final Stream<List<BrokerProperty>> properties;
  final address = TextEditingController();
  final size = TextEditingController();
  int stage = 0;
  int floor = 0;
  int totalFloors = 0;
  int cars = 0;
  int bikes = 0;
  String? rooms;
  String? furnishing;
  String? facing;
  String? error;
  bool saving = false;
  bool justSaved = false;
  BrokerProperty? selected;
  final inventory = {for (final name in BrokerProperty.inventoryItems) name: 0};

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? FirebaseBrokerPropertyRepository();
    properties = repository.watchProperties();
    address.addListener(_changed);
    if (widget.initialProperty != null) {
      selected = widget.initialProperty;
      _editSelected();
    }
  }

  void _changed() {
    if (mounted) setState(() => error = null);
  }

  @override
  void dispose() {
    address.dispose();
    size.dispose();
    super.dispose();
  }

  void _back() {
    if (saving) return;
    if (stage > 0) {
      setState(() {
        stage--;
        error = null;
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/broker/start');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: .2,
                      minHeight: 6,
                      color: AppColors.primary,
                      backgroundColor: AppColors.primaryBorder,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage == 0
                              ? 'Step 1 of 5 · House'
                              : 'Step 1 of 5 · Property',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      _CircleAction(
                        icon: 'call',
                        label: 'Call us',
                        onPressed: () =>
                            launchUrl(Uri.parse('tel:+918088516875')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ApprovedBackButton(onPressed: _back),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          stage == 0
                              ? 'Select the property'
                              : widget.initialProperty != null
                              ? 'Edit property'
                              : 'Add new property',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    switch (stage) {
                      0 => 'Pick your property, or add a new one.',
                      1 => 'Tell us about the property.',
                      2 => 'A few more details.',
                      3 => 'Things in the house. Tap + or −.',
                      _ => 'Check the details below.',
                    },
                    style: const TextStyle(
                      fontSize: 17,
                      height: 24 / 17,
                      color: AppColors.muted,
                    ),
                  ),
                  SizedBox(height: stage == 3 || stage == 4 ? 24 : 28),
                  switch (stage) {
                    0 => _picker(),
                    1 => _addressFields(),
                    2 => _roomFields(),
                    3 => _inventoryFields(),
                    _ => _summary(),
                  },
                ],
              ),
            ),
          ),
          if (stage > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEDF1F6))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null) ...[
                    Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(72, 56),
                        ),
                        onPressed: saving ? null : _back,
                        child: const Row(
                          children: [
                            Icon(Icons.chevron_left, size: 20),
                            SizedBox(width: 4),
                            Text('Back', style: TextStyle(fontSize: 17)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          label: saving
                              ? 'Saving…'
                              : stage == 3
                              ? 'Save property'
                              : stage == 4
                              ? 'Next: Owner'
                              : 'Next',
                          icon: stage == 3 ? Icons.check : Icons.chevron_right,
                          onPressed: saving ? null : _next,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _picker() => StreamBuilder<List<BrokerProperty>>(
    stream: properties,
    builder: (context, snapshot) {
      final values = snapshot.data ?? const <BrokerProperty>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(
            icon: 'building',
            label: 'My properties (${values.length})',
          ),
          const SizedBox(height: 12),
          if (snapshot.hasError) ...[
            const Text(
              'Could not load your properties. Check your connection.',
              style: TextStyle(color: AppColors.error),
            ),
          ] else if (!snapshot.hasData)
            const Center(child: CircularProgressIndicator()),
          OutlinedButton(
            onPressed: snapshot.hasData && !snapshot.hasError
                ? () => _chooseProperty(values)
                : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              side: const BorderSide(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search & select a property',
                    style: TextStyle(fontSize: 17, color: AppColors.muted),
                  ),
                ),
                Icon(Icons.expand_more, color: AppColors.muted),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: TextStyle(color: AppColors.muted)),
              ),
              Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: 22),
          _DashedAction(
            onPressed: _startNewProperty,
            child: const Column(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.add, size: 30, color: Colors.white),
                ),
                SizedBox(height: 10),
                Text(
                  'Add new property',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _addressFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('property-address'),
        controller: address,
        minLines: 2,
        maxLines: 2,
        style: const TextStyle(
          fontSize: 18,
          height: 24 / 18,
          color: AppColors.heading,
        ),
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Property name or address (optional)',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      const SizedBox(height: 26),
      TextField(
        key: const ValueKey('property-size'),
        controller: size,
        style: const TextStyle(
          fontSize: 22,
          height: 26 / 22,
          fontWeight: FontWeight.w600,
          color: AppColors.heading,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(
          labelText: 'Size',
          suffixIcon: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                'sq ft',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
          suffixIconConstraints: BoxConstraints(minHeight: 60),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        ),
      ),
      const SizedBox(height: 26),
      const _FieldLabel(icon: 'compass', label: 'Main door faces'),
      const SizedBox(height: 10),
      _choiceGrid(
        [
          'North-West',
          'North',
          'North-East',
          'West',
          '',
          'East',
          'South-West',
          'South',
          'South-East',
        ],
        facing,
        (value) => setState(() => facing = value),
        direction: true,
      ),
      const SizedBox(height: 26),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _labelCounter(
              'car',
              'Car parking',
              cars,
              (value) => setState(() => cars = value),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _labelCounter(
              'bike',
              'Bike parking',
              bikes,
              (value) => setState(() => bikes = value),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _roomFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _FieldLabel(icon: 'rooms', label: 'Rooms'),
      const SizedBox(height: 10),
      _choiceGrid(
        BrokerProperty.roomChoices,
        rooms,
        (value) => setState(() {
          rooms = value;
          error = null;
        }),
      ),
      const SizedBox(height: 26),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _labelCounter(
              'floor',
              'Floor',
              floor,
              (value) => setState(() => floor = value),
              maximum: 200,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _labelCounter(
              'building',
              'Total floors',
              totalFloors,
              (value) => setState(() => totalFloors = value),
              maximum: 200,
            ),
          ),
        ],
      ),
      const SizedBox(height: 26),
      const _FieldLabel(icon: 'furnished', label: 'Furnished'),
      const SizedBox(height: 10),
      _choiceGrid(
        BrokerProperty.furnishingChoices,
        furnishing,
        (value) => setState(() {
          furnishing = value;
          error = null;
        }),
        furnished: true,
      ),
    ],
  );

  Widget _choiceGrid(
    List<String> choices,
    String? selection,
    ValueChanged<String> onChanged, {
    bool direction = false,
    bool furnished = false,
  }) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: choices.map((choice) {
        final active = choice == selection;
        return SizedBox(
          width: (constraints.maxWidth - 16) / 3,
          child: choice.isEmpty
              ? const SizedBox(
                  height: 54,
                  child: Center(child: _DesignIcon('compass', size: 24)),
                )
              : Semantics(
                  selected: active,
                  button: true,
                  label: choice,
                  child: Material(
                    color: active ? AppColors.primary : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => onChanged(choice),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: furnished
                              ? 12
                              : direction
                              ? 8
                              : 14,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (direction || furnished) ...[
                              Transform.rotate(
                                angle: direction
                                    ? (switch (choice) {
                                            'North-West' => -1,
                                            'North-East' => 1,
                                            'West' => -2,
                                            'East' => 2,
                                            'South-West' => -3,
                                            'South' => 4,
                                            'South-East' => 3,
                                            _ => 0,
                                          }) *
                                          3.141592653589793 /
                                          4
                                    : 0,
                                child: _DesignIcon(
                                  choice.toLowerCase(),
                                  size: furnished ? 24 : 18,
                                  color: active
                                      ? Colors.white
                                      : AppColors.muted,
                                ),
                              ),
                              SizedBox(height: direction ? 3 : 4),
                            ],
                            Text(
                              choice,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: direction
                                    ? 13.5
                                    : furnished
                                    ? 15
                                    : 16,
                                height: direction
                                    ? 17 / 13.5
                                    : furnished
                                    ? 20 / 15
                                    : 24 / 16,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: active
                                    ? Colors.white
                                    : AppColors.heading,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      }).toList(),
    ),
  );

  Widget _labelCounter(
    String icon,
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int maximum = 100,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FieldLabel(icon: icon, label: label),
      const SizedBox(height: 10),
      Container(
        height: 56,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(28),
        ),
        child: _Counter(
          label: label,
          value: value,
          onChanged: onChanged,
          maximum: maximum,
          size: 44,
        ),
      ),
    ],
  );

  Widget _inventoryFields() => Column(
    children: [
      for (final item in inventory.entries)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: item.key == inventory.keys.last
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFEDF1F6))),
          ),
          child: Row(
            children: [
              BrokerProperty.inventoryItems.contains(item.key)
                  ? _DesignIcon(item.key.toLowerCase(), size: 24)
                  : const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.muted,
                      size: 24,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.key,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.heading,
                  ),
                ),
              ),
              SizedBox(
                width: 136,
                child: _Counter(
                  label: item.key,
                  value: item.value,
                  onChanged: (value) =>
                      setState(() => inventory[item.key] = value),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 18),
      _DashedAction(
        onPressed: _addItem,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.primaryDark, size: 20),
            SizedBox(width: 10),
            Text(
              'Add other item',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _summary() {
    final property = selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (justSaved) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFF2FA866),
                  child: Icon(Icons.check, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Property added',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        'Saved in My properties',
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        property.displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 28 / 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _editSelected,
                      tooltip: 'Change property details',
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEDF1F6)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    children: [
                      for (final fact in [
                        ('rooms', property.rooms),
                        (
                          'floor',
                          'Floor ${property.floor} of ${property.totalFloors}',
                        ),
                        (
                          'size',
                          property.sizeSqFt == null
                              ? 'Size not added'
                              : '${NumberFormat('#,##0.#', 'en_IN').format(property.sizeSqFt)} sq ft',
                        ),
                        ('furnished', '${property.furnishing} furnished'),
                        (
                          'compass',
                          property.facing == null
                              ? 'Facing not added'
                              : '${property.facing} facing',
                        ),
                        (
                          'car',
                          '${property.carParking} car · ${property.bikeParking} bike',
                        ),
                      ])
                        SizedBox(
                          width: constraints.maxWidth / 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                            child: Column(
                              children: [
                                _DesignIcon(
                                  fact.$1,
                                  size: 26,
                                  color: AppColors.primaryDark,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  fact.$2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 18 / 15,
                                    color: AppColors.heading,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                color: AppColors.surfaceMuted,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Things in the house',
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    if (property.inventory.values.every((count) => count == 0))
                      const Text('No items added'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in property.inventory.entries)
                          if (item.value > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (BrokerProperty.inventoryItems.contains(
                                    item.key,
                                  )) ...[
                                    _DesignIcon(
                                      item.key.toLowerCase(),
                                      color: AppColors.primaryDark,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    '${item.value} ${item.key}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.heading,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _editSelected() {
    final property = selected!;
    address.text = property.address;
    size.text = property.sizeSqFt?.toString() ?? '';
    setState(() {
      rooms = property.rooms;
      furnishing = property.furnishing;
      facing = property.facing;
      floor = property.floor;
      totalFloors = property.totalFloors;
      cars = property.carParking;
      bikes = property.bikeParking;
      inventory
        ..clear()
        ..addAll({for (final name in BrokerProperty.inventoryItems) name: 0})
        ..addAll(property.inventory);
      stage = 1;
    });
  }

  void _startNewProperty() {
    address.clear();
    size.clear();
    setState(() {
      selected = null;
      justSaved = false;
      rooms = furnishing = facing = error = null;
      floor = totalFloors = cars = bikes = 0;
      inventory
        ..clear()
        ..addAll({for (final name in BrokerProperty.inventoryItems) name: 0});
      stage = 1;
    });
  }

  Future<void> _chooseProperty(List<BrokerProperty> values) async {
    final property = await showModalBottomSheet<BrokerProperty>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PropertySearch(properties: values),
    );
    if (mounted && property != null) {
      selected = property;
      justSaved = false;
      _editSelected();
      setState(() => stage = 4);
    }
  }

  Future<void> _addItem() async {
    final item = await showDialog<(String, int)>(
      context: context,
      builder: (context) => const _AddInventoryItemDialog(),
    );
    if (!mounted || item == null) return;
    final name = item.$1;
    if (inventory.keys.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => error = 'That item is already in the list');
      return;
    }
    setState(() {
      inventory[name] = item.$2;
      error = null;
    });
  }

  Future<void> _next() async {
    if (stage == 4) {
      if (selected!.validationError != null) {
        setState(
          () => error =
              '${selected!.validationError} Tap edit to update this field.',
        );
        return;
      }
      if (widget.onSelected != null) {
        widget.onSelected!(selected!);
      } else {
        context.push('/broker/agreement', extra: selected);
      }
      return;
    }
    if (stage == 1 &&
        size.text.isNotEmpty &&
        (double.tryParse(size.text) == null || double.parse(size.text) <= 0)) {
      setState(() => error = 'Enter a valid size');
      return;
    }
    if (stage == 2 &&
        (rooms == null || furnishing == null || totalFloors < floor)) {
      setState(
        () => error = rooms == null
            ? 'Choose the rooms'
            : furnishing == null
            ? 'Choose the furnishing'
            : 'Total floors cannot be less than the property floor',
      );
      return;
    }
    if (stage < 3) {
      setState(() {
        stage++;
        error = null;
      });
      return;
    }
    final property = BrokerProperty(
      id: selected?.id ?? '',
      address: address.text,
      rooms: rooms!,
      floor: floor,
      totalFloors: totalFloors,
      furnishing: furnishing!,
      sizeSqFt: double.tryParse(size.text),
      facing: facing,
      carParking: cars,
      bikeParking: bikes,
      inventory: inventory,
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await repository.save(property);
      if (mounted) {
        setState(() {
          selected = saved;
          justSaved = true;
          stage = 4;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save your property. Check your connection and broker approval, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _AddInventoryItemDialog extends StatefulWidget {
  const _AddInventoryItemDialog();

  @override
  State<_AddInventoryItemDialog> createState() =>
      _AddInventoryItemDialogState();
}

class _AddInventoryItemDialogState extends State<_AddInventoryItemDialog> {
  final controller = TextEditingController();
  int count = 1;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add item',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Item name, for example Chimney',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            const _FieldLabel(icon: 'plus', label: 'How many'),
            const SizedBox(height: 10),
            Container(
              height: 56,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(28),
              ),
              child: _Counter(
                label: 'new item count',
                value: count,
                size: 44,
                onChanged: (value) => setState(() => count = value),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Add',
              icon: Icons.check,
              onPressed: controller.text.trim().isEmpty || count == 0
                  ? null
                  : () =>
                        Navigator.pop(context, (controller.text.trim(), count)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DesignIcon extends StatelessWidget {
  const _DesignIcon(this.name, {this.size = 16, this.color = AppColors.muted});
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/design/property-$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});
  final String icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      _DesignIcon(icon),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            height: 16 / 14,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
      ),
    ],
  );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final String icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    shadowColor: AppColors.heading.withValues(alpha: .1),
    surfaceTintColor: Colors.transparent,
    shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
    child: InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Semantics(
          button: true,
          label: label,
          child: Center(
            child: _DesignIcon(icon, size: 20, color: AppColors.heading),
          ),
        ),
      ),
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maximum = 100,
    this.size = 40,
  });
  final String label;
  final int value;
  final int maximum;
  final double size;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _control(
        'minus',
        'Decrease $label',
        value > 0 ? () => onChanged(value - 1) : null,
      ),
      Flexible(
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: size == 44 ? 22 : 20,
            fontWeight: FontWeight.w700,
            color: value == 0 ? const Color(0xFF8C99AB) : AppColors.heading,
          ),
        ),
      ),
      _control(
        'plus',
        'Increase $label',
        value < maximum ? () => onChanged(value + 1) : null,
      ),
    ],
  );
  Widget _control(String icon, String tooltip, VoidCallback? action) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      enabled: action != null,
      child: Material(
        color: action == null
            ? const Color(0xFFEDF1F6)
            : icon == 'plus'
            ? AppColors.primary
            : AppColors.primarySoft,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: action,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: _DesignIcon(
                icon,
                size: 20,
                color: action == null
                    ? const Color(0xFF8C99AB)
                    : icon == 'plus'
                    ? Colors.white
                    : AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DashedAction extends StatelessWidget {
  const _DashedAction({required this.child, required this.onPressed});
  final Widget child;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorder(),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
          child: child,
        ),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)),
      );
    final paint = Paint()
      ..color = const Color(0xFF9DB2FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 6) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 3).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PropertySearch extends StatefulWidget {
  const _PropertySearch({required this.properties});
  final List<BrokerProperty> properties;
  @override
  State<_PropertySearch> createState() => _PropertySearchState();
}

class _PropertySearchState extends State<_PropertySearch> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.properties
        .where(
          (property) =>
              property.address.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search properties',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Text('No properties found. Add a new property.'),
                      )
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(matches[index].address),
                          subtitle: Text(matches[index].rooms),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, matches[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
