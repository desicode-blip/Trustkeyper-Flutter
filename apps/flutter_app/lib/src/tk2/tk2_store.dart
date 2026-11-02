import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/broker/data/broker_property_repository.dart';
import 'tk2_link.dart';

// TrustKeeper 2 – broker MVP. Everything is stored on the phone for now
// (SharedPreferences). The backend plan is in docs/TRUSTKEEPER2.md.

/// A property the broker shows to customers: the house facts plus rent,
/// photos and the visit fee.
class Tk2Listing {
  const Tk2Listing({
    required this.id,
    required this.property,
    this.rent = 0,
    this.deposit = 0,
    this.brokerage = 0,
    this.brokerageDays = 0,
    this.visitDays = 'all',
    this.visitFrom = 7,
    this.visitTo = 23,
    this.availableFrom = '',
    this.photos = const [],
    this.visitFee = 150,
    this.createdAt = 0,
    this.sample = false,
    this.maintenance = 0,
    this.maintenanceIncluded = true,
    this.tenants = 'Anyone',
    this.pets = true,
    this.society = '',
    this.locality = '',
    this.door = '',
    this.ownerName = '',
    this.ownerPhone = '',
    this.keys = '',
    this.note = '',
  });

  // Shown to customers.
  final String society;
  final String locality;

  // Broker only – never in the shared message or customer page.
  final String door;
  final String ownerName;
  final String ownerPhone;

  /// With me · With owner · With security · Lockbox
  final String keys;
  final String note;

  static const maxVisitFee = 500;
  static const keyChoices = ['With me', 'With owner', 'With security', 'Lockbox'];

  /// What customers see as the title: "2 BHK · Sri Sai Residency".
  String get publicTitle => [property.rooms, if (society.trim().isNotEmpty) society.trim() else if (locality.trim().isNotEmpty) locality.trim()].join(' · ');

  /// "Madhapur, Hyderabad" style area line (no door number).
  String get area => locality.trim();

  /// Full address for the broker: door + saved address.
  String get fullAddress => [if (door.trim().isNotEmpty) door.trim(), if (society.trim().isNotEmpty) society.trim(), if (property.address.trim().isNotEmpty) property.address.trim()].join(', ');

  String get brokerageText => brokerage == 0
      ? 'No brokerage'
      : brokerageDays == 15
      ? '15 days rent · ${Tk2Store.money(brokerage)}'
      : brokerageDays == 30
      ? '1 month rent · ${Tk2Store.money(brokerage)}'
      : Tk2Store.money(brokerage);

  String get feeText => visitFee == 0 ? 'Free' : Tk2Store.money(visitFee);

  /// Monthly maintenance; 0 with [maintenanceIncluded] = included in rent.
  final int maintenance;
  final bool maintenanceIncluded;

  /// Family · Bachelors · Anyone
  final String tenants;
  final bool pets;

  final String id;
  final BrokerProperty property;
  final int rent;
  final int deposit;

  /// Brokerage the broker charges the tenant, in ₹ (0 = no brokerage). Customers see it.
  final int brokerage;

  /// Brokerage as part of rent: 15 = half month, 30 = one month; 0 = fixed amount (or none).
  final int brokerageDays;

  /// Brokerage for these days of rent, in ₹ (rent × days ÷ 30).
  static int brokerageFor(int rent, int days) => (rent * days / 30).round();

  /// Visit days: 'all' · 'weekdays' (Mon–Fri) · 'weekends' (Sat, Sun).
  final String visitDays;

  bool dayOpen(DateTime d) {
    final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    return switch (visitDays) {
      'weekdays' => !weekend,
      'weekends' => weekend,
      _ => true,
    };
  }

  /// Who can rent, ticked boxes. "Anyone" = all of them.
  static const tenantTypes = ['Family', 'Bachelor male', 'Bachelor female', 'Companies'];

  /// Ticked types from the saved text ('Anyone' or 'Family, Companies').
  static Set<String> tenantSet(String saved) {
    if (saved == 'Anyone' || saved.trim().isEmpty) return {...tenantTypes};
    final out = <String>{};
    for (final part in saved.split(',').map((e) => e.trim())) {
      if (part == 'Bachelors') {
        out.addAll(['Bachelor male', 'Bachelor female']);
      } else if (tenantTypes.contains(part)) {
        out.add(part);
      }
    }
    return out.isEmpty ? {...tenantTypes} : out;
  }

