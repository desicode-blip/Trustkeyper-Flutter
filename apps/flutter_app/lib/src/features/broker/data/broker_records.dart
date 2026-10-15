import 'broker_property_repository.dart';
import 'broker_repository.dart';

class BrokerPropertyRecord {
  const BrokerPropertyRecord({
    required this.id,
    required this.name,
    required this.agreements,
    this.property,
  });
  final String id;
  final String name;
  final BrokerProperty? property;
  final List<BrokerAgreementSummary> agreements;
  String get rooms => property?.rooms ?? '';
  String get state =>
      agreements.any((agreement) => agreement.status == 'active')
      ? 'Rented'
      : agreements.any(
          (agreement) => ![
            'cancelled',
            'terminated',
            'completed',
          ].contains(agreement.status),
        )
      ? 'Agreement pending'
      : 'No active agreement';
}

class BrokerPersonRecord {
  BrokerPersonRecord({
    required this.key,
    required this.role,
    required this.name,
    required this.phone,
    required this.email,
    required this.links,
  });
  final String key;
  final String role;
  final String name;
  final String phone;
  final String email;
  final List<({BrokerAgreementSummary agreement, Map<String, dynamic> person})>
  links;
  int get propertyCount => links
      .map(
        (link) => link.agreement.propertyId ?? 'agreement:${link.agreement.id}',
      )
      .toSet()
      .length;
}

List<BrokerPropertyRecord> brokerPropertyRecords(
  List<BrokerProperty> properties,
  List<BrokerAgreementSummary> agreements,
) {
  final byProperty = <String, List<BrokerAgreementSummary>>{};
  for (final agreement in agreements) {
    final id = agreement.propertyId?.isNotEmpty == true
        ? agreement.propertyId!
        : 'agreement:${agreement.id}';
    (byProperty[id] ??= []).add(agreement);
  }
  final result = <BrokerPropertyRecord>[];
  for (final property in properties) {
    result.add(
      BrokerPropertyRecord(
        id: property.id,
        name: property.displayName,
        property: property,
        agreements: byProperty.remove(property.id) ?? const [],
      ),
    );
  }
  for (final entry in byProperty.entries) {
    result.add(
      BrokerPropertyRecord(
        id: entry.key,
        name: entry.value.first.property,
        agreements: entry.value,
      ),
    );
  }
  result.sort(
    (left, right) =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase()),
  );
  return result;
}

List<BrokerPersonRecord> brokerPersonRecords(
  List<BrokerAgreementSummary> agreements,
  String role,
) {
  if (!['owner', 'tenant'].contains(role)) {
    throw ArgumentError('Choose owners or tenants.');
  }
  final grouped =
      <
        String,
        List<({BrokerAgreementSummary agreement, Map<String, dynamic> person})>
      >{};
  for (final agreement in agreements) {
    final people = agreement.details[role == 'owner' ? 'owners' : 'tenants'];
    if (people is! List) {
      continue;
    }
    for (var index = 0; index < people.length; index++) {
      if (people[index] is! Map) {
        continue;
      }
      final person = Map<String, dynamic>.from(people[index] as Map);
      final phone = (person['phone'] as String? ?? '').replaceAll(
        RegExp(r'[\s()-]'),
        '',
      );
      final key = phone.isNotEmpty
          ? '$role:$phone'
          : '$role:${agreement.id}:${person['id'] ?? index}';
      (grouped[key] ??= []).add((agreement: agreement, person: person));
    }
  }
  final result = grouped.entries.map((entry) {
    final person = entry.value.first.person;
    return BrokerPersonRecord(
      key: entry.key,
      role: role,
      name: (person['name'] as String? ?? '').trim().isEmpty
          ? 'Unnamed $role'
          : person['name'] as String,
      phone: person['phone'] as String? ?? '',
      email: person['email'] as String? ?? '',
      links: entry.value,
    );
  }).toList();
  result.sort(
    (left, right) =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase()),
  );
  return result;
}
