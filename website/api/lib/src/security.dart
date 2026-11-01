import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _rng = Random.secure();

/// A random 6-digit code, e.g. "048213".
String newOtpCode() => List.generate(6, (_) => _rng.nextInt(10)).join();

/// One-way hash of a code, tied to the target and the server secret.
/// Codes are never stored or logged in plain text.
String hashCode6(String secret, String channel, String target, String code) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$channel|$target|$code')).toString();

/// Stable id for a phone/email, used as the database key (no raw contact in the key).
String targetKey(String secret, String channel, String target) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('key|$channel|$target')).toString().substring(0, 40);

/// Compares two strings in constant time (prevents timing attacks).
bool safeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return r == 0;
}

/// Signed, short-lived proof that a phone/email was verified.
/// Format: base64url(payload).base64url(hmac)
String issueToken(String secret, String channel, String target, DateTime expires) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'c': channel,
    't': target,
    'e': expires.millisecondsSinceEpoch ~/ 1000,
    'n': _rng.nextInt(1 << 32),
  }))).replaceAll('=', '');
  final sig = base64Url.encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload)).bytes).replaceAll('=', '');
  return '$payload.$sig';
}

class VerifiedContact {
  final String channel;
  final String target;
  VerifiedContact(this.channel, this.target);
}

/// Returns the verified contact if the token is genuine and unexpired, else null.
VerifiedContact? readToken(String secret, String? token, {DateTime? now}) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 2) return null;
  final expected = base64Url.encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(parts[0])).bytes).replaceAll('=', '');
  if (!safeEquals(expected, parts[1])) return null;
  try {
    final padded = parts[0].padRight((parts[0].length + 3) ~/ 4 * 4, '=');
    final m = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
    final exp = DateTime.fromMillisecondsSinceEpoch((m['e'] as int) * 1000);
    if ((now ?? DateTime.now()).isAfter(exp)) return null;
    return VerifiedContact(m['c'] as String, m['t'] as String);
  } catch (_) {
    return null;
  }
}

final phoneRe = RegExp(r'^[6-9]\d{9}$');
final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Normalises and checks a phone/email. Returns null if invalid.
String? cleanTarget(String channel, Object? raw) {
  if (raw is! String) return null;
  if (channel == 'phone') {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    final ten = d.length == 12 && d.startsWith('91') ? d.substring(2) : d;
    return phoneRe.hasMatch(ten) ? ten : null;
  }
  if (channel == 'email') {
    final e = raw.trim().toLowerCase();
    return e.length <= 254 && emailRe.hasMatch(e) ? e : null;
  }
  return null;
}
