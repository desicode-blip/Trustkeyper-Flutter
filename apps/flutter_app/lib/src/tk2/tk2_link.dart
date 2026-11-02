import 'dart:convert';

import '../features/broker/data/broker_property_repository.dart';

import 'tk2_designs.dart';
import 'tk2_store.dart';

/// Tenant/owner web app (prototype on a Claude link until trustkeyper.com hosts it).
const tk2WebApp = 'https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt';

/// Only what customers may see. Never door number, full address, owner or keys.
Map<String, Object?> tk2PublicPayload(Tk2Listing l, String brokerName, [String brokerPhone = '']) {
  final p = l.property;
  return {
    'id': l.id,
    't': tk2CardHeading(l),
    'a': tk2PublicAddress(l),
    'r': p.rooms,
    'rent': l.rent,
    'mi': l.maintenanceIncluded || l.maintenance == 0 ? 1 : 0,
    'm': l.maintenance,
    'd': l.deposit,
    'b': l.brokerage,
    'bd': l.brokerageDays,
    'f': l.furnishingText,
    if (p.sizeSqFt != null) 's': p.sizeSqFt!.round(),
    'fl': p.floor,
    'tf': p.totalFloors,
    if ((p.facing ?? '').isNotEmpty) 'fc': p.facing,
    'w': l.tenants,
    'pt': l.pets ? 1 : 0,
    'av': l.availableFrom,
    'vd': l.visitDays,
    'vf': l.visitFrom,
    'vt': l.visitTo,
    'fee': l.visitFee,
    'bn': brokerName,
    if (brokerPhone.isNotEmpty) 'bp': brokerPhone,
  };
}

/// Property link for WhatsApp: the public details ride in the link (#p-…).
String tk2PropertyLink(Tk2Listing l, String brokerName, [String brokerPhone = '']) =>
    '$tk2WebApp#p-${tk2Base32(jsonEncode(tk2PublicPayload(l, brokerName, brokerPhone)))}';

/// Owner invite link: the owner signs up and adds the house (#owner-…).
String tk2OwnerLink(String brokerName, String houseName) => '$tk2WebApp#owner-${tk2Base32(jsonEncode({'bn': brokerName, 'h': houseName}))}';

/// Lower-case base32 (a–z, 2–7): the only characters the link's #name allows.
String tk2Base32(String text) {
  const abc = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = StringBuffer();
  var value = 0, bits = 0;
  for (final b in utf8.encode(text)) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(abc[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
    value &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(abc[(value << (5 - bits)) & 31]);
  return out.toString();
}

/// Web app: rebuild the public listing from a link payload (see [tk2PublicPayload]).
Tk2Listing tk2ListingFromPublic(Map<String, dynamic> j) {
  int n(String k, [int d = 0]) => (j[k] as num?)?.toInt() ?? d;
  String t(String k) => j[k] as String? ?? '';
  final furnishing = switch (t('f')) {
    'Fully furnished' => 'Full',
    'Semi-furnished' => 'Semi',
    _ => 'Empty',
  };
  final area = t('a');
  return Tk2Listing(
    id: t('id').isEmpty ? 'shared' : t('id'),
    property: BrokerProperty(
      id: t('id'),
      address: area,
      rooms: t('r').isEmpty ? '2 BHK' : t('r'),
      floor: n('fl'),
      totalFloors: n('tf'),
      furnishing: furnishing,
      sizeSqFt: j['s'] == null ? null : n('s').toDouble(),
      facing: j['fc'] as String?,
    ),
    society: t('t'),
    locality: area,
    rent: n('rent'),
    maintenance: n('m'),
    maintenanceIncluded: n('mi', 1) == 1,
    deposit: n('d'),
    brokerage: n('b'),
    brokerageDays: n('bd'),
    tenants: t('w').isEmpty ? 'Anyone' : t('w'),
    pets: n('pt', 1) == 1,
    availableFrom: t('av'),
    visitDays: t('vd').isEmpty ? 'all' : t('vd'),
    visitFrom: n('vf', 7),
    visitTo: n('vt', 23),
    visitFee: n('fee', 150),
  );
}

/// Decode the text after "#p-" / "#owner-".
String tk2Base32Decode(String code) {
  const abc = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = <int>[];
  var value = 0, bits = 0;
  for (final ch in code.split('')) {
    final i = abc.indexOf(ch);
    if (i < 0) continue;
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 255);
      bits -= 8;
    }
    value &= (1 << bits) - 1;
  }
  return utf8.decode(out, allowMalformed: true);
}
