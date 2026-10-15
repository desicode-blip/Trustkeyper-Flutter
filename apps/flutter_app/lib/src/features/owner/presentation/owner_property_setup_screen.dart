import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/approved_journey_widgets.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/data/agreement_imports.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../data/owner_properties.dart';
import '../data/owner_lifecycle.dart';
import 'owner_lifecycle_screen.dart';
import '../../../core/widgets/session_bound_screen.dart';
import '../../../core/testing/owner_lifecycle_fixture.dart';

class OwnerPropertySetupScreen extends StatefulWidget {
  const OwnerPropertySetupScreen({
    this.gateway,
    this.lifecycle,
    this.contractProof,
    this.photoPicker,
    this.photoReviewer,
    this.offline = false,
    super.key,
  });
  final OwnerPropertyGateway? gateway;
  final OwnerLifecycleGateway? lifecycle;
  final OwnerContractPhoneProof? contractProof;
  final Future<AgreementPageFile?> Function()? photoPicker;
  final Future<bool> Function(AgreementPageFile file)? photoReviewer;
  final bool offline;
  @override
  State<OwnerPropertySetupScreen> createState() =>
      _OwnerPropertySetupScreenState();
}

class _OwnerPropertySetupScreenState extends State<OwnerPropertySetupScreen> {
  late final gateway = widget.gateway ?? FirebaseOwnerPropertyGateway();
  final form = GlobalKey<FormState>();
  final controllers = {
    for (final key in [
      'address',
      'name',
      'bathrooms',
      'balconies',
      'floor',
      'totalFloors',
      'sizeSqFt',
      'rent',
      'maintenance',
      'deposit',
    ])
      key: TextEditingController(),
  };
  final photos = <AgreementPageFile>[];
  List<OwnerPropertyRecord>? saved;
  OwnerPropertyRecord? current;
  final features = <String>{};
  String homeType = 'Apartment';
  String rooms = '2 BHK';
  String furnishing = 'Empty';
  String pets = 'Ask me';
  String who = 'Anyone';
  String plan = 'diy';
  String method = 'visit';
  String slot = '10:00–12:00';
  bool negotiable = false;
  bool teamPhotos = false;
  bool busy = false;
  int step = -1;
  String? error;
  String? saveOperation;
  String? savePayload;
  String? photoOperation;
  DateTime ready = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 1)),
  );
  DateTime checkDay = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 1)),
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fail(Object failure) => setState(
    () => error = failure is DocumentFailure
        ? failure.message
        : 'Your property was not confirmed. Keep your details and retry, or refresh saved properties.',
  );
  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      saved = null;
    });
    try {
      final values = await gateway.list();
      if (mounted) setState(() => saved = values);
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _open(OwnerPropertyRecord? record) {
    if (record != null &&
        (record.status == 'fee_offered' || record.data['contract'] != null)) {
      final screen = OwnerLifecycleScreen(
        property: record,
        gateway:
            widget.lifecycle ??
            (widget.offline ? OfflineOwnerLifecycleGateway() : null),
        properties: gateway,
        proof:
            widget.contractProof ??
            (widget.offline ? OfflineOwnerContractPhoneProof() : null),
        offline: widget.offline,
      );
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  widget.offline ? screen : SessionBoundScreen(child: screen),
            ),
          )
          .then((_) {
            if (mounted) _load();
          });
      return;
    }
    final values = record?.details ?? <String, dynamic>{};
    for (final entry in controllers.entries) {
      entry.value.text = values[entry.key]?.toString() ?? '';
    }
    for (final key in ['rent', 'maintenance', 'deposit']) {
      final paise = values['${key}Paise'];
      controllers[key]!.text = paise is int
          ? (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2)
          : '';
    }
    setState(() {
      current = record;
      saveOperation = null;
      photoOperation = null;
      error = null;
      photos.clear();
      features.clear();
      features.addAll((values['features'] as List? ?? []).whereType<String>());
      homeType = values['homeType'] as String? ?? 'Apartment';
      rooms = values['rooms'] as String? ?? '2 BHK';
      furnishing = values['furnishing'] as String? ?? 'Empty';
      pets = values['pets'] as String? ?? 'Ask me';
      who = values['whoCanStay'] as String? ?? 'Anyone';
      negotiable = values['negotiable'] == true;
      teamPhotos = values['teamPhotos'] == true;
      ready =
          DateTime.tryParse(values['availableFrom']?.toString() ?? '') ??
          DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
      plan = record?.data['plan'] as String? ?? 'diy';
      final check = record?.data['check'];
      method = check is Map ? check['method'] as String? ?? 'visit' : 'visit';
      slot = check is Map
          ? check['slot'] as String? ?? '10:00–12:00'
          : '10:00–12:00';
      checkDay = check is Map
          ? DateTime.tryParse(check['day']?.toString() ?? '') ??
                DateTime.now().add(const Duration(days: 1))
          : DateTime.now().add(const Duration(days: 1));
      step = record == null
          ? -2
          : record.status == 'draft'
          ? record.nextStep
          : [
              'check_requested',
              'check_confirmed',
              'fee_offered',
            ].contains(record.status)
          ? 8
          : 5;
    });
  }

  String _iso(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
  Map<String, dynamic> _input() => switch (step) {
    0 => {
      'address': controllers['address']!.text.trim(),
      'name': controllers['name']!.text.trim(),
      'homeType': homeType,
    },
    1 => {
      'rooms': rooms,
      for (final key in [
        'bathrooms',
        'balconies',
        'floor',
        'totalFloors',
        'sizeSqFt',
      ])
        key: int.tryParse(controllers[key]!.text) ?? -1,
      'furnishing': furnishing,
    },
    2 => {'features': features.toList(), 'pets': pets},
    3 => {
      'rentPaise': parseRupeesToPaise(controllers['rent']!.text) ?? -1,
      'maintenancePaise': controllers['maintenance']!.text.trim().isEmpty
          ? 0
          : parseRupeesToPaise(controllers['maintenance']!.text) ?? -1,
      'depositPaise': parseRupeesToPaise(controllers['deposit']!.text) ?? -1,
      'availableFrom': _iso(ready),
      'whoCanStay': who,
      'negotiable': negotiable,
    },
    _ => {'teamPhotos': teamPhotos},
  };
  Future<void> _save() async {
    if (!form.currentState!.validate() || busy) return;
    if (step == 4 &&
        photos.isEmpty &&
        (current?.photos.isEmpty ?? true) &&
        !teamPhotos) {
      setState(
        () => error =
            'Add 1 to 5 clear photos, or request our team to take them.',
      );
      return;
    }
    final previousStep = step;
    setState(() {
      busy = true;
      error = null;
    });
    final payload = jsonEncode(_input());
    if (savePayload != payload) {
      saveOperation = importOperationId();
      savePayload = payload;
    }
    saveOperation ??= importOperationId();
    try {
      if (step == 4 && photos.isNotEmpty) {
        photoOperation ??= importOperationId();
        final updated = await gateway.uploadPhotos(
          current!,
          photos,
          photoOperation!,
        );
        if (!mounted) return;
        current = updated;
        photos.clear();
        photoOperation = null;
      }
      final updated = await gateway.save(
        current,
        step,
        _input(),
        saveOperation!,
      );
      if (!mounted) return;
      setState(() {
        current = updated;
        step = previousStep == 4 ? 5 : previousStep + 1;
        saveOperation = null;
      });
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _photo() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      AgreementPageFile? selected;
      if (widget.photoPicker != null) {
        selected = await widget.photoPicker!();
      } else {
        if (!context.mounted) return;
        final camera = await showModalBottomSheet<bool>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take photo'),
                  onTap: () => Navigator.pop(context, true),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Upload from phone'),
                  onTap: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
        );
        if (camera == null) return;
        final file = await pickPrivateDocument(camera: camera);
        if (file != null) {
          selected = AgreementPageFile(name: file.name, bytes: file.bytes);
        }
      }
      if (selected == null || !mounted) return;
      selected.validate();
      if (!selected.contentType.startsWith('image/') ||
          selected.bytes.length > 10485760 ||
          photos.length >= 5 ||
          photos.fold<int>(0, (total, photo) => total + photo.bytes.length) +
                  selected.bytes.length >
              20971520 ||
          photos.any((photo) => photo.digest == selected!.digest)) {
        throw const DocumentFailure(
          'Add different JPG/PNG photos, up to 5 photos and 20 MB in total.',
        );
      }
      final bool reviewed;
      if (widget.photoReviewer != null) {
        reviewed = await widget.photoReviewer!(selected);
      } else {
        if (!mounted) return;
        reviewed = await reviewPrivateDocument(
          context,
          selected,
          upload: true,
          selectionOnly: true,
          reviewTitle: 'Check this property photo',
          instructions:
              'Check light and focus. Open curtains, switch on lights, and take it again if dark or blurry. Confirm only a clear photo of your property.',
        );
      }
      if (reviewed && mounted) {
        setState(() {
          photos.add(selected!);
          photoOperation = null;
        });
      }
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _viewPhoto(int index) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await gateway.readPhoto(current!, index);
      if (!mounted) return;
      await reviewPrivateDocument(
        context,
        file,
        upload: false,
        selectionOnly: true,
        reviewTitle: 'Saved property photo',
      );
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickDay(bool check) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final value = check ? checkDay : ready;
    final selected = await showDatePicker(
      context: context,
      initialDate: value.isBefore(today) ? today : value,
      firstDate: today,
      lastDate: today.add(Duration(days: check ? 60 : 730)),
    );
    if (selected != null && mounted) {
      setState(() {
        if (check) {
          checkDay = selected;
        } else {
          ready = selected;
        }
      });
    }
  }

  Future<void> _requestPlan() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await gateway.requestPlan(
        current!,
        plan,
        method,
        _iso(checkDay),
        slot,
      );
      if (mounted) {
        setState(() {
          current = value;
          step = 8;
        });
      }
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _heading(String title, String subtitle) => ApprovedJourneyHeading(
    title: title,
    subtitle: subtitle,
    onBack: busy ? null : _back,
  );
  Widget _choices(
    String title,
    List<String> values,
    String selected,
    ValueChanged<String> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: values
            .map(
              (value) => ChoiceChip(
                label: Text(value),
                selected: selected == value,
                onSelected: busy ? null : (_) => setState(() => change(value)),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 20),
    ],
  );
  Widget _homeTypes() => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Type of home *',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in [
              (Icons.apartment_outlined, 'Apartment'),
              (Icons.home_outlined, 'House'),
              (Icons.villa_outlined, 'Villa'),
              (Icons.bed_outlined, 'Studio'),
              (Icons.add, 'Other'),
            ])
              SizedBox(
                width: (constraints.maxWidth - 16) / 3,
                child: Material(
                  color: homeType == type.$2
                      ? AppColors.primary
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: busy
                        ? null
                        : () => setState(() => homeType = type.$2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 4,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            type.$1,
                            color: homeType == type.$2
                                ? Colors.white
                                : AppColors.heading,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            type.$2,
                            style: TextStyle(
                              color: homeType == type.$2
                                  ? Colors.white
                                  : AppColors.heading,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
  Widget _field(
    String key,
    String label, {
    bool required = true,
    bool count = false,
    bool money = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: controllers[key],
      enabled: !busy,
      maxLength: count || money
          ? 12
          : key == 'address'
          ? 500
          : 100,
      keyboardType: count
          ? TextInputType.number
          : money
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (!required && text.isEmpty) return null;
        if (text.isEmpty) return 'Complete this field';
        if (count && (int.tryParse(text) == null || int.parse(text) < 0)) {
          return 'Enter a whole, non-negative number';
        }
        if (money && parseRupeesToPaise(text) == null) {
          return 'Enter rupees with up to two decimals';
        }
        return null;
      },
    ),
  );
  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
  void _back() {
    if (busy) return;
    if (step >= 0 && step <= 4) {
      setState(() => step--);
    } else if (step == 6 || step == 7) {
      setState(() => step--);
    } else {
      setState(() {
        step = -1;
        current = null;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ApprovedAuthScaffold(
          showBack: false,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.offline)
                  const Text('OFFLINE TEST · synthetic property only'),
                if (step >= 0 && step <= 4) ...[
                  LinearProgressIndicator(
                    value: (step + 1) / 5,
                    minHeight: 5,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primarySoft,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Step ${step + 1} of 5 · ${['Property', 'Rooms', 'Things', 'Rent', 'Photos'][step]}',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ApprovedJourneyHelp(
                        onPressed: busy
                            ? null
                            : () => context.push('/owner/support'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          footer: Row(
            children: [
              TextButton(
                onPressed: busy ? null : _back,
                child: const Text('‹ Back'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: busy
                      ? 'Saving…'
                      : step == 4
                      ? 'Save property'
                      : step == 5
                      ? 'Next: Pick a plan'
                      : step == 6
                      ? 'Next: Free check'
                      : step == 7
                      ? 'Request check'
                      : step == 8
                      ? 'Go to home'
                      : 'Next',
                  onPressed: busy || step < 0
                      ? null
                      : step <= 4
                      ? _save
                      : step <= 6
                      ? () => setState(() => step++)
                      : step == 7
                      ? _requestPlan
                      : () => context.go('/owner'),
                ),
              ),
            ],
          ),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                if (step == -1) ...[
                  _heading(
                    'Your properties',
                    'Start a new property, or finish what you saved.',
                  ),
                  for (final property in saved ?? <OwnerPropertyRecord>[])
                    _card(
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(property.name),
                        subtitle: Text(
                          property.status == 'draft'
                              ? 'Step ${property.nextStep + 1} of 5 · saved'
                              : property.status == 'check_requested'
                              ? 'Free check · waiting for team confirmation'
                              : property.status == 'property_added'
                              ? 'Property added · choose a plan'
                              : property.status.replaceAll('_', ' '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: busy ? null : () => _open(property),
                      ),
                    ),
                  PrimaryButton(
                    label: 'Add your property',
                    onPressed: busy ? null : () => _open(null),
                  ),
                  TextButton(
                    onPressed: busy ? null : _load,
                    child: const Text('Refresh saved properties'),
                  ),
                ],
                if (step == -2) ...[
                  _heading(
                    'What do you want to do?',
                    'Pick one for this property.',
                  ),
                  _card(
                    ListTile(
                      leading: const Icon(
                        Icons.home_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Rent it out'),
                      subtitle: const Text('Find a tenant, we collect rent'),
                      onTap: () => setState(() => step = 0),
                    ),
                  ),
                  _card(
                    ListTile(
                      leading: const Icon(
                        Icons.handyman_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Look after it'),
                      subtitle: const Text(
                        'A tenant already lives there · manager calls you',
                      ),
                      onTap: () => context.push('/owner/support'),
                    ),
                  ),
                  _card(
                    ListTile(
                      leading: const Icon(
                        Icons.sell_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Sell it'),
                      subtitle: const Text(
                        'Today we help owners rent and look after homes. Talk to us about selling.',
                      ),
                      onTap: () => context.push('/owner/support'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/owner/support'),
                    child: const Text(
                      'Our manager can do it for you · Call me',
                    ),
                  ),
                ],
                if (step >= 0 && step <= 4)
                  _heading(
                    'Add your property',
                    [
                      'Where is it?',
                      'Rooms and size.',
                      'Tap what the home has.',
                      'Rent and who can stay.',
                      'Add 1 to 5 photos (one to five).',
                    ][step],
                  ),
                if (step == 0) ...[
                  _field('address', 'Address (optional)', required: false),
                  _field('name', 'Name for this home', required: false),
                  const Text('Only you see this name.'),
                  const SizedBox(height: 16),
                  _homeTypes(),
                ],
                if (step == 1) ...[
                  _choices(
                    'Rooms *',
                    ['1 RK', '1 BHK', '2 BHK', '3 BHK', '4 BHK', '4+ BHK'],
                    rooms,
                    (value) => rooms = value,
                  ),
                  for (final key in [
                    'bathrooms',
                    'balconies',
                    'floor',
                    'totalFloors',
                    'sizeSqFt',
                  ])
                    _field(
                      key,
                      {
                        'bathrooms': 'Bathrooms',
                        'balconies': 'Balconies',
                        'floor': 'Floor',
                        'totalFloors': 'Total floors',
                        'sizeSqFt': 'Size · sq ft',
                      }[key]!,
                      count: true,
                    ),
                  _choices(
                    'Furnished',
                    ['Empty', 'Semi', 'Full'],
                    furnishing,
                    (value) => furnishing = value,
                  ),
                ],
                if (step == 2) ...[
                  for (final group in [
                    ownerPropertyFeatures.take(8).toList(),
                    ownerPropertyFeatures.skip(8).toList(),
                  ]) ...[
                    Text(
                      group.first == 'AC' ? 'In the house' : 'In the building',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: group
                          .map(
                            (value) => FilterChip(
                              label: Text(value),
                              selected: features.contains(value),
                              onSelected: busy
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected) {
                                        features.add(value);
                                      } else {
                                        features.remove(value);
                                      }
                                    }),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _choices(
                    'Pets allowed?',
                    ['Yes', 'No', 'Ask me'],
                    pets,
                    (value) => pets = value,
                  ),
                  const Text(
                    'Press Next to save this step. You can finish later from your properties on web or app.',
                  ),
                ],
                if (step == 3) ...[
                  _choices(
                    'Who can stay? *',
                    ['Family', 'Men only', 'Women only', 'Anyone'],
                    who,
                    (value) => who = value,
                  ),
                  _field('rent', 'Rent every month * · ₹', money: true),
                  _field(
                    'maintenance',
                    'Maintenance · ₹',
                    money: true,
                    required: false,
                  ),
                  _field('deposit', 'Deposit * · ₹', money: true),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _pickDay(false),
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      'Ready from · ${DateFormat('d MMM yyyy').format(ready)}',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: negotiable,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => negotiable = value),
                    title: const Text('Rent can change?'),
                  ),
                ],
                if (step == 4) ...[
                  const Text('Daylight · clear · every room'),
                  const SizedBox(height: 18),
                  for (var index = 0; index < photos.length; index++)
                    _card(
                      Column(
                        children: [
                          Image.memory(
                            photos[index].bytes,
                            height: 130,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Text('Photo preview unavailable'),
                          ),
                          Text('Photo ${index + 1} · reviewed by you'),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    photos.removeAt(index);
                                    photoOperation = null;
                                  }),
                            child: const Text('Remove photo'),
                          ),
                        ],
                      ),
                    ),
                  if (photos.isEmpty)
                    for (
                      var index = 0;
                      index < (current?.photos.length ?? 0);
                      index++
                    )
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => _viewPhoto(index),
                        icon: const Icon(Icons.photo_outlined),
                        label: Text('View saved photo ${index + 1}'),
                      ),
                  if (photos.length < 5)
                    OutlinedButton.icon(
                      onPressed: busy ? null : _photo,
                      icon: const Icon(Icons.add),
                      label: const Text('Add photo'),
                    ),
                  if (current?.photos.isNotEmpty == true)
                    const Text(
                      'New photos replace the saved set only after the server confirms your upload.',
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: teamPhotos,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => teamPhotos = value == true),
                    title: const Text('Our team can take them for you'),
                    subtitle: const Text(
                      'I’m interested · request, not a completed visit',
                    ),
                  ),
                ],
                if (step == 5) ...[
                  _heading(
                    'Property added',
                    'All 5 steps done. Check the details below.',
                  ),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current!.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(current!.details['address'] as String),
                        Text(
                          '${current!.details['rooms']} · ${current!.details['furnishing']} furnished',
                        ),
                        Text(
                          'Floor ${current!.details['floor']} of ${current!.details['totalFloors']} · ${current!.details['sizeSqFt']} sq ft',
                        ),
                        Text(
                          '₹${NumberFormat.decimalPattern('en_IN').format((current!.details['rentPaise'] as int) / 100)} rent · from ${current!.details['availableFrom']}',
                        ),
                        Text(
                          '${current!.photos.length} saved photos · ${(current!.details['features'] as List).length} things ticked',
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => step = 0),
                          child: const Text('Change property details'),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Add your property  ✓\nPick a plan\nFind a tenant',
                  ),
                ],
                if (step == 6) ...[
                  _heading(
                    'Pick a plan',
                    'Both plans: we make the agreement and collect rent.',
                  ),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChoiceChip(
                          label: const Text('Do it yourself'),
                          selected: plan == 'diy',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => plan = 'diy'),
                        ),
                        const Text(
                          'You add details and photos\nYou show the home to tenants\nYou talk to tenants',
                        ),
                      ],
                    ),
                  ),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChoiceChip(
                          label: const Text('We do it all'),
                          selected: plan == 'full_service',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => plan = 'full_service'),
                        ),
                        const Text(
                          'Photos by our team\nWe show the home to tenants\nWe look after repairs',
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Fee: 5% to 20% of rent\nSet by building age and other details after a free check. A fee is not assigned until the team records your contract offer.',
                  ),
                ],
                if (step == 7) ...[
                  _heading(
                    'Free home check',
                    'Our manager checks the home to set your fee.',
                  ),
                  Text(
                    'Plan: ${plan == 'diy' ? 'Do it yourself' : 'We do it all'}',
                  ),
                  const SizedBox(height: 20),
                  _choices(
                    'How?',
                    ['visit', 'video'],
                    method,
                    (value) => method = value,
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _pickDay(true),
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      'Day · ${DateFormat('EEE d MMM').format(checkDay)}',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _choices(
                    'Time',
                    ['10:00–12:00', '12:00–14:00', '16:00–18:00'],
                    slot,
                    (value) => slot = value,
                  ),
                  const Text(
                    'Takes about 30 minutes. Free. The team confirms the actual manager and time before your visit.',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => context.push('/owner/support'),
                    child: const Text(
                      'Not sure? Our manager can do it for you · Call me',
                    ),
                  ),
                ],
                if (step == 8) ...[
                  _heading(
                    current!.status == 'fee_offered'
                        ? 'Your fee offer'
                        : current!.status == 'check_confirmed'
                        ? 'Check booked'
                        : 'Check requested',
                    current!.status == 'check_requested'
                        ? 'Your request is saved. We will confirm the manager and actual time.'
                        : 'Saved by the TrustKeyper team. Review the actual details below.',
                  ),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current!.name),
                        Text(
                          '${current!.data['check']['day']} · ${current!.data['check']['slot']}',
                        ),
                        Text(
                          current!.data['check']['method'] == 'visit'
                              ? 'Visit the home'
                              : 'Video call',
                        ),
                        if (current!.data['check']['managerName'] != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Manager · ${current!.data['check']['managerName']}',
                          ),
                          Text(
                            current!.data['check']['managerPhone'] as String,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (current!.data['feeOffer'] is Map)
                          Text(
                            'Fee offered · ${(current!.data['feeOffer']['feeBps'] as int) / 100}% of rent\nEffective from · ${current!.data['feeOffer']['effectiveFrom']}\n${current!.data['feeOffer']['notes']}',
                          )
                        else
                          const Text('Fee: pending the free check'),
                        const Text(
                          'Contract: not signed yet\nListing: not live yet',
                        ),
                      ],
                    ),
                  ),
                  if (current!.status == 'check_requested')
                    TextButton(
                      onPressed: busy ? null : () => setState(() => step = 7),
                      child: const Text('Change requested time'),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => context.push('/owner/support'),
                    child: const Text('Ask your manager'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
