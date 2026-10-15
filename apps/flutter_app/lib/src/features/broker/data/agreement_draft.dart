int? parseRupeesToPaise(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 100000000) return null;
  return whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

DateTime addCalendarMonths(DateTime date, int months) {
  final target = DateTime(date.year, date.month + months);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(
    target.year,
    target.month,
    date.day > lastDay ? lastDay : date.day,
  );
}

String rupeesInWords(int paise) {
  if (paise < 0) return 'Enter a valid amount';
  const small = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  String words(int amount) {
    if (amount < 20) return small[amount];
    if (amount < 100) {
      return '${tens[amount ~/ 10]}${amount % 10 == 0 ? '' : '-${small[amount % 10]}'}';
    }
    for (final unit in [
      (10000000, 'crore'),
      (100000, 'lakh'),
      (1000, 'thousand'),
      (100, 'hundred'),
    ]) {
      if (amount >= unit.$1) {
        return '${words(amount ~/ unit.$1)} ${unit.$2}${amount % unit.$1 == 0 ? '' : ' ${words(amount % unit.$1)}'}';
      }
    }
    throw StateError('Amount could not be written');
  }

  final whole = paise ~/ 100;
  final fraction = paise % 100;
  final result =
      '${words(whole)} ${whole == 1 ? 'rupee' : 'rupees'}${fraction == 0 ? '' : ' and ${words(fraction)} paise'}';
  return '${result[0].toUpperCase()}${result.substring(1)}';
}