  /// Tick or untick one box. 'Anyone' ticks or unticks all.
  static Set<String> toggleTenant(Set<String> now, String box) {
    if (box == 'Anyone') return now.length == tenantTypes.length ? <String>{} : {...tenantTypes};
    final next = {...now};
    if (!next.remove(box)) next.add(box);
    return next;
  }

  static String tenantText(Set<String> set) => set.length == tenantTypes.length
      ? 'Anyone'
      : [
          for (final t in tenantTypes)
            if (set.contains(t)) t,
        ].join(', ');

  /// Visit hours the broker/owner is fine with (24h clock, both included). Default 7 am – 11 pm.
  final int visitFrom;
  final int visitTo;

  /// Hours a customer can pick: every hour 7 am – 11 pm.
  static const visitHours = [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];

  /// A slot is open inside the broker's hours. Other bookings never close a slot.
  bool slotOpen(int hour) => hour >= visitFrom && hour <= visitTo;

  /// yyyy-MM-dd, '' = now.
  final String availableFrom;

  /// Local file paths of photos picked on this phone.
  final List<String> photos;

  /// What a customer pays to book a visit (held until the visit happens).
  final int visitFee;
  final int createdAt;

  /// The built-in example shown until the broker adds their own.
  final bool sample;

  String get name => property.displayName;
  bool get hasRent => rent > 0;

  Tk2Listing copyWith({
    BrokerProperty? property,
    int? rent,
    int? deposit,
    int? brokerage,
    int? brokerageDays,
    String? visitDays,
    int? visitFrom,
    int? visitTo,
    String? availableFrom,
    List<String>? photos,
    int? visitFee,
    int? maintenance,
    bool? maintenanceIncluded,
    String? tenants,
    bool? pets,
    String? society,
    String? locality,
    String? door,
    String? ownerName,
    String? ownerPhone,
    String? keys,
    String? note,
  }) => Tk2Listing(
    id: id,
    property: property ?? this.property,
    rent: rent ?? this.rent,
    deposit: deposit ?? this.deposit,
    brokerage: brokerage ?? this.brokerage,
    brokerageDays: brokerageDays ?? this.brokerageDays,
    visitDays: visitDays ?? this.visitDays,
    visitFrom: visitFrom ?? this.visitFrom,
    visitTo: visitTo ?? this.visitTo,
    availableFrom: availableFrom ?? this.availableFrom,
    photos: photos ?? this.photos,
    visitFee: visitFee ?? this.visitFee,
    createdAt: createdAt,
    sample: sample,
    maintenance: maintenance ?? this.maintenance,
    maintenanceIncluded: maintenanceIncluded ?? this.maintenanceIncluded,
    tenants: tenants ?? this.tenants,
    pets: pets ?? this.pets,
    society: society ?? this.society,
    locality: locality ?? this.locality,
    door: door ?? this.door,
    ownerName: ownerName ?? this.ownerName,
    ownerPhone: ownerPhone ?? this.ownerPhone,
    keys: keys ?? this.keys,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'property': property.toMap(),
    'rent': rent,
    'deposit': deposit,
    'brokerage': brokerage,
    'brokerageDays': brokerageDays,
    'visitDays': visitDays,
    'visitFrom': visitFrom,
    'visitTo': visitTo,
    'availableFrom': availableFrom,
    'photos': photos,
    'visitFee': visitFee,
    'createdAt': createdAt,
    'maintenance': maintenance,
    'maintenanceIncluded': maintenanceIncluded,
    'tenants': tenants,
    'pets': pets,
    'society': society,
    'locality': locality,
    'door': door,
    'ownerName': ownerName,
    'ownerPhone': ownerPhone,
    'keys': keys,
    'note': note,
  };

