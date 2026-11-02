import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the tenant/owner web app remembers in this browser (demo: no server yet).
///
/// Backend later: user = Firebase Auth user; trip = Firestore "rentals/{id}";
/// owner answers = "properties/{id}" + "papers".
class TkwSession extends ChangeNotifier {
  TkwSession._();
  static final instance = TkwSession._();

  static const _key = 'tkweb_session_v1';

  /// Signed-in person: name and phone/email (after OTP).
  String name = '';
  String contact = '';
  bool get signedIn => contact.isNotEmpty;

  /// Tenant journey per listing: step index into [TkwTrip.steps] + answers.
  final Map<String, Map<String, dynamic>> trips = {};

  /// Owner answers (owners, papers, keys) per house id.
  final Map<String, Map<String, dynamic>> owners = {};

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      name = j['name'] as String? ?? '';
      contact = j['contact'] as String? ?? '';
      trips
        ..clear()
        ..addAll({for (final e in (j['trips'] as Map? ?? {}).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)});
      owners
        ..clear()
        ..addAll({for (final e in (j['owners'] as Map? ?? {}).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)});
    } catch (_) {
      // A broken save starts fresh.
    }
  }

  Future<void> save() async {
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({'name': name, 'contact': contact, 'trips': trips, 'owners': owners}));
    } catch (_) {}
  }

  Future<void> signIn(String n, String c) {
    name = n.trim();
    contact = c.trim();
    return save();
  }

  Map<String, dynamic> trip(String listingId) => trips.putIfAbsent(listingId, () => {});
  Map<String, dynamic> owner(String houseId) => owners.putIfAbsent(houseId, () => {});

  /// Start over (demo reset on the landing page).
  Future<void> reset() async {
    name = '';
    contact = '';
    trips.clear();
    owners.clear();
    await save();
  }
}
