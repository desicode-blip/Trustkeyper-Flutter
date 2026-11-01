import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:trustkeyper_web_api/trustkeyper_web_api.dart';

void main() {
  late Config c;
  late MemoryStore store;
  late ConsoleSms sms;
  late ConsoleEmail email;
  late DateTime clock;
  late Handler h;

  setUp(() {
    c = Config.fromEnv({'TK_SECRET': 'x' * 40, 'LEADS_TO': 'leads@trustkeyper.com'});
    store = MemoryStore();
    sms = ConsoleSms();
    email = ConsoleEmail();
    clock = DateTime(2026, 11, 1, 10);
    h = Api(c, store, sms, email, clock: () => clock).handler;
  });

  Future<(int, Map<String, dynamic>)> post(String path, Map<String, Object?> body, {String ip = '1.1.1.1'}) async {
    final res = await h(Request('POST', Uri.parse('http://localhost$path'),
        body: jsonEncode(body), headers: {'content-type': 'application/json', 'x-forwarded-for': ip}));
    return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, dynamic>);
  }

  Future<String> verifiedPhoneToken([String phone = '9876543210']) async {
    await post('/api/otp/send', {'channel': 'phone', 'target': phone});
    final (_, v) = await post('/api/otp/verify', {'channel': 'phone', 'target': phone, 'code': sms.sent[phone]});
    return v['token'] as String;
  }

  Map<String, Object?> lead(String token, {String phone = '9876543210', String email = '', String role = 'property_owner', String id = 'req-12345678'}) => {
        'firstName': 'Ravi',
        'lastName': 'Kumar',
        'phone': phone,
        'email': email,
        'role': role,
        'serviceTiming': 'exploring',
        'message': 'I am a: Property owner\nNeeds the most: All of the above',
        'otpToken': token,
        'website': '',
        'requestId': id,
      };

  group('validation helpers', () {
    test('phone numbers', () {
      expect(cleanTarget('phone', '9876543210'), '9876543210');
      expect(cleanTarget('phone', '+91 98765 43210'), '9876543210');
      expect(cleanTarget('phone', '1234567890'), isNull);
      expect(cleanTarget('phone', '98765'), isNull);
    });
    test('emails', () {
      expect(cleanTarget('email', ' Owner@Example.COM '), 'owner@example.com');
      expect(cleanTarget('email', 'not-an-email'), isNull);
    });
    test('tokens are signed and expire', () {
      final t = issueToken(c.secret, 'phone', '9876543210', clock.add(const Duration(minutes: 30)));
      expect(readToken(c.secret, t, now: clock)!.target, '9876543210');
      expect(readToken(c.secret, t, now: clock.add(const Duration(minutes: 31))), isNull);
      expect(readToken('y' * 40, t, now: clock), isNull, reason: 'wrong secret');
      expect(readToken(c.secret, '${t}x', now: clock), isNull, reason: 'tampered');
    });
    test('config flags missing production settings', () {
      final bad = Config.fromEnv({'SMS_PROVIDER': 'msg91', 'STORE': 'firestore'});
      expect(bad.problems().length, 3);
    });
  });

  group('POST /api/otp/send', () {
    test('sends a 6-digit SMS code and stores only a hash', () async {
      final (s, b) = await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'});
      expect(s, 200);
      expect(b['sent'], true);
      expect(sms.sent['9876543210'], matches(RegExp(r'^\d{6}$')));
      expect(store.otps.values.single.codeHash, isNot(contains(sms.sent['9876543210']!)));
    });
    test('sends email codes', () async {
      final (s, _) = await post('/api/otp/send', {'channel': 'email', 'target': 'a@b.com'});
      expect(s, 200);
      expect(email.sent.single['subject'], contains('verification code'));
    });
    test('rejects bad input', () async {
      expect((await post('/api/otp/send', {'channel': 'phone', 'target': '123'})).$1, 400);
      expect((await post('/api/otp/send', {'channel': 'fax', 'target': '9876543210'})).$1, 400);
    });
    test('blocks resend within 30 seconds, allows after', () async {
      await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'});
      expect((await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'})).$1, 429);
      clock = clock.add(const Duration(seconds: 31));
      expect((await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'})).$1, 200);
    });
    test('limits sends per number per hour', () async {
      for (var i = 0; i < 5; i++) {
        expect((await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'}, ip: '9.9.9.$i')).$1, 200);
        clock = clock.add(const Duration(seconds: 31));
      }
      expect((await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'}, ip: '8.8.8.8')).$1, 429);
    });
    test('ignores bots that fill the hidden field', () async {
      final (s, _) = await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210', 'website': 'spam'});
      expect(s, 200);
      expect(sms.sent, isEmpty);
    });
  });

  group('POST /api/otp/verify', () {
    test('right code returns a token, and works only once', () async {
      await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'});
      final code = sms.sent['9876543210'];
      final (_, ok) = await post('/api/otp/verify', {'channel': 'phone', 'target': '9876543210', 'code': code});
      expect(ok['verified'], true);
      expect(ok['token'], isA<String>());
      final (_, again) = await post('/api/otp/verify', {'channel': 'phone', 'target': '9876543210', 'code': code});
      expect(again['verified'], false);
    });
    test('wrong code fails; 5 wrong attempts lock the code', () async {
      await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'});
      final right = sms.sent['9876543210'];
      final wrong = right == '000000' ? '111111' : '000000';
      for (var i = 0; i < 5; i++) {
        expect((await post('/api/otp/verify', {'channel': 'phone', 'target': '9876543210', 'code': wrong})).$2['verified'], false);
      }
      expect((await post('/api/otp/verify', {'channel': 'phone', 'target': '9876543210', 'code': right})).$1, 429);
    });
    test('expired code fails', () async {
      await post('/api/otp/send', {'channel': 'phone', 'target': '9876543210'});
      clock = clock.add(const Duration(minutes: 11));
      final (_, b) = await post('/api/otp/verify', {'channel': 'phone', 'target': '9876543210', 'code': sms.sent['9876543210']});
      expect(b['verified'], false);
    });
  });

  group('POST /api/contact', () {
    test('accepts a verified phone enquiry, saves it and emails the team', () async {
      final t = await verifiedPhoneToken();
      final (s, b) = await post('/api/contact', lead(t));
      expect(s, 200);
      expect(b['accepted'], true);
      expect(store.leads.values.single['roleLabel'], 'Property owner');
      expect(email.sent.last['to'], ['leads@trustkeyper.com']);
      expect(email.sent.last['text'], contains('+91 9876543210'));
    });
    test('accepts a verified email enquiry with no phone, and the builder role', () async {
      await post('/api/otp/send', {'channel': 'email', 'target': 'b@build.in'});
      final code = RegExp(r'\d{6}').firstMatch(email.sent.single['text'] as String)!.group(0);
      final (_, v) = await post('/api/otp/verify', {'channel': 'email', 'target': 'b@build.in', 'code': code});
      final (s, _) = await post('/api/contact', lead(v['token'] as String, phone: '', email: 'b@build.in', role: 'builder'));
      expect(s, 200);
      expect(store.leads.values.single['role'], 'builder');
    });
    test('rejects missing token, or a token for a different number', () async {
      expect((await post('/api/contact', lead(''))).$1, 400);
      final t = await verifiedPhoneToken('9123456789');
      final (s, b) = await post('/api/contact', lead(t, phone: '9876543210'));
      expect(s, 400);
      expect(b['fields'], contains('contact'));
    });
    test('duplicate submit is saved and emailed only once', () async {
      final t = await verifiedPhoneToken();
      await post('/api/contact', lead(t));
      final before = email.sent.length;
      final (s, _) = await post('/api/contact', lead(t));
      expect(s, 200);
      expect(store.leads.length, 1);
      expect(email.sent.length, before);
    });
    test('rejects unknown roles', () async {
      final t = await verifiedPhoneToken();
      expect((await post('/api/contact', lead(t, role: 'hacker'))).$1, 400);
    });
  });
}
