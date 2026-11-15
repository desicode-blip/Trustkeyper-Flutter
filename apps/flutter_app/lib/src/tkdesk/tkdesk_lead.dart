/// TrustKeyper desk: leads (tenants looking for a home, owners with a home to
/// rent) that come before a TK2 property or visit exists.
///
/// One flexible record per lead. The fields follow the top row of the team's
/// sheets ("Tenanat Rent" and "OWNER- FOR RENT"), so anything the sheet can
/// hold, the desk can hold. Format on disk and in imports: TK Lead Format v1
/// (docs/TK-LEAD-FORMAT.md).
library;

enum LeadKind { tenant, home }

/// How a field is edited and shown.
enum FieldType { text, number, money, bhk, choice, yesNo, date, list, phone, longText }

class LeadField {
  const LeadField(this.key, this.label, this.type, {this.choices = const [], this.pref = false, this.group = 'Details'});
  final String key;
  final String label;
  final FieldType type;
  final List<String> choices;

  /// A preference that can be marked "Must have" and is used in matching.
  final bool pref;
  final String group;
}

const tenantFields = <LeadField>[
  LeadField('name', 'Name', FieldType.text, group: 'Contact'),
  LeadField('phone', 'Phone', FieldType.phone, group: 'Contact'),
  LeadField('linkedin', 'LinkedIn', FieldType.text, group: 'Contact'),
  LeadField('bhk', 'Size (BHK)', FieldType.bhk, group: 'Needs'),
  LeadField('budgetMin', 'Budget from', FieldType.money, group: 'Needs'),
  LeadField('budgetMax', 'Budget up to', FieldType.money, pref: true, group: 'Needs'),
  LeadField('budgetRentOnly', 'Budget is rent only (maintenance extra)', FieldType.yesNo, group: 'Needs'),
  LeadField('areas', 'Areas', FieldType.list, pref: true, group: 'Needs'),
  LeadField('moveIn', 'Move-in date', FieldType.date, pref: true, group: 'Needs'),
  LeadField('furnishing', 'Furnishing', FieldType.choice, choices: furnishings, pref: true, group: 'Preferences'),
  LeadField('who', 'Family or bachelors', FieldType.choice, choices: ['family', 'bachelors', 'couple'], pref: true, group: 'Preferences'),
  LeadField('food', 'Veg / non-veg', FieldType.choice, choices: ['veg', 'non-veg'], pref: true, group: 'Preferences'),
  LeadField('pets', 'Has pets', FieldType.yesNo, pref: true, group: 'Preferences'),
  LeadField('parking', 'Car parking needed', FieldType.number, pref: true, group: 'Preferences'),
  LeadField('facing', 'Facing', FieldType.choice, choices: facings, pref: true, group: 'Preferences'),
  LeadField('followUp', 'Next follow-up', FieldType.date, group: 'Follow-up'),
  LeadField('remarks', 'Remarks', FieldType.longText, group: 'Follow-up'),
];

