import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/broker/data/broker_property_repository.dart';
import 'tk2_cloud.dart';
import 'tk2_deal.dart';
import 'tk2_link.dart';
import 'tk2_sync.dart';

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
    this.brokeragePayer = 'None',
    this.ownerBrokerage = 0,
    this.visitDays = 'all',
    this.visitFrom = 7,
    this.visitTo = 23,
    this.availableFrom = '',
    this.photos = const [],
    this.visitFee = 150,
    this.token = 0,
    this.createdAt = 0,
    this.sample = false,
    this.maintenance = 0,
    this.maintenanceIncluded = true,
    this.rentNegotiable = false,
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
  String get fullAddress => [
    if (door.trim().isNotEmpty) door.trim(),
    if (society.trim().isNotEmpty) society.trim(),
    if (property.address.trim().isNotEmpty) property.address.trim(),
  ].join(', ');

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

  /// Broker ticked "Rent is negotiable" (shown to customers).
  final bool rentNegotiable;

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

  /// Who pays the broker: Owner · Tenant · Both · None (same as the main app).
  final String brokeragePayer;

  /// Owner's part, in ₹. Private: never shown to customers. [brokerage] is the tenant's part.
  final int ownerBrokerage;

  /// Brokerage for these days of rent, in ₹ (rent × days ÷ 30).
  static int brokerageFor(int rent, int days) => (rent * days / 30).round();

  /// 15 or 30 when the tenant's brokerage is half or one month rent, else 0.
  static int daysFor(int rent, int amount) => rent > 0 && amount == rent
      ? 30
      : rent > 0 && amount == brokerageFor(rent, 15)
      ? 15
      : 0;

  /// Visit days: 'all', or the days picked as weekday numbers "1,3,5" (1 = Mon … 7 = Sun).
  /// Older saves 'weekdays' / 'weekends' still read correctly.
  final String visitDays;

  static const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static Set<int> visitDaySet(String saved) => switch (saved.trim()) {
    '' || 'all' => {1, 2, 3, 4, 5, 6, 7},
    'weekdays' => {1, 2, 3, 4, 5},
    'weekends' => {6, 7},
    final s => {for (final p in s.split(',')) ?int.tryParse(p.trim())}.where((d) => d >= 1 && d <= 7).toSet(),
  };

  /// Saved form: 'all' when every day is picked.
  static String visitDayText(Set<int> days) => days.length == 7 ? 'all' : (days.toList()..sort()).join(',');

  /// Tap a day card. "Every day" (0) picks or clears all; picking all 7 = Every day.
  static Set<int> toggleVisitDay(Set<int> now, int day) {
    if (day == 0) return now.length == 7 ? <int>{} : {1, 2, 3, 4, 5, 6, 7};
    final next = {...now};
    if (!next.remove(day)) next.add(day);
    return next;
  }

  bool dayOpen(DateTime d) => visitDaySet(visitDays).contains(d.weekday);

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

  /// What cards show: "Anyone can rent", or e.g. "Family, Bachelor" (male + female = Bachelor). No "only".
  static String tenantLabel(String saved) {
    if (saved == 'Anyone' || saved.trim().isEmpty) return 'Anyone can rent';
    final set = tenantSet(saved);
    if (set.length == tenantTypes.length) return 'Anyone can rent';
    final both = set.contains('Bachelor male') && set.contains('Bachelor female');
    return [
      for (final t in tenantTypes)
        if (set.contains(t) && !(both && t == 'Bachelor female')) both && t == 'Bachelor male' ? 'Bachelor' : t,
    ].join(', ');
  }

  String get tenantsLabel => tenantLabel(tenants);

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

  /// Customers book at least this long ahead.
  static const visitLead = Duration(hours: 1);

  /// Earliest time a customer can pick on [day] (any minute, e.g. 4:35 pm),
  /// or null when the day is closed. Window: visitFrom:00 – visitTo:00.
  DateTime? earliestVisit(DateTime day, DateTime now) {
    final d = DateTime(day.year, day.month, day.day);
    if (!dayOpen(d)) return null;
    var start = d.add(Duration(hours: visitFrom));
    final end = d.add(Duration(hours: visitTo));
    final soonest = now.add(visitLead);
    if (soonest.isAfter(start)) {
      // Round up to the next 5 minutes so the wheel starts on a tidy time.
      final m = (soonest.minute + 4) ~/ 5 * 5;
      start = DateTime(soonest.year, soonest.month, soonest.day, soonest.hour).add(Duration(minutes: m));
    }
    return start.isAfter(end) ? null : start;
  }

  /// Latest time on [day] (visitTo:00).
  DateTime latestVisit(DateTime day) => DateTime(day.year, day.month, day.day, visitTo);

  /// A picked time is fine: inside the window and not too soon.
  bool visitTimeOk(DateTime at, DateTime now) {
    final first = earliestVisit(at, now);
    return first != null && !at.isBefore(first) && !at.isAfter(latestVisit(at));
  }

  /// yyyy-MM-dd, '' = now.
  final String availableFrom;

  /// Local file paths of photos picked on this phone.
  final List<String> photos;

  /// What a customer pays to book a visit (held until the visit happens).
  final int visitFee;

  /// Token the tenant pays to block the house. 0 = not set yet (the broker's default is used).
  final int token;
  final int createdAt;

  /// This property's token, or [fallback] (the broker's default) when not set.
  int tokenOr(int fallback) => token > 0 ? token : fallback;

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
    String? brokeragePayer,
    int? ownerBrokerage,
    String? visitDays,
    int? visitFrom,
    int? visitTo,
    String? availableFrom,
    List<String>? photos,
    int? visitFee,
    int? token,
    int? maintenance,
    bool? maintenanceIncluded,
    bool? rentNegotiable,
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
    brokeragePayer: brokeragePayer ?? this.brokeragePayer,
    ownerBrokerage: ownerBrokerage ?? this.ownerBrokerage,
    visitDays: visitDays ?? this.visitDays,
    visitFrom: visitFrom ?? this.visitFrom,
    visitTo: visitTo ?? this.visitTo,
    availableFrom: availableFrom ?? this.availableFrom,
    photos: photos ?? this.photos,
    visitFee: visitFee ?? this.visitFee,
    token: token ?? this.token,
    createdAt: createdAt,
    sample: sample,
    maintenance: maintenance ?? this.maintenance,
    maintenanceIncluded: maintenanceIncluded ?? this.maintenanceIncluded,
    rentNegotiable: rentNegotiable ?? this.rentNegotiable,
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
    'brokeragePayer': brokeragePayer,
    'ownerBrokerage': ownerBrokerage,
    'visitDays': visitDays,
    'visitFrom': visitFrom,
    'visitTo': visitTo,
    'availableFrom': availableFrom,
    'photos': photos,
    'visitFee': visitFee,
    'token': token,
    'createdAt': createdAt,
    'maintenance': maintenance,
    'maintenanceIncluded': maintenanceIncluded,
    'rentNegotiable': rentNegotiable,
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
    brokeragePayer: json['brokeragePayer'] as String? ?? ((json['brokerage'] as num? ?? 0) > 0 ? 'Tenant' : 'None'),
    ownerBrokerage: (json['ownerBrokerage'] as num?)?.toInt() ?? 0,
    visitDays: json['visitDays'] as String? ?? 'all',
    visitFrom: (json['visitFrom'] as num?)?.toInt() ?? 7,
    visitTo: (json['visitTo'] as num?)?.toInt() ?? 23,
    availableFrom: json['availableFrom'] as String? ?? '',
    photos: [
      for (final p in (json['photos'] as List? ?? const []))
        if (p is String) p,
    ],
    visitFee: (json['visitFee'] as num?)?.toInt() ?? 150,
    token: (json['token'] as num?)?.toInt() ?? 0,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    maintenance: (json['maintenance'] as num?)?.toInt() ?? 0,
    maintenanceIncluded: json['maintenanceIncluded'] as bool? ?? true,
    rentNegotiable: json['rentNegotiable'] as bool? ?? false,
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
    final line = maintenanceIncluded || maintenance == 0 ? '$r incl. maintenance' : '$r + ${Tk2Store.money(maintenance)} maintenance';
    return rentNegotiable ? '$line · negotiable' : line;
  }

  /// Furnishing as people say it.
  String get furnishingText => switch (property.furnishing) {
    'Empty' || '' => 'Unfurnished',
    'Full' => 'Fully furnished',
    final f => '$f-furnished',
  };

  /// Who can rent and pets, e.g. "Family · No pets".
  String get rules => [tenantsLabel, pets ? 'Pets OK' : 'No pets'].join(' · ');

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

  /// Customer cancelled within 5 minutes of booking (98% back).
  static const customerCancelled = 'customerCancelled';

  /// Customer cancelled after 5 minutes: no refund. The broker was told in
  /// advance, so he gets nothing; TrustKeyper keeps the fee.
  static const customerCancelledLate = 'customerCancelledLate';
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
    this.gatePass = '',
    this.customerUid = '',
    this.changedAt = 0,
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

  /// Gate pass the broker uploaded (file path / URL). The backend sends it to
  /// the customer on WhatsApp. Empty = not added yet.
  final String gatePass;

  /// Backend: the customer's login, so a deal can be started for them.
  final String customerUid;

  /// When the status last changed (ms); 0 = never (still booked, or older data).
  final int changedAt;

  /// When the visit ended (done, cancelled…), for payments and notifications.
  int get endedAt => changedAt > 0 ? changedAt : (status == VisitStatus.done || status == VisitStatus.noShow ? at : createdAt);

  bool get upcoming => status == VisitStatus.booked;

  /// held · released · half (customer did not come) · refunded · kept (late cancel)
  String get feeStatus => switch (status) {
    VisitStatus.done => 'released',
    VisitStatus.noShow => 'half',
    VisitStatus.customerCancelledLate => 'kept',
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
  /// customer cancels within 5 minutes; nothing if they cancel later or did not come.
  int get customerRefund => switch (status) {
    VisitStatus.cancelled => fee,
    VisitStatus.customerCancelled => Tk2Visit.refundAfterFee(fee),
    _ => 0,
  };

  /// Cancel window for the customer: 5 minutes after booking.
  static const cancelWindow = Duration(minutes: 5);

  /// 2% is kept when the customer cancels in time.
  static int refundAfterFee(int fee) => fee - (fee * 2 / 100).round();

  /// Within 5 minutes of booking: cancelling gives 98% back. After that the
  /// customer can still cancel, with no refund.
  bool inRefundWindow(DateTime now) => now.difference(DateTime.fromMillisecondsSinceEpoch(createdAt)) <= cancelWindow;

  /// The visit code works from 24 hours before to 24 hours after the visit time.
  static const codeWindow = Duration(hours: 24);

  bool codeWorks(DateTime now) {
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    return !now.isBefore(t.subtract(codeWindow)) && !now.isAfter(t.add(codeWindow));
  }

  Tk2Visit withStatus(String next, {DateTime? now}) => _copy(status: next, changedAt: (now ?? DateTime.now()).millisecondsSinceEpoch);

  Tk2Visit _copy({String? status, String? gatePass, String? code, int? changedAt}) => Tk2Visit(
    id: id,
    listingId: listingId,
    customerName: customerName,
    customerPhone: customerPhone,
    at: at,
    fee: fee,
    code: code ?? this.code,
    status: status ?? this.status,
    createdAt: createdAt,
    gatePass: gatePass ?? this.gatePass,
    customerUid: customerUid,
    changedAt: changedAt ?? this.changedAt,
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
    'gatePass': gatePass,
    'customerUid': customerUid,
    'changedAt': changedAt,
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
    gatePass: json['gatePass'] as String? ?? '',
    customerUid: json['customerUid'] as String? ?? '',
    changedAt: (json['changedAt'] as num?)?.toInt() ?? 0,
  );
}