  factory Tk2Listing.fromJson(Map<String, dynamic> json) => Tk2Listing(
    id: json['id'] as String? ?? '',
    property: BrokerProperty.fromMap(json['id'] as String? ?? '', Map<String, dynamic>.from(json['property'] as Map? ?? const {})),
    rent: (json['rent'] as num?)?.toInt() ?? 0,
    deposit: (json['deposit'] as num?)?.toInt() ?? 0,
    brokerage: (json['brokerage'] as num?)?.toInt() ?? 0,
    brokerageDays: (json['brokerageDays'] as num?)?.toInt() ?? 0,
    visitDays: json['visitDays'] as String? ?? 'all',
    visitFrom: (json['visitFrom'] as num?)?.toInt() ?? 7,
    visitTo: (json['visitTo'] as num?)?.toInt() ?? 23,
    availableFrom: json['availableFrom'] as String? ?? '',
    photos: [
      for (final p in (json['photos'] as List? ?? const []))
        if (p is String) p,
    ],
    visitFee: (json['visitFee'] as num?)?.toInt() ?? 150,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    maintenance: (json['maintenance'] as num?)?.toInt() ?? 0,
    maintenanceIncluded: json['maintenanceIncluded'] as bool? ?? true,
    tenants: json['tenants'] as String? ?? 'Anyone',
    pets: json['pets'] as bool? ?? true,
    society: json['society'] as String? ?? '',
    locality: json['locality'] as String? ?? '',
    door: json['door'] as String? ?? '',
    ownerName: json['ownerName'] as String? ?? '',
    ownerPhone: json['ownerPhone'] as String? ?? '',
    keys: json['keys'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );

  /// Rent line for cards: "₹32,000 incl. maintenance" or "₹32,000 + ₹3,000 maintenance".
  String get rentLine {
    if (!hasRent) return 'Add rent';
    final r = Tk2Store.money(rent);
    if (maintenanceIncluded || maintenance == 0) return '$r incl. maintenance';
    return '$r + ${Tk2Store.money(maintenance)} maintenance';
  }

  /// Furnishing as people say it.
  String get furnishingText => switch (property.furnishing) {
    'Empty' || '' => 'Unfurnished',
    'Full' => 'Fully furnished',
    final f => '$f-furnished',
  };

  /// Who can rent and pets, e.g. "Family · No pets".
  String get rules => [if (tenants != 'Anyone') '$tenants only' else 'Anyone can rent', pets ? 'Pets OK' : 'No pets'].join(' · ');

  /// The example everyone sees first.
  static final example = Tk2Listing(
    id: 'sample',
    sample: true,
    rent: 32000,
    deposit: 64000,
    visitFee: 150,
    maintenance: 3000,
    maintenanceIncluded: false,
    tenants: 'Family',
    pets: false,
    society: 'Sri Sai Residency',
    locality: 'Madhapur, Hyderabad',
    door: 'Flat 402, 4th floor',
    ownerName: 'Owner (example)',
    ownerPhone: '+91 90000 00000',
    keys: 'With security',
    note: 'Call the owner a day before visits.',
    property: BrokerProperty(
      id: 'sample',
      name: 'Flat 402, Madhapur',
      address: 'Sri Sai Residency, Madhapur, Hyderabad',
      rooms: '2 BHK',
      floor: 4,
      totalFloors: 7,
      furnishing: 'Semi',
      sizeSqFt: 1150,
      facing: 'East',
      carParking: 1,
      bikeParking: 1,
      inventory: const {'Fan': 4, 'Light': 8, 'AC': 2, 'Geyser': 2, 'Cupboard': 2, 'Bed': 0},
    ),
  );
}

/// booked → done (fee released to the broker)
///        → cancelled / noShow (fee refunded to the customer)
abstract final class VisitStatus {
  static const booked = 'booked';
  static const done = 'done';
  static const cancelled = 'cancelled';
  static const noShow = 'noShow';

  /// Customer cancelled within 5 minutes of booking.
  static const customerCancelled = 'customerCancelled';
}

class Tk2Visit {
  const Tk2Visit({
    required this.id,
    required this.listingId,
    required this.customerName,
    required this.customerPhone,
    required this.at,
    required this.fee,
    required this.code,
    this.status = VisitStatus.booked,
    this.createdAt = 0,
  });

  final String id;
  final String listingId;
  final String customerName;
  final String customerPhone;

  /// Visit time (ms).
  final int at;
  final int fee;

  /// 4 digits the customer shows at the visit. The broker types it to get paid.
  final String code;
  final String status;
  final int createdAt;

  bool get upcoming => status == VisitStatus.booked;

  /// held · released · half (customer did not come) · refunded
  String get feeStatus => switch (status) {
    VisitStatus.done => 'released',
    VisitStatus.noShow => 'half',
    VisitStatus.cancelled || VisitStatus.customerCancelled => 'refunded',
    _ => 'held',
  };

  /// What the broker gets: all after the visit, half if the customer did not come.
  int get brokerShare => switch (status) {
    VisitStatus.done => fee,
    VisitStatus.noShow => fee ~/ 2,
    _ => 0,
  };

  /// What goes back to the customer: all if the broker cancels; 98% if the
  /// customer cancels within 5 minutes; nothing if they did not come.
  int get customerRefund => switch (status) {
    VisitStatus.cancelled => fee,
    VisitStatus.customerCancelled => Tk2Visit.refundAfterFee(fee),
    _ => 0,
  };