const homeFields = <LeadField>[
  LeadField('society', 'Society', FieldType.text, group: 'Where'),
  LeadField('tower', 'Tower', FieldType.text, group: 'Where'),
  LeadField('flat', 'Flat no.', FieldType.text, group: 'Where'),
  LeadField('area', 'Area', FieldType.text, pref: true, group: 'Where'),
  LeadField('bhk', 'Size (BHK)', FieldType.bhk, group: 'House'),
  LeadField('rent', 'Rent', FieldType.money, group: 'Money'),
  LeadField('maint', 'Maintenance', FieldType.money, group: 'Money'),
  LeadField('maintIncl', 'Rent includes maintenance', FieldType.yesNo, group: 'Money'),
  LeadField('deposit', 'Security deposit', FieldType.text, group: 'Money'),
  LeadField('brokerage', 'Brokerage', FieldType.text, group: 'Money'),
  LeadField('lockIn', 'Lock-in period', FieldType.text, group: 'Money'),
  LeadField('furnishing', 'Furnishing', FieldType.choice, choices: furnishings, pref: true, group: 'House'),
  LeadField('sqft', 'Built-up area (sq ft)', FieldType.number, group: 'House'),
  LeadField('carpet', 'Carpet area', FieldType.number, group: 'House'),
  LeadField('superArea', 'Super built-up area', FieldType.number, group: 'House'),
  LeadField('floor', 'Floor', FieldType.number, group: 'House'),
  LeadField('floors', 'Total floors', FieldType.number, group: 'House'),
  LeadField('facing', 'Facing', FieldType.choice, choices: facings, pref: true, group: 'House'),
  LeadField('parking', 'Car parking', FieldType.number, pref: true, group: 'House'),
  LeadField('powerBackup', 'Power backup', FieldType.choice, choices: ['none', 'partial', 'full'], group: 'House'),
  LeadField('balconies', 'Balconies', FieldType.number, group: 'House'),
  LeadField('washrooms', 'Washrooms', FieldType.number, group: 'House'),
  LeadField('availableFrom', 'Available from', FieldType.date, pref: true, group: 'Tenant'),
  LeadField('who', 'Tenant: family or bachelors', FieldType.choice, choices: ['any', 'family', 'bachelors'], pref: true, group: 'Tenant'),
  LeadField('work', 'Tenant: working preference', FieldType.text, group: 'Tenant'),
  LeadField('food', 'Tenant: veg / non-veg', FieldType.choice, choices: ['any', 'veg only'], pref: true, group: 'Tenant'),
  LeadField('pets', 'Pets allowed', FieldType.yesNo, pref: true, group: 'Tenant'),
  LeadField('ownerName', 'Owner name', FieldType.text, group: 'Owner (private)'),
  LeadField('ownerPhone', 'Owner phone', FieldType.phone, group: 'Owner (private)'),
  LeadField('keys', 'Keys', FieldType.text, group: 'Owner (private)'),
  LeadField('pictures', 'Pictures link', FieldType.text, group: 'Owner (private)'),
  LeadField('followUp', 'Next follow-up', FieldType.date, group: 'Follow-up'),
  LeadField('remarks', 'Remarks', FieldType.longText, group: 'Follow-up'),
];

const furnishings = ['unfurnished', 'semi-furnished', 'fully furnished'];
const facings = ['east', 'west', 'north', 'south', 'north-east', 'north-west', 'south-east', 'south-west'];

/// Tenant status. Homes use [HomeState].
const tenantStatuses = ['new', 'calling', 'looking', 'visit planned', 'got a home', 'lost'];
const tenantClosed = {'got a home', 'lost'};

abstract final class HomeState {
  static const active = 'active';
  static const inactive = 'inactive';
  static const cancelled = 'cancelled';
}

List<LeadField> fieldsFor(LeadKind kind) => kind == LeadKind.tenant ? tenantFields : homeFields;
LeadField? fieldFor(LeadKind kind, String key) {
  for (final f in fieldsFor(kind)) {
    if (f.key == key) return f;
  }
  return null;
}

class Lead {
  Lead({
    required this.id,
    required this.kind,
    Map<String, dynamic>? f,
    Set<String>? must,
    this.status = '',
    int? at,
    int? changed,
    Map<String, dynamic>? source,
    this.off,
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? notes,
    this.listingId = '',
  }) : f = f ?? {},
       must = must ?? {},
       at = at ?? DateTime.now().millisecondsSinceEpoch,
       changed = changed ?? DateTime.now().millisecondsSinceEpoch,
       source = source ?? {},
       history = history ?? [],
       notes = notes ?? [];

  final String id;
  final LeadKind kind;

  /// The details, keyed as in [tenantFields] / [homeFields].
  final Map<String, dynamic> f;

  /// Field keys this person will not compromise on.
  final Set<String> must;
  String status;
  final int at;
  int changed;

  /// Where the lead came from: type, group, text (the original post), by (who made the file).
  final Map<String, dynamic> source;

  /// Why a home is not active or cancelled: reason, freeFrom, note, at.
  Map<String, dynamic>? off;

  /// Every change: k (field), o (old), n (new), t (time). Never trimmed.
  final List<Map<String, dynamic>> history;

  /// Call notes: text, t.
  final List<Map<String, dynamic>> notes;

  /// The TK2 property made from this home lead, if any.
  String listingId;

  bool get isTenant => kind == LeadKind.tenant;
  bool get isHome => kind == LeadKind.home;

