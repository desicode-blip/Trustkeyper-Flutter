import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool downloadText(String name, String text) {
  final blob = web.Blob([text.toJS].toJS, web.BlobPropertyBag(type: 'application/json'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}

@JS('tkLoadLeads')
external JSPromise<JSString?>? _load(JSString pass, JSString skip);

@JS('tkLeadBatches')
external JSPromise<JSString>? _batches();

Future<String?> openPublishedLeads(String password, List<String> skip) async {
  try {
    final p = _load(password.toJS, skip.join(',').toJS);
    if (p == null) return null;
    return (await p.toDart)?.toDart;
  } catch (_) {
    return null;
  }
}

Future<List<String>> publishedBatches() async {
  try {
    final p = _batches();
    if (p == null) return const [];
    final s = (await p.toDart).toDart;
    return s.isEmpty ? const [] : s.split(',');
  } catch (_) {
    return const [];
  }
}
