import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/session_bound_screen.dart';
import '../../document_requests/data/document_request_repository.dart';
import '../data/agreement_draft.dart';
import 'private_documents_screen.dart';
import '../data/broker_property_repository.dart';
import '../data/broker_records.dart';
import '../data/broker_repository.dart';

class BrokerRecordsScreen extends StatefulWidget {
  const BrokerRecordsScreen({
    required this.agreements,
    required this.properties,
    required this.onAddProperty,
    required this.onOpenAgreement,
    required this.onPhotoChecks,
    this.onUpdates,
    this.documents,
    this.identities,
    this.expectedUid,
    this.watchDetailAgreements,
    this.watchDetailProperties,
    super.key,
  });
  final Stream<List<BrokerAgreementSummary>> agreements;
  final Stream<List<BrokerProperty>> properties;
  final VoidCallback? onAddProperty;
  final ValueChanged<BrokerAgreementSummary> onOpenAgreement;
  final void Function(String propertyId, String? agreementId) onPhotoChecks;
  final VoidCallback? onUpdates;
  final DocumentRequests? documents;
  final Stream<String?>? identities;
  final String? expectedUid;
  final Stream<List<BrokerAgreementSummary>> Function()? watchDetailAgreements;
  final Stream<List<BrokerProperty>> Function()? watchDetailProperties;
  @override
  State<BrokerRecordsScreen> createState() => _BrokerRecordsScreenState();
}