  /// Cancel window for the customer: 5 minutes after booking.
  static const cancelWindow = Duration(minutes: 5);

  /// 2% is kept when the customer cancels in time.
  static int refundAfterFee(int fee) => fee - (fee * 2 / 100).round();

  bool customerCanCancel(DateTime now) => upcoming && now.difference(DateTime.fromMillisecondsSinceEpoch(createdAt)) <= cancelWindow;

  Tk2Visit withStatus(String next) =>
      Tk2Visit(id: id, listingId: listingId, customerName: customerName, customerPhone: customerPhone, at: at, fee: fee, code: code, status: next, createdAt: createdAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'listingId': listingId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'at': at,
    'fee': fee,
    'code': code,
    'status': status,
    'createdAt': createdAt,
  };

  factory Tk2Visit.fromJson(Map<String, dynamic> json) => Tk2Visit(
    id: json['id'] as String? ?? '',
    listingId: json['listingId'] as String? ?? '',
    customerName: json['customerName'] as String? ?? '',
    customerPhone: json['customerPhone'] as String? ?? '',
    at: (json['at'] as num?)?.toInt() ?? 0,
    fee: (json['fee'] as num?)?.toInt() ?? 0,
    code: json['code'] as String? ?? '',
    status: json['status'] as String? ?? VisitStatus.booked,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class Tk2Store extends ChangeNotifier {
  Tk2Store._();
  static final instance = Tk2Store._();

  /// For tests: a fresh store.
  @visibleForTesting
  factory Tk2Store.forTest() => Tk2Store._();

  static const _key = 'tk2_store_v1';

  String brokerName = '';
  String brokerPhone = '';
  final List<Tk2Listing> _listings = [];
  final List<Tk2Visit> _visits = [];
  bool _loaded = false;

  /// True right after the broker's first own property replaced the sample.
  bool sampleJustRemoved = false;

  bool get loaded => _loaded;
  bool get hasName => brokerName.trim().isNotEmpty;

  /// Own properties, newest first. Empty → the home shows the example.
  List<Tk2Listing> get listings => List.unmodifiable(_listings);
  List<Tk2Listing> get shown => _listings.isEmpty ? [Tk2Listing.example] : listings;
  List<Tk2Visit> get visits => List.unmodifiable(_visits);

  List<Tk2Visit> get upcoming => _visits.where((v) => v.upcoming).toList()..sort((a, b) => a.at.compareTo(b.at));
  List<Tk2Visit> get past => _visits.where((v) => !v.upcoming).toList()..sort((a, b) => b.at.compareTo(a.at));
  int get heldTotal => _visits.where((v) => v.feeStatus == 'held').fold(0, (sum, v) => sum + v.fee);
  int get releasedTotal => _visits.fold(0, (sum, v) => sum + v.brokerShare);

  Tk2Listing? listing(String id) {
    if (id == Tk2Listing.example.id) return Tk2Listing.example;
    for (final l in _listings) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<Tk2Visit> visitsFor(String listingId) => _visits.where((v) => v.listingId == listingId).toList()..sort((a, b) => b.at.compareTo(a.at));

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        brokerName = json['brokerName'] as String? ?? '';
        brokerPhone = json['brokerPhone'] as String? ?? '';
        _listings
          ..clear()
          ..addAll([
            for (final l in (json['listings'] as List? ?? const []))
              if (l is Map) Tk2Listing.fromJson(Map<String, dynamic>.from(l)),
          ]);
        _visits
          ..clear()
          ..addAll([
            for (final v in (json['visits'] as List? ?? const []))
              if (v is Map) Tk2Visit.fromJson(Map<String, dynamic>.from(v)),
          ]);
      } catch (_) {
        // A broken save starts fresh rather than crashing the app.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'brokerName': brokerName,
        'brokerPhone': brokerPhone,
        'listings': [for (final l in _listings) l.toJson()],
        'visits': [for (final v in _visits) v.toJson()],
      }),
    );
    notifyListeners();
  }

  Future<void> setBroker(String name, String phone) {
    brokerName = name.trim();
    brokerPhone = phone.trim();
    return _save();
  }

  static String _id(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(999)}';

