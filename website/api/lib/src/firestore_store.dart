import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart';

import 'store.dart';

/// Firestore storage. On Cloud Run it signs in automatically as the service's
/// service account (no key file needed).
///
/// Collections created (all prefixed `web_` so they never clash with the app):
///   web_otp/{key}            pending codes (deleted once used or replaced)
///   web_rate/{bucket}        hourly counters for rate limits
///   web_leads/{requestId}    every enquiry from the website
class FirestoreStore implements Store {
  final fs.FirestoreApi _api;
  final String _db;

  FirestoreStore._(this._api, String project) : _db = 'projects/$project/databases/(default)';

  static Future<FirestoreStore> connect(String project) async {
    final client = await clientViaApplicationDefaultCredentials(scopes: [fs.FirestoreApi.datastoreScope]);
    return FirestoreStore._(fs.FirestoreApi(client), project);
  }

  String _doc(String col, String id) => '$_db/documents/$col/${Uri.encodeComponent(id)}';

  static fs.Value _s(String v) => fs.Value(stringValue: v);
  static fs.Value _t(DateTime v) => fs.Value(timestampValue: v.toUtc().toIso8601String());
  static fs.Value _i(int v) => fs.Value(integerValue: '$v');

  @override
  Future<OtpRecord?> getOtp(String key) async {
    try {
      final d = await _api.projects.databases.documents.get(_doc('web_otp', key));
      final f = d.fields!;
      return OtpRecord(
        codeHash: f['codeHash']!.stringValue!,
        expiresAt: DateTime.parse(f['expiresAt']!.timestampValue!),
        sentAt: DateTime.parse(f['sentAt']!.timestampValue!),
        attempts: int.parse(f['attempts']!.integerValue!),
      );
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> putOtp(String key, OtpRecord rec) async {
    await _api.projects.databases.documents.patch(
      fs.Document(fields: {
        'codeHash': _s(rec.codeHash),
        'expiresAt': _t(rec.expiresAt),
        'sentAt': _t(rec.sentAt),
        'attempts': _i(rec.attempts),
      }),
      _doc('web_otp', key),
    );
  }

  @override
  Future<void> deleteOtp(String key) async {
    try {
      await _api.projects.databases.documents.delete(_doc('web_otp', key));
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  @override
  Future<int> hit(String bucket) async {
    final name = _doc('web_rate', hourBucket(bucket));
    final res = await _api.projects.databases.documents.commit(
      fs.CommitRequest(writes: [
        fs.Write(
          transform: fs.DocumentTransform(document: name, fieldTransforms: [
            fs.FieldTransform(fieldPath: 'count', increment: _i(1)),
          ]),
        ),
      ]),
      _db,
    );
    final v = res.writeResults?.first.transformResults?.first.integerValue;
    return int.tryParse(v ?? '1') ?? 1;
  }

  @override
  Future<bool> saveLead(String id, Map<String, Object?> lead) async {
    fs.Value conv(Object? v) {
      if (v == null) return fs.Value(nullValue: 'NULL_VALUE');
      if (v is DateTime) return _t(v);
      if (v is int) return _i(v);
      if (v is bool) return fs.Value(booleanValue: v);
      return _s('$v');
    }

    try {
      await _api.projects.databases.documents.commit(
        fs.CommitRequest(writes: [
          fs.Write(
            update: fs.Document(name: _doc('web_leads', id), fields: lead.map((k, v) => MapEntry(k, conv(v)))),
            currentDocument: fs.Precondition(exists: false),
          ),
        ]),
        _db,
      );
      return true;
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 409 || e.status == 400 && (e.message ?? '').contains('already exists')) return false;
      rethrow;
    }
  }
}
