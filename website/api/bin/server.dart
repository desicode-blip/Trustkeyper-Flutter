import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:trustkeyper_web_api/trustkeyper_web_api.dart';

Future<void> main() async {
  final c = Config.fromEnv();
  final problems = c.problems();
  if (problems.isNotEmpty) {
    stderr.writeln('Configuration problems:\n- ${problems.join('\n- ')}');
    exit(1);
  }

  final Store store = c.store == 'firestore' ? await FirestoreStore.connect(c.gcpProject) : MemoryStore();
  final SmsSender sms = c.smsProvider == 'msg91' ? Msg91Sms(c) : ConsoleSms();
  final EmailSender email = c.emailProvider == 'resend' ? ResendEmail(c) : ConsoleEmail();

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(Api(c, store, sms, email).handler);
  final server = await io.serve(handler, InternetAddress.anyIPv4, c.port);
  print('TrustKeyper web API listening on :${server.port} (store=${c.store}, sms=${c.smsProvider}, email=${c.emailProvider})');
}
