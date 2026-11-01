import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

abstract class SmsSender {
  /// Sends the OTP to a 10-digit Indian mobile number. Throws on failure.
  Future<void> sendOtp(String phone10, String code);
}

abstract class EmailSender {
  Future<void> send({required List<String> to, required String subject, required String text, String? html});
}

/// MSG91 OTP API (India). Needs a DLT-approved template whose OTP variable is
/// named `otp`, e.g. "Your TrustKeyper code is ##otp##. It expires in 10 minutes."
class Msg91Sms implements SmsSender {
  final Config c;
  final http.Client _http;
  Msg91Sms(this.c, [http.Client? client]) : _http = client ?? http.Client();

  @override
  Future<void> sendOtp(String phone10, String code) async {
    final res = await _http.post(
      Uri.https('control.msg91.com', '/api/v5/flow'),
      headers: {'authkey': c.msg91AuthKey, 'content-type': 'application/json', 'accept': 'application/json'},
      body: jsonEncode({
        'template_id': c.msg91TemplateId,
        'short_url': '0',
        'recipients': [
          {'mobiles': '91$phone10', 'otp': code},
        ],
      }),
    );
    if (res.statusCode != 200 || !res.body.contains('"success"')) {
      throw Exception('MSG91 error ${res.statusCode}: ${res.body}');
    }
  }
}

/// Resend.com transactional email. The sending domain (trustkeyper.com) must be
/// verified in the Resend dashboard (they show the DNS records to add).
class ResendEmail implements EmailSender {
  final Config c;
  final http.Client _http;
  ResendEmail(this.c, [http.Client? client]) : _http = client ?? http.Client();

  @override
  Future<void> send({required List<String> to, required String subject, required String text, String? html}) async {
    final res = await _http.post(
      Uri.https('api.resend.com', '/emails'),
      headers: {'authorization': 'Bearer ${c.resendApiKey}', 'content-type': 'application/json'},
      body: jsonEncode({'from': c.emailFrom, 'to': to, 'subject': subject, 'text': text, if (html != null) 'html': html}),
    );
    if (res.statusCode >= 300) throw Exception('Resend error ${res.statusCode}: ${res.body}');
  }
}

/// Local testing only: prints instead of sending.
class ConsoleSms implements SmsSender {
  final sent = <String, String>{};
  @override
  Future<void> sendOtp(String phone10, String code) async {
    sent[phone10] = code;
    print('[console-sms] +91$phone10 code=$code');
  }
}

class ConsoleEmail implements EmailSender {
  final sent = <Map<String, Object?>>[];
  @override
  Future<void> send({required List<String> to, required String subject, required String text, String? html}) async {
    sent.add({'to': to, 'subject': subject, 'text': text});
    print('[console-email] to=$to subject=$subject\n$text');
  }
}