  String str(String k) => (f[k] ?? '').toString().trim();
  double numOf(String k) => toNum(f[k]);
  bool yes(String k) => f[k] == true || f[k] == 'yes' || f[k] == 'true';
  bool has(String k) {
    final v = f[k];
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is num) return v != 0;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  double get bhk => numOf('bhk');
  int get rent => numOf('rent').round();
  String get phone => kind == LeadKind.tenant ? str('phone') : str('ownerPhone');
  String get personName => kind == LeadKind.tenant ? str('name') : str('ownerName');
  List<String> get areas => listOf(f['areas']);

  bool get active => isHome ? status == HomeState.active : !tenantClosed.contains(status);

  /// Has what matching needs: tenants a size; homes a size and a rent.
  bool get ready => isTenant ? bhk > 0 : bhk > 0 && rent > 0;

  /// Card heading: society, else area (TK2 rule). Tenants: their name.
  String get title {
    if (isTenant) return str('name').isEmpty ? 'Tenant ${phoneText(phone)}' : str('name');
    if (str('society').isNotEmpty) return '${str('society')}${str('area').isEmpty ? '' : ', ${cap(str('area'))}'}';
    return str('area').isEmpty ? 'Home (area not known)' : cap(str('area'));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    ...f,
    if (must.isNotEmpty) 'mustHave': must.toList(),
    'status': status,
    'at': at,
    'changed': changed,
    if (source.isNotEmpty) 'source': source,
    if (off != null) 'off': off,
    if (history.isNotEmpty) 'history': history,
    if (notes.isNotEmpty) 'notes': notes,
    if (listingId.isNotEmpty) 'listingId': listingId,
  };

  static const _meta = {'id', 'kind', 'mustHave', 'status', 'at', 'changed', 'source', 'off', 'history', 'notes', 'listingId', 'format'};

  factory Lead.fromJson(Map<String, dynamic> j, {LeadKind? kind}) {
    final k = kind ?? (j['kind'] == 'home' ? LeadKind.home : LeadKind.tenant);
    final f = <String, dynamic>{
      for (final e in j.entries)
        if (!_meta.contains(e.key)) e.key: e.value,
    };
    return Lead(
      id: (j['id'] ?? '').toString(),
      kind: k,
      f: f,
      must: {...listOf(j['mustHave'])},
      status: (j['status'] ?? '').toString(),
      at: parseTime(j['at']),
      changed: parseTime(j['changed'] ?? j['at']),
      source: j['source'] is Map ? Map<String, dynamic>.from(j['source'] as Map) : {},
      off: j['off'] is Map ? Map<String, dynamic>.from(j['off'] as Map) : null,
      history: [for (final h in (j['history'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)],
      notes: [for (final h in (j['notes'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)],
      listingId: (j['listingId'] ?? '').toString(),
    );
  }
}

double toNum(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().toLowerCase().replaceAll(',', '').trim();
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*(k|l|lakh)?').firstMatch(s);
  if (m == null) return 0;
  var n = double.parse(m.group(1)!);
  if (m.group(2) == 'k') n *= 1000;
  if (m.group(2) == 'l' || m.group(2) == 'lakh') n *= 100000;
  return n;
}

List<String> listOf(Object? v) {
  if (v == null) return [];
  if (v is List) return [for (final e in v) e.toString().trim()].where((e) => e.isNotEmpty).toList();
  return v.toString().split(RegExp(r'[,/;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

int parseTime(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  final d = DateTime.tryParse((v ?? '').toString());
  return (d ?? DateTime.now()).millisecondsSinceEpoch;
}

String cap(String s) => s.isEmpty ? s : s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

String phoneText(String p) {
  final d = p.replaceAll(RegExp(r'\D'), '');
  final t = d.length > 10 ? d.substring(d.length - 10) : d;
  return t.length == 10 ? '${t.substring(0, 5)} ${t.substring(5)}' : p;
}

String bhkText(double b) => b <= 0 ? '' : '${b == b.roundToDouble() ? b.toInt() : b} BHK';

String rupees(num n) {
  if (n <= 0) return '';
  final s = n.round().toString();
  if (s.length <= 3) return '₹$s';
  final last = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last';
}
