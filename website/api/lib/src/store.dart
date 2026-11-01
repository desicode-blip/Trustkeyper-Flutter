/// Storage used by the API. Production uses Firestore (firestore_store.dart);
/// tests and local runs use [MemoryStore].
abstract class Store {
  /// Pending OTP for a contact, or null.
  Future<OtpRecord?> getOtp(String key);
  Future<void> putOtp(String key, OtpRecord rec);
  Future<void> deleteOtp(String key);

  /// Adds one hit to a named counter for the current hour and returns the new
  /// count. Used for rate limits (per contact, per IP).
  Future<int> hit(String bucket);

  /// Saves an enquiry. Returns false if [id] was already saved (duplicate
  /// submit / retry), so it is not stored or emailed twice.
  Future<bool> saveLead(String id, Map<String, Object?> lead);
}

class OtpRecord {
  final String codeHash;
  final DateTime expiresAt;
  final DateTime sentAt;
  final int attempts;
  OtpRecord({required this.codeHash, required this.expiresAt, required this.sentAt, this.attempts = 0});
  OtpRecord withAttempts(int a) => OtpRecord(codeHash: codeHash, expiresAt: expiresAt, sentAt: sentAt, attempts: a);
}

String hourBucket(String name, [DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc();
  return '$name|${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}${t.hour.toString().padLeft(2, '0')}';
}

class MemoryStore implements Store {
  final otps = <String, OtpRecord>{};
  final counters = <String, int>{};
  final leads = <String, Map<String, Object?>>{};

  @override
  Future<OtpRecord?> getOtp(String key) async => otps[key];
  @override
  Future<void> putOtp(String key, OtpRecord rec) async => otps[key] = rec;
  @override
  Future<void> deleteOtp(String key) async => otps.remove(key);
  @override
  Future<int> hit(String bucket) async {
    final k = hourBucket(bucket);
    return counters[k] = (counters[k] ?? 0) + 1;
  }

  @override
  Future<bool> saveLead(String id, Map<String, Object?> lead) async {
    if (leads.containsKey(id)) return false;
    leads[id] = lead;
    return true;
  }
}
