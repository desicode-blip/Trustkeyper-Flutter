import 'dart:io';

/// All settings come from environment variables (set them on the Cloud Run
/// service). Nothing secret is written in code.
class Config {
  /// Long random string used to sign verification tokens and hash OTP codes.
  /// REQUIRED in production. Generate with: openssl rand -hex 32
  final String secret;

  /// 'msg91' (India SMS) or 'console' (prints codes to the log; local testing only).
  final String smsProvider;
  final String msg91AuthKey;
  final String msg91TemplateId;

  /// 'resend' or 'console'.
  final String emailProvider;
  final String resendApiKey;
  final String emailFrom;

  /// Where new enquiries are emailed, comma separated.
  final List<String> leadsTo;

  /// 'firestore' (production) or 'memory' (local testing only).
  final String store;
  final String gcpProject;

  /// Allowed browser origins for CORS (the website). Same-origin calls via
  /// Firebase Hosting rewrites do not need this, but it is safe to set.
  final List<String> allowedOrigins;

  final int port;

  // Limits (sensible defaults, change only if needed).
  final Duration codeTtl = const Duration(minutes: 10);
  final Duration tokenTtl = const Duration(minutes: 30);
  final Duration resendGap = const Duration(seconds: 30);
  final int maxSendsPerTargetPerHour = 5;
  final int maxSendsPerIpPerHour = 10;
  final int maxVerifyAttempts = 5;
  final int maxContactsPerIpPerHour = 10;

  Config({
    required this.secret,
    required this.smsProvider,
    required this.msg91AuthKey,
    required this.msg91TemplateId,
    required this.emailProvider,
    required this.resendApiKey,
    required this.emailFrom,
    required this.leadsTo,
    required this.store,
    required this.gcpProject,
    required this.allowedOrigins,
    required this.port,
  });

  factory Config.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String v(String k, [String d = '']) => (e[k] ?? d).trim();
    List<String> list(String k, [String d = '']) =>
        v(k, d).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return Config(
      secret: v('TK_SECRET'),
      smsProvider: v('SMS_PROVIDER', 'console'),
      msg91AuthKey: v('MSG91_AUTH_KEY'),
      msg91TemplateId: v('MSG91_TEMPLATE_ID'),
      emailProvider: v('EMAIL_PROVIDER', 'console'),
      resendApiKey: v('RESEND_API_KEY'),
      emailFrom: v('EMAIL_FROM', 'TrustKeyper <noreply@trustkeyper.com>'),
      leadsTo: list('LEADS_TO', 'info@trustkeyper.com'),
      store: v('STORE', 'memory'),
      gcpProject: v('GCP_PROJECT', v('GOOGLE_CLOUD_PROJECT')),
      allowedOrigins: list('ALLOWED_ORIGINS', 'https://trustkeyper.com,https://www.trustkeyper.com'),
      port: int.tryParse(v('PORT', '8080')) ?? 8080,
    );
  }

  /// Fails fast at start-up if production settings are missing, so a broken
  /// deploy is caught immediately instead of when a visitor tries the form.
  List<String> problems() {
    final p = <String>[];
    if (secret.length < 32) p.add('TK_SECRET must be at least 32 characters.');
    if (smsProvider == 'msg91' && (msg91AuthKey.isEmpty || msg91TemplateId.isEmpty)) {
      p.add('MSG91_AUTH_KEY and MSG91_TEMPLATE_ID are required when SMS_PROVIDER=msg91.');
    }
    if (emailProvider == 'resend' && resendApiKey.isEmpty) {
      p.add('RESEND_API_KEY is required when EMAIL_PROVIDER=resend.');
    }
    if (store == 'firestore' && gcpProject.isEmpty) {
      p.add('GCP_PROJECT is required when STORE=firestore.');
    }
    return p;
  }
}
