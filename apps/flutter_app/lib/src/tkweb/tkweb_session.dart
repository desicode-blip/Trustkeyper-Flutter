import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tk2/tk2_cloud.dart';
import '../tk2/tk2_deal.dart';
import '../tk2/tk2_store.dart';

/// What the tenant/owner web app remembers in this browser. With the backend
/// on, the login is Firebase Auth and every save is also sent to Firestore:
/// trips → tk2Trips, owner answers → tk2Private (see [Tk2Sync.session]).
class TkwSession extends ChangeNotifier {
  TkwSession._();
  static final instance = TkwSession._();

  static const _key = 'tkweb_session_v1';
  String? _uid;

  /// Signed-in person: name and phone/email (after OTP).
  String name = '';
  String contact = '';
  bool get signedIn => contact.isNotEmpty && (!Tk2Cloud.on || _uid != null && Tk2Cloud.uid == _uid);

  /// Tenant journey per listing: step index into [TkwTrip.steps] + answers.
  final Map<String, Map<String, dynamic>> trips = {};

  /// Owner answers (owners, papers, keys) per house id.
  final Map<String, Map<String, dynamic>> owners = {};

  /// Demo build: which side of each deal this browser is on ('tenant' or
  /// 'owner'), by deal id. With the backend the login decides.
  final Map<String, String> roles = {};

  /// This person's side of [d], or null when the deal is not theirs.
  DealRole? roleIn(Tk2Deal d) {
    final sync = Tk2Store.instance.sync;
    if (sync != null) return sync.roleIn(d);
    return switch (roles[d.id]) {
      'owner' => DealRole.owner,
      'tenant' => DealRole.tenant,
      _ => null,
    };
  }

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (Tk2Cloud.on && (Tk2Cloud.uid == null || j['uid'] != Tk2Cloud.uid)) return;
      _uid = j['uid'] as String?;
      name = j['name'] as String? ?? '';
      contact = j['contact'] as String? ?? '';
      trips
        ..clear()
        ..addAll({for (final e in (j['trips'] as Map? ?? {}).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)});
      owners
        ..clear()
        ..addAll({for (final e in (j['owners'] as Map? ?? {}).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)});
      roles
        ..clear()
        ..addAll({for (final e in (j['roles'] as Map? ?? {}).entries) e.key as String: '${e.value}'});
    } catch (_) {
      // A broken save starts fresh.
    }
  }

  Future<void> save() async {
    notifyListeners();
    Tk2Store.instance.sync?.session(trips);
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({'uid': _uid, 'name': name, 'contact': contact, 'trips': trips, 'owners': owners, 'roles': roles}));
    } catch (_) {}
  }

  Future<void> signIn(String n, String c) async {
    final store = Tk2Store.instance;
    if (Tk2Cloud.on && _uid != Tk2Cloud.uid) {
      store.sync?.clearWebSession();
      store.applyDeals([]);
      store.applyVisits([]);
      trips.clear();
      owners.clear();
      roles.clear();
    }
    _uid = Tk2Cloud.uid;
    name = n.trim();
    contact = c.trim();
    store.sync?.startTenant();
    return save();
  }

  Map<String, dynamic> trip(String listingId) => trips.putIfAbsent(listingId, () => {});
  Map<String, dynamic> owner(String houseId) => owners.putIfAbsent(houseId, () => {});

  /// Start over (demo reset on the landing page; logs out with the backend on).
  Future<void> reset() async {
    Tk2Store.instance.sync?.clearWebSession();
    if (Tk2Cloud.on) await Tk2Store.instance.signOut();
    _uid = null;
    name = '';
    contact = '';
    trips.clear();
    owners.clear();
    roles.clear();
    await save();
  }
}