/// A property taken off the market (rented out, tie-up ended…). It is kept,
/// and the broker is reminded 10 months later to check if it is free again.
class Tk2Inactive {
  const Tk2Inactive({required this.reason, required this.since, required this.remindAt, this.note = '', this.rentStart});

  final String reason;
  final String note;

  /// When the broker turned it off (ms).
  final int since;

  /// Rent start date when it was rented out (ms); the 10 months count from here.
  final int? rentStart;

  /// When to remind the broker (ms).
  final int remindAt;

  static const reasons = [
    'Rented out by me',
    'Rented out by someone else',
    'Owner cancelled the tie-up',
    'Owner is using it',
    'Being sold or repaired',
    'Other reason',
  ];

  /// Set by the app when a tenant pays the token (not in the broker's list of reasons).
  static const blocked = 'Blocked with a token';

  static bool isRented(String reason) => reason.startsWith('Rented out');

  /// Same day, 10 months later (end of month when the day does not exist).
  static DateTime tenMonthsAfter(DateTime d) {
    final last = DateTime(d.year, d.month + 11, 0).day;
    return DateTime(d.year, d.month + 10, d.day > last ? last : d.day, d.hour, d.minute);
  }

  bool due(DateTime now) => !now.isBefore(DateTime.fromMillisecondsSinceEpoch(remindAt));