class AgreementParty {
  const AgreementParty({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.rentSharePaise = 0,
    this.depositSharePaise = 0,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final int rentSharePaise;
  final int depositSharePaise;

  String? get validationError {
    if (id.isEmpty || name.trim().length < 2) {
      return 'Enter the full name for every person.';
    }
    if (!RegExp(r'^\+91[1-9]\d{9}$').hasMatch(phone)) {
      return 'Enter a ten-digit Indian phone number for every person.';
    }
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email or leave it empty.';
    }
    if (rentSharePaise < 0 || depositSharePaise < 0) {
      return 'Shares cannot be negative.';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name.trim(),
    'phone': phone,
    'email': email.trim().toLowerCase(),
    'rentSharePaise': rentSharePaise,
    'depositSharePaise': depositSharePaise,
  };

  factory AgreementParty.fromMap(
    Map<String, dynamic> data, {
    required String fallbackId,
  }) => AgreementParty(
    id: data['id'] as String? ?? fallbackId,
    name: data['name'] as String? ?? '',
    phone: data['phone'] as String? ?? '',
    email: data['email'] as String? ?? '',
    rentSharePaise: (data['rentSharePaise'] as num?)?.toInt() ?? 0,
    depositSharePaise: (data['depositSharePaise'] as num?)?.toInt() ?? 0,
  );
}

class AgreementDraft {
  AgreementDraft({
    required this.id,
    required this.propertyAddress,
    required List<AgreementParty> owners,
    required List<AgreementParty> tenants,
    required this.monthlyRentPaise,
    required this.maintenancePaise,
    required this.depositPaise,
    required this.startDate,
    required this.endDate,
    required this.ownerBrokeragePaise,
    required this.tenantBrokeragePaise,
    this.propertyId,
    Map<String, dynamic>? propertyDetails,
    this.rentDueDay = 5,
    this.lockInMonths = 0,
    this.noticeMonths = 1,
    this.revision = 0,
    this.legacySplitTotalPaise,
    this.reviewReturnReason,
    this.renewalSourceId,
  }) : owners = List.unmodifiable(owners),
       tenants = List.unmodifiable(tenants),
       propertyDetails = propertyDetails == null
           ? null
           : Map.unmodifiable(propertyDetails);

  final String id;
  final String propertyAddress;
  final String? propertyId;
  final Map<String, dynamic>? propertyDetails;
  final List<AgreementParty> owners;
  final List<AgreementParty> tenants;
  final int monthlyRentPaise;
  final int maintenancePaise;
  final int depositPaise;
  final DateTime? startDate;
  final DateTime? endDate;
  final int rentDueDay;
  final int lockInMonths;
  final int noticeMonths;
  final int ownerBrokeragePaise;
  final int tenantBrokeragePaise;
  final int revision;
  final int? legacySplitTotalPaise;
  final String? reviewReturnReason;
  final String? renewalSourceId;

  int get brokeragePaise => ownerBrokeragePaise + tenantBrokeragePaise;

  static String? validateParties(List<AgreementParty> parties) {
    if (parties.isEmpty || parties.length > 20) {
      return 'Add between 1 and 20 people.';
    }
    final phones = <String>{};
    final identifiers = <String>{};
    for (final party in parties) {
      if (party.validationError != null) return party.validationError;
      if (!phones.add(party.phone) || !identifiers.add(party.id)) {
        return 'Each person needs a different mobile number.';
      }
    }
    return null;
  }

  String? get moneyError {
    if (monthlyRentPaise <= 0 ||
        monthlyRentPaise > 10000000000 ||
        maintenancePaise < 0 ||
        maintenancePaise > 10000000000 ||
        depositPaise <= 0 ||
        depositPaise > 10000000000) {
      return 'Enter valid rent, maintenance and deposit amounts.';
    }
    if (tenants.any(
      (party) => party.rentSharePaise < 0 || party.depositSharePaise < 0,
    )) {
      return 'Shares cannot be negative.';
    }
    if (tenants.fold(0, (total, party) => total + party.rentSharePaise) !=
        monthlyRentPaise) {
      return 'Tenant rent shares must add up to the monthly rent.';
    }
    if (tenants.fold(0, (total, party) => total + party.depositSharePaise) !=
        depositPaise) {
      return 'Tenant deposit shares must add up to the deposit.';
    }
    return null;
  }

  String? get datesError {
    if (startDate == null || endDate == null || !endDate!.isAfter(startDate!)) {
      return 'Choose valid start and end dates.';
    }
    if (![1, 5, 10].contains(rentDueDay)) return 'Choose rent day 1, 5 or 10.';
    if (lockInMonths < 0 ||
        lockInMonths > 60 ||
        noticeMonths < 1 ||
        noticeMonths > 12) {
      return 'Choose valid lock-in and notice periods.';
    }
    final boundary = endDate!.add(const Duration(days: 1));
    if (addCalendarMonths(startDate!, lockInMonths).isAfter(boundary) ||
        addCalendarMonths(startDate!, noticeMonths).isAfter(boundary)) {
      return 'Lock-in and notice cannot exceed the agreement period.';
    }
    return null;
  }

  String? get validationError {
    if (legacySplitTotalPaise != null) {
      return 'Review the owner and tenant brokerage amounts for this older draft.';
    }
    if (id.isEmpty) {
      return 'Reopen this agreement to restore its draft reference.';
    }
    final ownerError = validateParties(owners);
    if (ownerError != null) return 'Owners: $ownerError';
    final tenantError = validateParties(tenants);
    if (tenantError != null) return 'Tenants: $tenantError';
    if (moneyError != null) return moneyError;
    if (datesError != null) return datesError;
    if (ownerBrokeragePaise < 0 ||
        tenantBrokeragePaise < 0 ||
        brokeragePaise > 10000000000) {
      return 'Enter valid brokerage amounts.';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 2,
    if (renewalSourceId != null) 'renewalSourceId': renewalSourceId,
    'propertyAddress': propertyAddress.trim(),
    if (propertyId != null) 'propertyId': propertyId,
    if (propertyDetails != null) 'propertyDetails': propertyDetails,
    'owners': owners.map((party) => party.toMap()).toList(),
    'tenants': tenants.map((party) => party.toMap()).toList(),
    'owner': owners.first.toMap(),
    'tenant': tenants.first.toMap(),
    'partyNames': [
      ...owners,
      ...tenants,
    ].map((party) => party.name.trim()).toList(),
    'monthlyRentPaise': monthlyRentPaise,
    'monthlyMaintenancePaise': maintenancePaise,
    'securityDepositPaise': depositPaise,
    'startDateISO': startDate?.toIso8601String(),
    'endDateISO': endDate?.toIso8601String(),
    'rentDueDay': rentDueDay,
    'lockInMonths': lockInMonths,
    'noticeMonths': noticeMonths,
    'ownerBrokeragePaise': ownerBrokeragePaise,
    'tenantBrokeragePaise': tenantBrokeragePaise,
    'brokerageFeePaise': brokeragePaise,
    'brokeragePayer': brokeragePaise == 0
        ? 'none'
        : ownerBrokeragePaise == 0
        ? 'tenant'
        : tenantBrokeragePaise == 0
        ? 'owner'
        : 'split',
  };

  factory AgreementDraft.fromMap(String id, Map<String, dynamic> data) {
    List<AgreementParty> parties(String plural, String singular) {
      final values =
          data[plural] as List? ?? [if (data[singular] is Map) data[singular]];
      return [
        for (var index = 0; index < values.length; index++)
          AgreementParty.fromMap(
            Map<String, dynamic>.from(values[index] as Map),
            fallbackId: '$singular-${index + 1}',
          ),
      ];
    }

    int amount(String name) => (data[name] as num?)?.toInt() ?? 0;
    final payer = data['brokeragePayer'];
    final legacyTotal = amount('brokerageFeePaise');
    return AgreementDraft(
      id: id,
      propertyAddress: data['propertyAddress'] as String? ?? '',
      propertyId: data['propertyId'] as String?,
      renewalSourceId: data['renewalSourceId'] as String?,
      propertyDetails: data['propertyDetails'] == null
          ? null
          : Map<String, dynamic>.from(data['propertyDetails'] as Map),
      owners: parties('owners', 'owner'),
      tenants: parties('tenants', 'tenant'),
      monthlyRentPaise: amount('monthlyRentPaise'),
      maintenancePaise: amount('monthlyMaintenancePaise'),
      depositPaise: amount('securityDepositPaise'),
      startDate: DateTime.tryParse(data['startDateISO'] as String? ?? ''),
      endDate: DateTime.tryParse(data['endDateISO'] as String? ?? ''),
      ownerBrokeragePaise: data.containsKey('ownerBrokeragePaise')
          ? amount('ownerBrokeragePaise')
          : payer == 'owner'
          ? legacyTotal
          : 0,
      tenantBrokeragePaise: data.containsKey('tenantBrokeragePaise')
          ? amount('tenantBrokeragePaise')
          : payer == 'tenant'
          ? legacyTotal
          : 0,
      rentDueDay: (data['rentDueDay'] as num?)?.toInt() ?? 5,
      lockInMonths: (data['lockInMonths'] as num?)?.toInt() ?? 0,
      noticeMonths: (data['noticeMonths'] as num?)?.toInt() ?? 1,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      reviewReturnReason: data['reviewReturnReason'] is String
          ? data['reviewReturnReason'] as String
          : null,
      legacySplitTotalPaise:
          payer == 'split' &&
              !data.containsKey('ownerBrokeragePaise') &&
              !data.containsKey('tenantBrokeragePaise') &&
              legacyTotal > 0
          ? legacyTotal
          : null,
    );
  }
}
