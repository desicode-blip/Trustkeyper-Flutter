import 'dart:convert';

import 'tk2_designs.dart';
import 'tk2_store.dart';

/// Tenant/owner web app (prototype on a Claude link until trustkeyper.com hosts it).
const tk2WebApp = 'https://claude.ai/artifact/Szj2fK38ocoCABGHbTtxUt';

/// Only what customers may see. Never door number, full address, owner or keys.
Map<String, Object?> tk2PublicPayload(Tk2Listing l, String brokerName) {
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
  };
}

/// Property link for WhatsApp: the public details ride in the link (#p-…).
String tk2PropertyLink(Tk2Listing l, String brokerName) => '$tk2WebApp#p-${tk2Base32(jsonEncode(tk2PublicPayload(l, brokerName)))}';

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
