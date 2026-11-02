import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/broker/data/broker_property_repository.dart';

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
    this.availableFrom = '',
    this.photos = const [],
    this.visitFee = 150,
    this.createdAt = 0,
    this.sample = false,
    this.maintenance = 0,
    this.maintenanceIncluded = true,
    this.tenants = 'Anyone',
    this.pets = true,
  });

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
    String? availableFrom,
    List<String>? photos,
    int? visitFee,
    int? maintenance,
    bool? maintenanceIncluded,
    String? tenants,
    bool? pets,
  }) => Tk2Listing(
    id: id,
    property: property ?? this.property,
    rent: rent ?? this.rent,
    deposit: deposit ?? this.deposit,
    availableFrom: availableFrom ?? this.availableFrom,
    photos: photos ?? this.photos,
    visitFee: visitFee ?? this.visitFee,
    createdAt: createdAt,
    sample: sample,
    maintenance: maintenance ?? this.maintenance,
    maintenanceIncluded: maintenanceIncluded ?? this.maintenanceIncluded,
    tenants: tenants ?? this.tenants,
    pets: pets ?? this.pets,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'property': property.toMap(),
    'rent': rent,
    'deposit': deposit,
    'availableFrom': availableFrom,
    'photos': photos,
    'visitFee': visitFee,
    'createdAt': createdAt,
    'maintenance': maintenance,
    'maintenanceIncluded': maintenanceIncluded,
    'tenants': tenants,
    'pets': pets,
  };

  factory Tk2Listing.fromJson(Map<String, dynamic> json) => Tk2Listing(
    id: json['id'] as String? ?? '',
    property: BrokerProperty.fromMap(
      json['id'] as String? ?? '',
      Map<String, dynamic>.from(json['property'] as Map? ?? const {}),
    ),
    rent: (json['rent'] as num?)?.toInt() ?? 0,
    deposit: (json['deposit'] as num?)?.toInt() ?? 0,
    availableFrom: json['availableFrom'] as String? ?? '',
    photos: [for (final p in (json['photos'] as List? ?? const [])) if (p is String) p],
    visitFee: (json['visitFee'] as num?)?.toInt() ?? 150,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    maintenance: (json['maintenance'] as num?)?.toInt() ?? 0,
    maintenanceIncluded: json['maintenanceIncluded'] as bool? ?? true,
    tenants: json['tenants'] as String? ?? 'Anyone',
    pets: json['pets'] as bool? ?? true,
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
  String get rules => [if (tenants != 'Anyone') '$tenants only' else 'Family or bachelors', pets ? 'Pets OK' : 'No pets'].join(' · ');

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

  /// held · released · refunded
  String get feeStatus => switch (status) {
    VisitStatus.done => 'released',
    VisitStatus.cancelled || VisitStatus.noShow => 'refunded',
    _ => 'held',
  };

  Tk2Visit withStatus(String next) => Tk2Visit(
    id: id,
    listingId: listingId,
    customerName: customerName,
    customerPhone: customerPhone,
    at: at,
    fee: fee,
    code: code,
    status: next,
    createdAt: createdAt,
  );

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
  int get releasedTotal => _visits.where((v) => v.feeStatus == 'released').fold(0, (sum, v) => sum + v.fee);

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
          ..addAll([for (final l in (json['listings'] as List? ?? const [])) if (l is Map) Tk2Listing.fromJson(Map<String, dynamic>.from(l))]);
        _visits
          ..clear()
          ..addAll([for (final v in (json['visits'] as List? ?? const [])) if (v is Map) Tk2Visit.fromJson(Map<String, dynamic>.from(v))]);
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
      inventory: property.inventory,
    );
    final at = _listings.indexWhere((l) => l.id == id);
    if (at >= 0) {
      _listings[at] = _listings[at].copyWith(property: saved);
    } else {
      sampleJustRemoved = _listings.isEmpty;
      _listings.insert(0, Tk2Listing(id: id, property: saved, createdAt: DateTime.now().millisecondsSinceEpoch));
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

  /// Broker cancels, or the customer did not come → fee refunded.
  Future<void> closeVisit(String visitId, String status) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0) return;
    _visits[at] = _visits[at].withStatus(status);
    await _save();
  }

  /// The share message the broker sends on WhatsApp.
  String shareText(Tk2Listing l) {
    final p = l.property;
    final facts = [
      p.rooms,
      l.furnishingText,
      if (p.sizeSqFt != null) '${p.sizeSqFt!.toStringAsFixed(0)} sft',
    ].join(' · ');
    return [
      '🏠 ${l.name}',
      if (p.address.trim().isNotEmpty && p.address.trim() != l.name) p.address.trim(),
      facts,
      if (l.hasRent) 'Rent ${l.rentLine}${l.deposit > 0 ? ' · Deposit ${money(l.deposit)}' : ''}',
      l.rules,
      'Available ${l.availableFrom.isEmpty ? 'now' : 'from ${l.availableFrom}'}',
      '',
      'See photos and book a visit (${money(l.visitFee)}, refunded if the visit does not happen):',
      shareLink(l),
      if (brokerName.isNotEmpty) '',
      if (brokerName.isNotEmpty) '– $brokerName${brokerPhone.isNotEmpty ? ', $brokerPhone' : ''}',
    ].join('\n');
  }

  static String shareLink(Tk2Listing l) => 'https://trustkeyper.com/v/${l.id}';

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
  Stream<List<BrokerProperty>> watchProperties() =>
      Stream.value([for (final l in store.listings) l.property]);

  @override
  Future<BrokerProperty> save(BrokerProperty property) => store.saveProperty(property);
}