  /// Saves the house facts (from the shared "Add property" screens).
  Future<BrokerProperty> saveProperty(BrokerProperty property) async {
    final id = property.id.isEmpty ? _id('p') : property.id;
    final saved = BrokerProperty(
      id: id,
      name: property.name,
      address: property.address,
      rooms: property.rooms,
      floor: property.floor,
      totalFloors: property.totalFloors,
      furnishing: property.furnishing,
      sizeSqFt: property.sizeSqFt,
      facing: property.facing,
      carParking: property.carParking,
      bikeParking: property.bikeParking,
      flat: property.flat,
      society: property.society,
      area: property.area,
      city: property.city,
      inventory: property.inventory,
    );
    // Address parts feed the listing: flat stays private (door), the rest is public.
    final locality = [property.area, property.city].map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
    final at = _listings.indexWhere((l) => l.id == id);
    if (at >= 0) {
      _listings[at] = _listings[at].copyWith(property: saved, door: property.flat, society: property.society, locality: locality);
    } else {
      sampleJustRemoved = _listings.isEmpty;
      _listings.insert(0, Tk2Listing(id: id, property: saved, door: property.flat, society: property.society, locality: locality, createdAt: DateTime.now().millisecondsSinceEpoch));
    }
    await _save();
    return saved;
  }

  Future<void> saveListing(Tk2Listing listing) async {
    final at = _listings.indexWhere((l) => l.id == listing.id);
    if (at < 0) return;
    _listings[at] = listing;
    await _save();
  }

  Future<void> removeListing(String id) async {
    _listings.removeWhere((l) => l.id == id);
    await _save();
  }

  void clearSampleNotice() => sampleJustRemoved = false;

  /// Customer books a visit and pays (payment is pretend in this build).
  Future<Tk2Visit> bookVisit({required String listingId, required String name, required String phone, required DateTime at}) async {
    final listing = this.listing(listingId);
    final visit = Tk2Visit(
      id: _id('v'),
      listingId: listingId,
      customerName: name.trim(),
      customerPhone: phone.trim(),
      at: at.millisecondsSinceEpoch,
      fee: listing?.visitFee ?? 150,
      code: (1000 + Random().nextInt(9000)).toString(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _visits.add(visit);
    await _save();
    return visit;
  }

  /// Broker confirms the visit with the customer's code → fee released.
  /// Returns false when the code is wrong.
  Future<bool> confirmVisit(String visitId, String code) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0 || _visits[at].code != code.trim()) return false;
    _visits[at] = _visits[at].withStatus(VisitStatus.done);
    await _save();
    return true;
  }

  /// Customer cancels: only within 5 minutes of booking (98% back).
  Future<bool> customerCancel(String visitId, {DateTime? now}) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0 || !_visits[at].customerCanCancel(now ?? DateTime.now())) return false;
    _visits[at] = _visits[at].withStatus(VisitStatus.customerCancelled);
    await _save();
    return true;
  }

  /// Broker cancels (full refund) or the customer did not come (broker gets half).
  Future<void> closeVisit(String visitId, String status) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0) return;
    _visits[at] = _visits[at].withStatus(status);
    await _save();
  }

  /// The share message the broker sends on WhatsApp.
  String shareText(Tk2Listing l) {
    final p = l.property;
    final facts = [p.rooms, l.furnishingText, if (p.sizeSqFt != null) '${p.sizeSqFt!.toStringAsFixed(0)} sft'].join(' · ');
    return [
      '🏠 ${l.publicTitle}',
      if (l.area.isNotEmpty) '📍 ${l.area}',
      facts,
      if (l.hasRent) 'Rent ${l.rentLine}${l.deposit > 0 ? ' · Deposit ${money(l.deposit)}' : ''}',
      if (l.brokerage > 0) 'Brokerage ${money(l.brokerage)}',
      l.rules,
      'Available ${l.availableFrom.isEmpty ? 'now' : 'from ${l.availableFrom}'}',
      '',
      l.visitFee == 0 ? 'See photos and book a visit (free):' : 'See the house and book a visit (${money(l.visitFee)}):',
      tk2PropertyLink(l, brokerName),
      if (brokerName.isNotEmpty) '',
      if (brokerName.isNotEmpty) '– $brokerName${brokerPhone.isNotEmpty ? ', $brokerPhone' : ''}',
    ].join('\n');
  }

  static String money(int v) {
    final s = v.toString();
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }
}

/// Lets the shared "Add property" screens save into TrustKeeper 2.
class Tk2PropertyRepository implements BrokerPropertyRepository {
  Tk2PropertyRepository(this.store);
  final Tk2Store store;

  @override
  Stream<List<BrokerProperty>> watchProperties() => Stream.value([for (final l in store.listings) l.property]);

  @override
  Future<BrokerProperty> save(BrokerProperty property) => store.saveProperty(property);
}