  Tk2Inactive remindLater(DateTime now) =>
      Tk2Inactive(reason: reason, note: note, since: since, rentStart: rentStart, remindAt: tenMonthsAfter(now).millisecondsSinceEpoch);

  Map<String, Object?> toJson() => {'reason': reason, 'note': note, 'since': since, 'rentStart': rentStart, 'remindAt': remindAt};

  factory Tk2Inactive.fromJson(Map<String, dynamic> j) => Tk2Inactive(
    reason: j['reason'] as String? ?? '',
    note: j['note'] as String? ?? '',
    since: (j['since'] as num?)?.toInt() ?? 0,
    rentStart: (j['rentStart'] as num?)?.toInt(),
    remindAt: (j['remindAt'] as num?)?.toInt() ?? 0,
  );
}

class Tk2Store extends ChangeNotifier {
  Tk2Store._();
  static final instance = Tk2Store._();

  /// For tests: a fresh store.
  @visibleForTesting
  factory Tk2Store.forTest() => Tk2Store._();

  static const _key = 'tk2_store_v1';

  /// Backend sync (null in the demo build and in tests). Set by the app at start.
  Tk2Sync? sync;

  String brokerName = '';
  String brokerPhone = '';

  /// Token the broker usually asks for. Filled in for every new property
  /// (each property can change it). Set at sign-up and in Profile.
  int defaultToken = defaultTokenStart;

