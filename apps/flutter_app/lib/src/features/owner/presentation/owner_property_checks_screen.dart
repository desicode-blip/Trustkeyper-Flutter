import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../broker/data/private_documents.dart';
import '../data/owner_properties.dart';
import 'owner_property_admin_actions.dart';

class OwnerPropertyChecksScreen extends StatefulWidget {
  const OwnerPropertyChecksScreen({this.gateway, super.key});
  final OwnerPropertyGateway? gateway;
  @override
  State<OwnerPropertyChecksScreen> createState() =>
      _OwnerPropertyChecksScreenState();
}

class _OwnerPropertyChecksScreenState extends State<OwnerPropertyChecksScreen> {
  late final gateway = widget.gateway ?? FirebaseOwnerPropertyGateway();
  List<OwnerPropertyRecord>? records;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      records = null;
    });
    try {
      final values = await gateway.list(admin: true);
      if (mounted) setState(() => records = values);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'Property requests could not be loaded. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _record(OwnerPropertyRecord property, bool offer) async {
    final reference = TextEditingController();
    final notes = TextEditingController();
    final manager = TextEditingController(
      text: property.data['check']?['managerName'] as String?,
    );
    final phone = TextEditingController(
      text: property.data['check']?['managerPhone'] as String?,
    );
    final fee = TextEditingController();
    final day = TextEditingController(
      text: offer
          ? DateFormat('yyyy-MM-dd').format(DateTime.now())
          : property.data['check']['day'] as String,
    );
    final form = GlobalKey<FormState>();
    bool completed = false;
    String slot = property.data['check']['slot'] as String;
    final input = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            offer
                ? 'Record completed check and fee offer'
                : 'Confirm actual appointment',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      offer
                          ? 'An offer does not sign a contract, activate a tenancy or apply a fee to payments.'
                          : 'Confirm only an appointment agreed with the assigned manager.',
                    ),
                    if (!offer) ...[
                      TextFormField(
                        controller: manager,
                        decoration: const InputDecoration(
                          labelText: 'Assigned manager name',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter the actual manager'
                            : null,
                      ),
                      TextFormField(
                        controller: phone,
                        decoration: const InputDecoration(
                          labelText: 'Manager phone (+91…)',
                        ),
                        validator: (value) =>
                            RegExp(r'^\+91\d{10}$').hasMatch(value ?? '')
                            ? null
                            : 'Enter +91 and 10 digits',
                      ),
                    ],
                    TextFormField(
                      controller: day,
                      decoration: InputDecoration(
                        labelText: offer
                            ? 'Effective from (YYYY-MM-DD)'
                            : 'Confirmed day (YYYY-MM-DD)',
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value ?? '')
                          ? null
                          : 'Enter YYYY-MM-DD',
                    ),
                    if (!offer)
                      DropdownButtonFormField<String>(
                        initialValue: slot,
                        items: ['10:00–12:00', '12:00–14:00', '16:00–18:00']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => slot = value!,
                      ),
                    if (offer) ...[
                      TextFormField(
                        controller: fee,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Fee percentage (5–20)',
                        ),
                        validator: (value) => _fee(value) != null
                            ? null
                            : 'Enter 5–20 with up to two decimals',
                      ),
                      CheckboxListTile(
                        value: completed,
                        onChanged: (value) =>
                            update(() => completed = value == true),
                        title: const Text(
                          'The actual home check is completed and I reviewed its evidence',
                        ),
                      ),
                    ],
                    TextFormField(
                      controller: reference,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Actual booking/check evidence reference',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'Enter the actual reference'
                          : null,
                    ),
                    TextFormField(
                      controller: notes,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Notes shown to owner',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate() || offer && !completed) {
                  return;
                }
                Navigator.pop(dialog, {
                  'action': offer ? 'offer_fee' : 'confirm',
                  'reference': reference.text.trim(),
                  'notes': notes.text.trim(),
                  if (offer) ...{
                    'feeBps': _fee(fee.text),
                    'effectiveFrom': day.text.trim(),
                    'checkCompleted': true,
                  } else ...{
                    'managerName': manager.text.trim(),
                    'managerPhone': phone.text.trim(),
                    'day': day.text.trim(),
                    'slot': slot,
                  },
                });
              },
              child: const Text('Record actual details'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [reference, notes, manager, phone, fee, day]) {
      controller.dispose();
    }
    if (input == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await gateway.recordCheck(property, input);
      if (mounted) await _load();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'The update was not confirmed. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int? _fee(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final bps =
        int.parse(parts[0]) * 100 +
        int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
    return bps >= 500 && bps <= 2000 ? bps : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Owner property checks'),
      actions: [
        IconButton(
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.error)),
        if (records?.isEmpty == true)
          const Text('No owner property requests yet.'),
        for (final property in records ?? <OwnerPropertyRecord>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(property.details['address'] as String),
                  Text('Status · ${property.status.replaceAll('_', ' ')}'),
                  if (property.data['check'] is Map)
                    Text(
                      '${property.data['check']['day']} · ${property.data['check']['slot']} · ${property.data['check']['method']}',
                    ),
                  if (property.data['feeOffer'] is Map)
                    Text(
                      'Offered fee · ${(property.data['feeOffer']['feeBps'] as int) / 100}% · from ${property.data['feeOffer']['effectiveFrom']}',
                    ),
                  if ([
                    'check_requested',
                    'check_confirmed',
                  ].contains(property.status))
                    TextButton(
                      onPressed: busy ? null : () => _record(property, false),
                      child: const Text('Confirm / reschedule actual check'),
                    ),
                  if (property.status == 'check_confirmed')
                    TextButton(
                      onPressed: busy ? null : () => _record(property, true),
                      child: const Text('Record completed check and fee offer'),
                    ),
                  if (!busy)
                    OwnerPropertyAdminActions(
                      property: property,
                      onChanged: _load,
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