class _BrokerRecordsScreenState extends State<BrokerRecordsScreen> {
  int tab = 0;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget _avatar(String name, {bool property = false}) => CircleAvatar(
    radius: 22,
    backgroundColor: AppColors.primarySoft,
    foregroundColor: AppColors.primaryDark,
    child: property
        ? const Icon(Icons.apartment_outlined, size: 22)
        : Text(
            name
                .split(RegExp(r'\s+'))
                .where((part) => part.isNotEmpty)
                .take(2)
                .map((part) => part[0])
                .join()
                .toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
  );
  Widget _pill(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: value == 'Rented'
          ? AppColors.successSoft
          : value == 'Agreement pending'
          ? AppColors.warningSoft
          : AppColors.surfaceMuted,
    ),
    child: Text(
      value,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: value == 'Rented'
            ? AppColors.success
            : value == 'Agreement pending'
            ? AppColors.warning
            : AppColors.muted,
      ),
    ),
  );
  void _detail(
    Widget Function(List<BrokerAgreementSummary>) builder,
    List<BrokerAgreementSummary> initial,
  ) {
    final stream = widget.watchDetailAgreements?.call();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) {
          final child = stream == null
              ? builder(initial)
              : StreamBuilder<List<BrokerAgreementSummary>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Scaffold(
                        appBar: AppBar(),
                        body: const Center(
                          child: Text(
                            'This private record is unavailable. Reopen Records to retry.',
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return builder(snapshot.data!);
                  },
                );
          return widget.identities == null
              ? child
              : SessionBoundScreen(
                  users: widget.identities,
                  initialUid: widget.expectedUid,
                  expectedUid: widget.expectedUid,
                  onSessionEnded: () {
                    final route = ModalRoute.of(routeContext);
                    if (route != null && route.isActive) {
                      Navigator.of(
                        routeContext,
                      ).popUntil((candidate) => candidate == route);
                    }
                  },
                  child: child,
                );
        },
      ),
    );
  }

  void _openPerson(BrokerPersonRecord person) => _detail((agreements) {
    final matches = brokerPersonRecords(
      agreements,
      person.role,
    ).where((candidate) => candidate.key == person.key);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('This person is no longer in your records.'),
        ),
      );
    }
    return BrokerPersonRecordScreen(
      person: matches.single,
      documents: widget.documents,
      onOpenAgreement: widget.onOpenAgreement,
      onPhotoChecks: widget.onPhotoChecks,
    );
  }, person.links.map((link) => link.agreement).toList());
  void _openProperty(BrokerPropertyRecord property) {
    final changes = widget.watchDetailProperties?.call();
    Widget detail(
      List<BrokerAgreementSummary> agreements,
      List<BrokerProperty> properties,
    ) {
      final matches = brokerPropertyRecords(
        properties,
        agreements,
      ).where((record) => record.id == property.id);
      if (matches.isEmpty) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text('This property is no longer in your records.'),
          ),
        );
      }
      return BrokerPropertyRecordScreen(
        record: matches.single,
        onOpenAgreement: widget.onOpenAgreement,
        onPhotoChecks: widget.onPhotoChecks,
        onPerson: _openPerson,
      );
    }

    _detail(
      (agreements) => changes == null
          ? detail(
              agreements,
              property.property == null ? [] : [property.property!],
            )
          : StreamBuilder<List<BrokerProperty>>(
              stream: changes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Scaffold(
                    appBar: AppBar(),
                    body: const Center(
                      child: Text(
                        'This property is unavailable. Reopen Records to retry.',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return detail(agreements, snapshot.data!);
              },
            ),
      property.agreements,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<BrokerAgreementSummary>>(
    stream: widget.agreements,
    builder: (context, agreements) => StreamBuilder<List<BrokerProperty>>(
      stream: widget.properties,
      builder: (context, properties) {
        final loading = !agreements.hasData || !properties.hasData;
        final failed = agreements.hasError || properties.hasError;
        final query = search.text.trim().toLowerCase();
        final records = brokerPropertyRecords(
          properties.data ?? const [],
          agreements.data ?? const [],
        );
        final people = tab == 0
            ? <BrokerPersonRecord>[]
            : brokerPersonRecords(
                agreements.data ?? const [],
                tab == 1 ? 'owner' : 'tenant',
              );
        final filteredProperties = records
            .where(
              (record) => '${record.name} ${record.rooms}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList();
        final filteredPeople = people
            .where(
              (person) => '${person.name} ${person.phone} ${person.email}'
                  .toLowerCase()
                  .contains(query),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Records',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: widget.onUpdates,
                  icon: const Icon(Icons.notifications_none),
                  tooltip: 'Updates',
                ),
              ],
            ),
            const Text(
              'Your properties and people',
              style: TextStyle(fontSize: 17, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        tab = index;
                        search.clear();
                      }),
                      borderRadius: BorderRadius.circular(24),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: tab == index ? Colors.white : null,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: tab == index
                              ? [
                                  BoxShadow(
                                    color: AppColors.heading.withValues(
                                      alpha: .08,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          ['Properties', 'Owners', 'Tenants'][index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: tab == index
                                ? AppColors.primaryDark
                                : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search ${['property', 'owner', 'tenant'][tab]}',
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 14),
            if (failed)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Records could not be loaded. Check your connection and reopen this tab.',
                ),
              )
            else if (loading)
              const LinearProgressIndicator()
            else if (tab == 0) ...[
              for (final record in filteredProperties)
                Column(
                  children: [
                    InkWell(
                      onTap: () => _openProperty(record),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            _avatar('', property: true),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (record.rooms.isNotEmpty)
                                    Text(
                                      record.rooms,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _pill(record.state),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              if (filteredProperties.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    query.isEmpty
                        ? 'No properties yet'
                        : 'No properties match your search',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: widget.onAddProperty,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add property'),
              ),
            ] else ...[
              for (final person in filteredPeople)
                Column(
                  children: [
                    InkWell(
                      onTap: () => _openPerson(person),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            _avatar(person.name),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${person.phone} · ${person.propertyCount} ${person.propertyCount == 1 ? 'property' : 'properties'}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              if (filteredPeople.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    query.isEmpty
                        ? 'No ${tab == 1 ? 'owners' : 'tenants'} yet'
                        : 'No people match your search',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class BrokerPropertyRecordScreen extends StatelessWidget {
  const BrokerPropertyRecordScreen({
    required this.record,
    required this.onOpenAgreement,
    required this.onPhotoChecks,
    required this.onPerson,
    super.key,
  });
  final BrokerPropertyRecord record;
  final ValueChanged<BrokerAgreementSummary> onOpenAgreement;
  final void Function(String, String?) onPhotoChecks;
  final ValueChanged<BrokerPersonRecord> onPerson;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(record.name)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Property', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        Text(
          record.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        if (record.property != null)
          Text(
            [
              record.rooms,
              record.property!.furnishing,
            ].where((value) => value.isNotEmpty).join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 17),
          ),
        const SizedBox(height: 20),
        for (final role in ['owner', 'tenant']) ...[
          Text(
            role == 'owner' ? 'Owners' : 'Tenants',
            style: const TextStyle(color: AppColors.muted),
          ),
          for (final person in brokerPersonRecords(record.agreements, role))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(person.name),
              subtitle: Text(person.phone),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onPerson(person),
            ),
          const SizedBox(height: 18),
        ],
        const Text('Agreements', style: TextStyle(color: AppColors.muted)),
        for (final agreement in record.agreements)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(agreement.property),
            subtitle: Text(agreement.status.replaceAll('_', ' ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenAgreement(agreement),
          ),
        if (!record.id.startsWith('agreement:'))
          Card(
            child: ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Photo checks'),
              subtitle: const Text('Room photos and check timeline'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onPhotoChecks(
                record.id,
                record.agreements.isEmpty ? null : record.agreements.first.id,
              ),
            ),
          ),
        if (record.property?.inventory.isNotEmpty == true) ...[
          const SizedBox(height: 18),
          const Text('Inventory', style: TextStyle(color: AppColors.muted)),
          for (final item in record.property!.inventory.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.key),
              trailing: Text('${item.value}'),
            ),
        ],
      ],
    ),
  );
}

class BrokerPersonRecordScreen extends StatelessWidget {
  const BrokerPersonRecordScreen({
    required this.person,
    required this.onOpenAgreement,
    required this.onPhotoChecks,
    this.documents,
    super.key,
  });
  final BrokerPersonRecord person;
  final DocumentRequests? documents;
  final ValueChanged<BrokerAgreementSummary> onOpenAgreement;
  final void Function(String, String?) onPhotoChecks;
  Future<void> _contact(BuildContext context, bool whatsapp) async {
    final phone = person.phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) {
      return;
    }
    final url = whatsapp
        ? Uri.https('wa.me', phone.replaceAll('+', ''))
        : Uri(scheme: 'tel', path: phone);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app could open this contact.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This contact could not be opened.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(person.name)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          person.role == 'owner' ? 'Owner' : 'Tenant',
          style: const TextStyle(color: AppColors.muted),
        ),
        Text(
          person.phone,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (person.email.isNotEmpty)
          Text(person.email, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: person.phone.isEmpty
                    ? null
                    : () => _contact(context, false),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: person.phone.isEmpty
                    ? null
                    : () => _contact(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.successSoft,
                  foregroundColor: AppColors.success,
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('WhatsApp'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Properties (${person.propertyCount})',
          style: const TextStyle(color: AppColors.muted),
        ),
        for (final link in person.links) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.apartment_outlined,
              color: AppColors.primaryDark,
            ),
            title: Text(link.agreement.property),
            subtitle: Text(link.agreement.status.replaceAll('_', ' ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenAgreement(link.agreement),
          ),
          if (documents != null &&
              link.person['id'] is String &&
              link.agreement.revision > 0) ...[
            const Text(
              'Documents for this agreement',
              style: TextStyle(color: AppColors.muted),
            ),
            PrivateDocumentsScreen(
              draft: AgreementDraft.fromMap(
                link.agreement.id,
                link.agreement.details,
              ),
              onlyPartyId: link.person['id'] as String,
              requests: documents,
              embedded: true,
              readOnly: true,
            ),
          ],
          const Divider(height: 28),
        ],
      ],
    ),
  );
}