  /// The broker has chosen his usual token (with his first property, or in
  /// Profile). Until then the property form asks for it in full.
  bool tokenSet = false;
  static const defaultTokenStart = 15000;
  static const maxToken = 999999;

  /// People the broker has sent properties to (name, phone).
  final List<({String name, String phone, String email})> _contacts = [];
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
    for (final l in _listings) {
      if (l.id == id) return l;
    }
    return id == Tk2Listing.example.id ? Tk2Listing.example : null;
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
        _contacts
          ..clear()
          ..addAll([
            for (final c in (json['contacts'] as List? ?? const []))
              if (c is Map) (name: c['name'] as String? ?? '', phone: c['phone'] as String? ?? '', email: c['email'] as String? ?? ''),
          ]);
        brokerPhone = json['brokerPhone'] as String? ?? '';
        defaultToken = (json['defaultToken'] as num?)?.toInt() ?? defaultTokenStart;
        // Older saves chose it at sign-up.
        tokenSet = json['tokenSet'] as bool? ?? brokerName.isNotEmpty;
        _inactive
          ..clear()
          ..addAll({
            for (final e in (json['inactive'] as Map? ?? const {}).entries)
              if (e.value is Map) e.key as String: Tk2Inactive.fromJson(Map<String, dynamic>.from(e.value as Map)),
          });
        account
          ..clear()
          ..addAll(Map<String, dynamic>.from(json['account'] as Map? ?? const {}));
        _listings
          ..clear()
          ..addAll([
            for (final l in (json['listings'] as List? ?? const []))
              if (l is Map) Tk2Listing.fromJson(Map<String, dynamic>.from(l)),
          ]);
        _deals
          ..clear()
          ..addAll([
            for (final d in (json['deals'] as List? ?? const []))
              if (d is Map) Tk2Deal.fromJson(Map<String, dynamic>.from(d)),
          ]);
        playbooks
          ..clear()
          ..addAll({for (final e in (json['playbooks'] as Map? ?? const {}).entries) e.key as String: List<dynamic>.from(e.value as List)});
        _visits
          ..clear()
          ..addAll([
            for (final v in (json['visits'] as List? ?? const []))
              if (v is Map) Tk2Visit.fromJson(Map<String, dynamic>.from(v)),
          ]);
        notesReadBefore = (json['notesReadBefore'] as num?)?.toInt() ?? 0;
        notesRead
          ..clear()
          ..addAll([for (final n in (json['notesRead'] as List? ?? const [])) '$n']);
        notesMuted
          ..clear()
          ..addAll([for (final n in (json['notesMuted'] as List? ?? const [])) '$n']);
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
        'contacts': [
          for (final c in _contacts) {'name': c.name, 'phone': c.phone, 'email': c.email},
        ],
        'brokerPhone': brokerPhone,
        'defaultToken': defaultToken,
        'tokenSet': tokenSet,
        'account': account,
        'inactive': {for (final e in _inactive.entries) e.key: e.value.toJson()},
        'listings': [for (final l in _listings) l.toJson()],
        'visits': [for (final v in _visits) v.toJson()],
        'deals': [for (final d in _deals) d.toJson()],
        'playbooks': playbooks,
        'notesReadBefore': notesReadBefore,
        'notesRead': notesRead.toList(),
        'notesMuted': notesMuted.toList(),
      }),
    );
    notifyListeners();
  }

  // ------------------------------------------------------------------ deals

  final List<Tk2Deal> _deals = [];

  /// Finalised houses (token onwards), newest first.
  List<Tk2Deal> get deals => List.unmodifiable(_deals);
  Tk2Deal? deal(String id) => _deals.where((d) => d.id == id).firstOrNull;
  Tk2Deal? dealFor(String listingId) => _deals.where((d) => d.listingId == listingId && d.ended == null).firstOrNull;

  /// Society move-in steps a broker has written, by society name (lower case).
  /// Reused for every tenant moving into that society.
  final Map<String, List<dynamic>> playbooks = {};

  /// Starts a deal for [tenant] on a house. Money is fixed here from the
  /// listing. [paid] = the tenant has just paid the token (web); the broker
  /// can also start one and the tenant pays from their link.
  Future<Tk2Deal> startDeal(
    Tk2Listing l, {
    required String tenantName,
    required String tenantPhone,
    bool paid = false,
    String tenantUid = '',
    DateTime? now,
  }) async {
    final existing = dealFor(l.id);
    if (existing != null) return existing;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final d = Tk2Deal(
      id: tenantUid.isEmpty ? _id('d') : '${tenantUid}_${l.id}',
      listingId: l.id,
      title: l.publicTitle,
      tenantName: tenantName.trim(),
      tenantPhone: tenantPhone.trim(),
      ownerName: l.ownerName,
      ownerPhone: l.ownerPhone,
      brokerName: brokerName,
      brokerPhone: brokerPhone,
      brokerUid: sync?.brokerUidFor(l.id) ?? '',
      tenantUid: tenantUid,
      token: l.tokenOr(defaultToken),
      rent: l.rent,
      deposit: l.deposit,
      brokerage: l.brokerage,
      ownerBrokerage: l.ownerBrokerage,
      maintenance: l.maintenanceIncluded ? 0 : l.maintenance,
      createdAt: at,
      t: paid ? {'tokenPaid': true, 'tokenAt': at} : null,
    );
    _deals.insert(0, d);
    await _save();
    sync?.createDeal(d);
    await _block(d);
    return d;
  }

  /// A paid token takes the house off the market (shared links stop working);
  /// a broken deal puts it back.
  Future<void> _block(Tk2Deal d) async {
    if (listing(d.listingId) == null || listing(d.listingId)!.sample) return;
    final blocked = d.t['tokenPaid'] == true && d.ended == null;
    if (blocked && isActive(d.listingId)) {
      await deactivate(d.listingId, reason: Tk2Inactive.blocked, note: 'Token paid by ${d.tenantName}');
    } else if (!blocked && inactive(d.listingId)?.reason == Tk2Inactive.blocked) {
      await activate(d.listingId);
    }
  }

  /// Saves what [role] just did on a deal (only that person's part is sent to the backend).
  Future<void> saveDeal(Tk2Deal d, DealRole role) async {
    if (!_deals.contains(d)) _deals.insert(0, d);
    await _save();
    sync?.dealPart(d, role);
    if (role != DealRole.owner) await _block(d);
  }

  /// A deal opened from a link, or arriving from the backend.
  Future<void> putDeal(Tk2Deal d) async {
    _deals
      ..removeWhere((x) => x.id == d.id)
      ..insert(0, d);
    await _save();
  }

  /// Backend → this device.
  void applyDeals(List<Tk2Deal> deals, {bool block = false}) {
    _deals
      ..clear()
      ..addAll(deals..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    _save();
    if (block) {
      for (final d in deals) {
        _block(d);
      }
    }
  }

  /// The deal broke before signing. [by] = 'owner' or 'tenant'; the token
  /// follows [Tk2Deal.tokenSplit] and the house goes back on the market.
  Future<void> endDeal(Tk2Deal d, String by) {
    d.b.addAll({'ended': by, 'endedAt': DateTime.now().millisecondsSinceEpoch});
    return saveDeal(d, DealRole.broker);
  }

  // ------------------------------------------------------- notifications

  /// Everything up to this time (ms) is read ("Mark all as read").
  int notesReadBefore = 0;

  /// Single notifications opened since then.
  final Set<String> notesRead = {};

  /// Kinds the broker turned off (no badge, no phone alerts): visits · money · deals · houses.
  final Set<String> notesMuted = {};

  Future<void> readNote(String id) {
    notesRead.add(id);
    return _save();
  }

  Future<void> readAllNotes({DateTime? now}) {
    notesReadBefore = (now ?? DateTime.now()).millisecondsSinceEpoch;
    notesRead.clear();
    return _save();
  }

  Future<void> muteNotes(String kind, {required bool off}) {
    off ? notesMuted.add(kind) : notesMuted.remove(kind);
    return _save();
  }

  /// Keeps a society's steps for the next tenant moving in there.
  Future<void> savePlaybook(String society, List<dynamic> steps) {
    playbooks[society.trim().toLowerCase()] = steps;
    sync?.playbook(society.trim(), steps);
    return _save();
  }

  /// Profile details for the main app's account screens (email, city, bank,
  /// RERA…). Name and phone live in [brokerName] / [brokerPhone].
  final Map<String, dynamic> account = {};

  /// Saves profile changes from the account screens.
  Future<void> saveAccount(Map<String, dynamic> details) {
    account.addAll(details);
    final name = details['displayName'];
    if (name is String && name.trim().isNotEmpty) brokerName = name.trim();
    sync?.profile();
    return _save();
  }

  /// Profile as saved in the backend (tk2Brokers/{uid}).
  Map<String, Object?> profileJson() => {
    'name': brokerName,
    'phone': brokerPhone,
    'defaultToken': defaultToken,
    'account': account,
    'contacts': [
      for (final c in _contacts) {'name': c.name, 'phone': c.phone, 'email': c.email},
    ],
  };

  /// Backend → this device: the broker's saved profile.
  void applyProfile(Map<String, dynamic> j) {
    brokerName = j['name'] as String? ?? brokerName;
    brokerPhone = j['phone'] as String? ?? brokerPhone;
    defaultToken = (j['defaultToken'] as num?)?.toInt() ?? defaultToken;
    account
      ..clear()
      ..addAll(Map<String, dynamic>.from(j['account'] as Map? ?? const {}));
    _contacts
      ..clear()
      ..addAll([
        for (final c in (j['contacts'] as List? ?? const []))
          if (c is Map) (name: c['name'] as String? ?? '', phone: c['phone'] as String? ?? '', email: c['email'] as String? ?? ''),
      ]);
    _save();
  }

  /// Backend → this device: listings and off-market notes. Listings still
  /// uploading ([keep]) stay as they are on this device.
  void applyListings(List<Tk2Listing> listings, Map<String, Tk2Inactive> off, {Set<String> keep = const {}}) {
    final local = {for (final l in _listings) l.id: l};
    _listings
      ..clear()
      ..addAll([for (final l in listings) keep.contains(l.id) ? local[l.id] ?? l : l]);
    for (final id in keep) {
      if (!_listings.any((l) => l.id == id) && local[id] != null) _listings.insert(0, local[id]!);
    }
    _inactive
      ..clear()
      ..addAll(off);
    _save();
  }

  /// Backend → this device: visits (broker: theirs; tenant web: own).
  void applyVisits(List<Tk2Visit> visits) {
    // The tenant's code may arrive a moment after the visit: keep the one we have.
    final codes = {for (final v in _visits) v.id: v.code};
    _visits
      ..clear()
      ..addAll([for (final v in visits) v.code.isEmpty && (codes[v.id] ?? '').isNotEmpty ? v._copy(code: codes[v.id]) : v]);
    _save();
  }

  /// After upload: photo files become web addresses.
  void replacePhotos(String id, List<String> photos) {
    final at = _listings.indexWhere((l) => l.id == id);
    if (at < 0) return;
    _listings[at] = _listings[at].copyWith(photos: photos);
    _save();
  }

  /// Log out: the backend keeps everything; this device forgets it.
  Future<void> signOut() async {
    sync?.stop();
    await Tk2Cloud.signOut();
    await _clearDevice();
  }

  /// Delete account: everything on this phone is wiped (and, with the
  /// backend on, the broker's listings and profile).
  Future<void> wipe() async {
    await sync?.deleteAccount();
    await _clearDevice();
  }

  Future<void> _clearDevice() async {
    brokerName = '';
    brokerPhone = '';
    defaultToken = defaultTokenStart;
    tokenSet = false;
    account.clear();
    _inactive.clear();
    _contacts.clear();
    _listings.clear();
    _visits.clear();
    _deals.clear();
    playbooks.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }

  Future<void> setBroker(String name, String phone) {
    brokerName = name.trim();
    brokerPhone = phone.trim();
    sync?.profile();
    return _save();
  }

  /// The broker's usual token (first property and Profile). Properties
  /// already saved keep their own amount.
  Future<void> setDefaultToken(int amount) {
    defaultToken = amount;
    tokenSet = true;
    sync?.profile();
    return _save();
  }

  /// Owner invite link for "Send link to owner" (saved as an invite when the
  /// backend is on).
  String ownerLink(String houseName, String ownerName) => tk2OwnerLink(
    brokerName,
    houseName,
    inviteId: sync?.invite(houseName: houseName, ownerName: ownerName),
  );

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
      _listings.insert(
        0,
        Tk2Listing(
          id: id,
          property: saved,
          door: property.flat,
          society: property.society,
          locality: locality,
          token: defaultToken,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await _save();
    sync?.listing(id);
    return saved;
  }

  Future<void> saveListing(Tk2Listing listing) async {
    final at = _listings.indexWhere((l) => l.id == listing.id);
    if (at < 0) return;
    _listings[at] = listing;
    await _save();
    sync?.listing(listing.id);
  }

  final Map<String, Tk2Inactive> _inactive = {};

  /// Off the market, with why and when; null = active.
  Tk2Inactive? inactive(String id) => _inactive[id];
  bool isActive(String id) => !_inactive.containsKey(id);

  /// Turn a property off. Rented out: 10 months from the rent start date;
  /// otherwise from today.
  Future<void> deactivate(String id, {required String reason, String note = '', DateTime? rentStart, DateTime? now}) {
    final today = now ?? DateTime.now();
    final from = Tk2Inactive.isRented(reason) && rentStart != null ? rentStart : today;
    _inactive[id] = Tk2Inactive(
      reason: reason,
      note: note.trim(),
      since: today.millisecondsSinceEpoch,
      rentStart: Tk2Inactive.isRented(reason) ? rentStart?.millisecondsSinceEpoch : null,
      remindAt: Tk2Inactive.tenMonthsAfter(from).millisecondsSinceEpoch,
    );
    sync?.listing(id);
    return _save();
  }

  /// Back on the market. Turning it off again starts a new 10-month count.
  Future<void> activate(String id) {
    _inactive.remove(id);
    sync?.listing(id);
    return _save();
  }

  /// "Still not available": ask again 10 months from now.
  Future<void> remindLater(String id, {DateTime? now}) {
    final i = _inactive[id];
    if (i == null) return Future.value();
    _inactive[id] = i.remindLater(now ?? DateTime.now());
    sync?.listing(id);
    return _save();
  }

  /// Off-market properties whose 10 months are up (the "check with the owner" updates).
  List<Tk2Listing> remindersDue([DateTime? now]) {
    final t = now ?? DateTime.now();
    return [
      for (final l in _listings)
        if (_inactive[l.id]?.due(t) ?? false) l,
    ];
  }

  Future<void> removeListing(String id) async {
    _inactive.remove(id);
    _listings.removeWhere((l) => l.id == id);
    await _save();
    sync?.removeListing(id);
  }

  void clearSampleNotice() => sampleJustRemoved = false;

  /// Tenants to send to: people who booked visits plus numbers added before (newest first, no repeats).
  List<({String name, String phone, String email})> get contacts {
    final seen = <String>{};
    final out = <({String name, String phone, String email})>[];
    for (final c in [..._contacts.reversed, for (final v in _visits.reversed) (name: v.customerName, phone: v.customerPhone, email: '')]) {
      final key = c.phone.replaceAll(RegExp(r'\D'), '');
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(c);
    }
    return out;
  }

  /// Send a property by any mix of WhatsApp, text message and email
  /// (demo: recorded here; the backend delivers them).
  Future<void> sendListing(
    String listingId, {
    required String name,
    required String phone,
    String email = '',
    required bool whatsapp,
    required bool sms,
    bool byEmail = false,
  }) async {
    final key = phone.replaceAll(RegExp(r'\D'), '');
    final old = _contacts.where((c) => c.phone.replaceAll(RegExp(r'\D'), '') == key).firstOrNull;
    _contacts.removeWhere((c) => c.phone.replaceAll(RegExp(r'\D'), '') == key);
    _contacts.add((name: name.trim(), phone: phone.trim(), email: email.trim().isNotEmpty ? email.trim() : old?.email ?? ''));
    sync?.profile();
    await _save();
  }

  /// Web app: keep the listing that came in the shared link (replaces an older copy).
  Future<void> putListing(Tk2Listing l) async {
    _listings.removeWhere((x) => x.id == l.id);
    _listings.insert(0, l);
    await _save();
  }

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
    await sync?.bookVisit(visit);
    _visits.add(visit);
    await _save();
    return visit;
  }

  /// Broker confirms the visit with the customer's code → fee released.
  /// Returns null when done, or why not: 'wrong' code, or 'window' (more than
  /// 24 hours before or after the visit time).
  Future<String?> confirmVisit(String visitId, String code, {DateTime? now}) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    // Backend: only the tenant can read the code, so the server checks it.
    if (sync != null) {
      if (at < 0) return 'wrong';
      final why = await Tk2Cloud.confirmVisit(visitId, code.trim());
      if (why == null) {
        _visits[at] = _visits[at].withStatus(VisitStatus.done);
        await _save();
      }
      return why;
    }
    if (at < 0 || _visits[at].code != code.trim()) return 'wrong';
    if (!_visits[at].codeWorks(now ?? DateTime.now())) return 'window';
    _visits[at] = _visits[at].withStatus(VisitStatus.done, now: now);
    await _save();
    return null;
  }

  /// Customer cancels any time before the visit is done. Within 5 minutes of
  /// booking they get 98% back; after that nothing (TrustKeyper keeps it).
  Future<bool> customerCancel(String visitId, {DateTime? now}) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0 || !_visits[at].upcoming) return false;
    final inTime = _visits[at].inRefundWindow(now ?? DateTime.now());
    _visits[at] = _visits[at].withStatus(inTime ? VisitStatus.customerCancelled : VisitStatus.customerCancelledLate, now: now);
    sync?.visitStatus(visitId, _visits[at].status);
    await _save();
    return true;
  }

  /// Broker adds the gate pass (demo: kept here; the backend sends it to the
  /// customer on WhatsApp right away).
  Future<void> addGatePass(String visitId, String file) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0) return;
    final url = sync == null ? file : await sync!.gatePass(visitId, file);
    _visits[at] = _visits[at]._copy(gatePass: url);
    await _save();
  }

  /// Broker cancels (full refund) or the customer did not come (broker gets half).
  Future<void> closeVisit(String visitId, String status) async {
    final at = _visits.indexWhere((v) => v.id == visitId);
    if (at < 0) return;
    _visits[at] = _visits[at].withStatus(status);
    sync?.visitStatus(visitId, status);
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
      tk2PropertyLink(l.copyWith(token: l.tokenOr(defaultToken)), brokerName, brokerPhone),
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
