import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'security.dart';
import 'senders.dart';
import 'store.dart';

const allowedRoles = {'property_owner', 'tenant', 'broker', 'builder'};
const roleLabels = {
  'property_owner': 'Property owner',
  'tenant': 'Tenant',
  'broker': 'Property agent',
  'builder': 'Builder',
};
const allowedTimings = {'immediately', 'within_1_month', 'within_3_months', 'within_6_months', 'exploring'};

/// The website's backend: three JSON endpoints matching website.js exactly.
class Api {
  final Config c;
  final Store store;
  final SmsSender sms;
  final EmailSender email;
  final DateTime Function() now;

  Api(this.c, this.store, this.sms, this.email, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  Handler get handler {
    final r = Router()
      ..get('/healthz', (_) => Response.ok('ok'))
      ..post('/api/otp/send', _send)
      ..post('/api/otp/verify', _verify)
      ..post('/api/contact', _contact);
    return const Pipeline().addMiddleware(_cors()).addMiddleware(_errors()).addHandler(r.call);
  }

  // ---------------------------------------------------------------- send
  Future<Response> _send(Request req) async {
    final b = await _json(req);
    if (b == null) return _out(400, {'sent': false, 'error': 'bad_json'});
    if (_honeypot(b)) return _out(200, {'sent': true}); // silently ignore bots
    final channel = b['channel'];
    if (channel != 'phone' && channel != 'email') return _out(400, {'sent': false, 'error': 'invalid_channel'});
    final target = cleanTarget(channel as String, b['target']);
    if (target == null) return _out(400, {'sent': false, 'error': 'invalid_target'});

    final ip = _ip(req);
    if (await store.hit('send-ip|$ip') > c.maxSendsPerIpPerHour) return _out(429, {'sent': false, 'error': 'rate_limited'});
    final key = targetKey(c.secret, channel, target);
    final existing = await store.getOtp(key);
    if (existing != null && now().difference(existing.sentAt) < c.resendGap) {
      return _out(429, {'sent': false, 'error': 'too_soon'});
    }
    if (await store.hit('send-target|$key') > c.maxSendsPerTargetPerHour) return _out(429, {'sent': false, 'error': 'rate_limited'});

    final code = newOtpCode();
    await store.putOtp(key, OtpRecord(codeHash: hashCode6(c.secret, channel, target, code), expiresAt: now().add(c.codeTtl), sentAt: now()));
    try {
      if (channel == 'phone') {
        await sms.sendOtp(target, code);
      } else {
        await email.send(
          to: [target],
          subject: 'Your TrustKeyper verification code',
          text: 'Your TrustKeyper verification code is $code.\n\nIt expires in 10 minutes. If you did not ask for this code, you can ignore this email.\n\nTrustKeyper · info@trustkeyper.com · +91 8088516875',
          html: _codeEmailHtml(code),
        );
      }
    } catch (e) {
      await store.deleteOtp(key);
      print('send failed ($channel): $e');
      return _out(502, {'sent': false, 'error': 'delivery_failed'});
    }
    return _out(200, {'sent': true});
  }

  // ---------------------------------------------------------------- verify
  Future<Response> _verify(Request req) async {
    final b = await _json(req);
    if (b == null) return _out(400, {'verified': false, 'error': 'bad_json'});
    final channel = b['channel'];
    if (channel != 'phone' && channel != 'email') return _out(400, {'verified': false, 'error': 'invalid_channel'});
    final target = cleanTarget(channel as String, b['target']);
    final code = b['code'];
    if (target == null || code is! String || !RegExp(r'^\d{6}$').hasMatch(code)) return _out(200, {'verified': false});

    final key = targetKey(c.secret, channel, target);
    final rec = await store.getOtp(key);
    if (rec == null || now().isAfter(rec.expiresAt)) return _out(200, {'verified': false, 'error': 'expired'});
    if (rec.attempts >= c.maxVerifyAttempts) {
      await store.deleteOtp(key);
      return _out(429, {'verified': false, 'error': 'too_many_attempts'});
    }
    if (!safeEquals(rec.codeHash, hashCode6(c.secret, channel, target, code))) {
      await store.putOtp(key, rec.withAttempts(rec.attempts + 1));
      return _out(200, {'verified': false});
    }
    await store.deleteOtp(key); // single use
    return _out(200, {'verified': true, 'token': issueToken(c.secret, channel, target, now().add(c.tokenTtl))});
  }

  // ---------------------------------------------------------------- contact
  Future<Response> _contact(Request req) async {
    final b = await _json(req);
    if (b == null) return _out(400, {'accepted': false, 'error': 'bad_json'});
    if (_honeypot(b)) return _out(200, {'accepted': true});
    if (await store.hit('contact-ip|${_ip(req)}') > c.maxContactsPerIpPerHour) return _out(429, {'accepted': false});

    String s(String k, [int max = 200]) {
      final v = b[k];
      return v is String ? v.trim().substring(0, v.trim().length.clamp(0, max)) : '';
    }

    final fields = <String, String>{};
    final firstName = s('firstName', 100);
    var lastName = s('lastName', 100);
    if (lastName == '-') lastName = '';
    final role = s('role', 40);
    final timing = allowedTimings.contains(s('serviceTiming', 40)) ? s('serviceTiming', 40) : 'exploring';
    final message = s('message', 5000);
    final requestId = s('requestId', 80);
    if (firstName.length < 2) fields['name'] = 'Please enter your name';
    if (!allowedRoles.contains(role)) fields['role'] = 'Select your role';
    if (!RegExp(r'^[A-Za-z0-9-]{8,80}$').hasMatch(requestId)) fields['requestId'] = 'Missing request id';

    final verified = readToken(c.secret, b['otpToken'] as String?, now: now());
    final phone = cleanTarget('phone', b['phone']);
    final mail = cleanTarget('email', b['email']);
    final matches = verified != null &&
        ((verified.channel == 'phone' && verified.target == phone) || (verified.channel == 'email' && verified.target == mail));
    if (!matches) fields['contact'] = 'Please verify your phone number or email again';
    if (fields.isNotEmpty || verified == null) return _out(400, {'accepted': false, 'fields': fields});

    final contact = verified.channel == 'phone' ? '+91 $phone' : mail!;
    final lead = <String, Object?>{
      'createdAt': now(),
      'firstName': firstName,
      'lastName': lastName,
      'role': role,
      'roleLabel': roleLabels[role],
      'serviceTiming': timing,
      'verifiedChannel': verified.channel,
      'phone': phone,
      'email': mail,
      'message': message,
      'ip': _ip(req),
      'userAgent': req.headers['user-agent'] ?? '',
      'status': 'new',
    };
    final isNew = await store.saveLead(requestId, lead);
    if (isNew) {
      try {
        await email.send(
          to: c.leadsTo,
          subject: 'New ${roleLabels[role]} enquiry: $firstName $lastName'.trim(),
          text: 'Name: $firstName $lastName\nVerified ${verified.channel}: $contact\nRole: ${roleLabels[role]}\n\n$message\n\nReceived: ${now().toUtc().toIso8601String()} UTC',
        );
      } catch (e) {
        // The lead is already saved in Firestore, so the visitor still gets a success.
        print('lead email failed for $requestId: $e');
      }
    }
    return _out(200, {'accepted': true});
  }

  // ---------------------------------------------------------------- helpers
  Future<Map<String, dynamic>?> _json(Request req) async {
    try {
      final body = await req.readAsString();
      if (body.length > 20000) return null;
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  bool _honeypot(Map<String, dynamic> b) => (b['website'] is String) && (b['website'] as String).isNotEmpty;

  String _ip(Request req) {
    final fwd = req.headers['x-forwarded-for'];
    if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
    final info = req.context['shelf.io.connection_info'];
    return info == null ? 'unknown' : (info as dynamic).remoteAddress.address as String;
  }

  Response _out(int status, Map<String, Object?> body) =>
      Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json', 'cache-control': 'no-store'});

  Middleware _cors() => (inner) => (req) async {
        final origin = req.headers['origin'];
        final ok = origin != null && c.allowedOrigins.contains(origin);
        final h = ok
            ? {'access-control-allow-origin': origin, 'vary': 'origin', 'access-control-allow-methods': 'POST, GET, OPTIONS', 'access-control-allow-headers': 'content-type'}
            : <String, String>{};
        if (req.method == 'OPTIONS') return Response(204, headers: h);
        final res = await inner(req);
        return res.change(headers: h);
      };

  Middleware _errors() => (inner) => (req) async {
        try {
          return await inner(req);
        } catch (e, st) {
          print('ERROR ${req.method} ${req.url}: $e\n$st');
          return _out(500, {'error': 'server_error'});
        }
      };

  String _codeEmailHtml(String code) => '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#0d1a48">
  <p style="font-size:20px;font-weight:bold;margin:0 0 16px">TrustKeyper</p>
  <p style="margin:0 0 12px">Your verification code is:</p>
  <p style="font-size:34px;letter-spacing:8px;font-weight:bold;background:#edf4f7;border-radius:12px;padding:16px;text-align:center;margin:0 0 16px">$code</p>
  <p style="color:#5b6b7f;font-size:14px;margin:0">It expires in 10 minutes. If you did not ask for this code, you can ignore this email.</p>
</div>''';
}
