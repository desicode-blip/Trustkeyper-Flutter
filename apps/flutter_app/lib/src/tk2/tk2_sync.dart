import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'tk2_cloud.dart';
import 'tk2_deal.dart';
import 'tk2_link.dart';
import 'tk2_store.dart';

/// Keeps [Tk2Store] in step with Firestore when the backend is on.
/// Screens never call this: the store does, after it saves on the device, so
/// the app keeps working offline and the design is unchanged.
///
/// Three users of one store:
/// - broker app: own profile, listings (private docs) and visits, live
/// - tenant web: listing opened from a link (public doc), own visits, live
/// - owner web: the invite, and the house the owner adds for that broker
class Tk2Sync {
  Tk2Sync(this.store);
  final Tk2Store store;

  FirebaseFirestore get _db => Tk2Cloud.db;
  String get _uid => Tk2Cloud.uid ?? '';
  final _subs = <StreamSubscription<Object?>>[];

  /// Listings being uploaded: a live update must not undo them on screen.
  final _pending = <String>{};

  /// Broker of each listing opened on the web (needed to book a visit).
  final brokerOf = <String, String>{};

  /// Owner web: the invite this owner is answering.
  String? inviteId;
  String _inviteBroker = '';
  String _inviteBrokerPhone = '';

  /// Last error, for the debug console (writes retry on the next save).
  final error = ValueNotifier<String?>(null);

  void _try(Future<void> Function() job, String what) {
    unawaited(
      job().then((_) => error.value = null).catchError((Object e) {
        error.value = '$what: $e';
        debugPrint('TK2 sync – ${error.value}');
      }),
    );
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  // ------------------------------------------------------------- broker app

  /// After login: bring the saved profile, then follow listings and visits.
  /// Returns true when this phone number already had a TK2 profile.
  Future<bool> startBroker() async {
    stop();
    final doc = await _db.doc('tk2Brokers/$_uid').get();
    final saved = doc.data();
    if (saved != null && (saved['name'] as String? ?? '').isNotEmpty) {
      store.applyProfile(saved);
    } else {
      profile();
    }
    _subs.add(
      _db.collection('tk2Private').where('brokerUid', isEqualTo: _uid).snapshots().listen((q) {
        final listings = <Tk2Listing>[];
        final off = <String, Tk2Inactive>{};
        for (final d in q.docs) {
          final j = d.data();
          if (j['ownerUid'] is String) _addedBy[d.id] = (ownerUid: j['ownerUid'] as String, inviteId: j['inviteId'] as String?);
          final l = Tk2Listing.fromJson(Map<String, dynamic>.from(j['listing'] as Map? ?? const {}));
          listings.add(j['ownerAnswers'] is Map ? tk2WithOwnerAnswers(l, Map<String, dynamic>.from(j['ownerAnswers'] as Map)) : l);
          if (j['inactive'] is Map) off[d.id] = Tk2Inactive.fromJson(Map<String, dynamic>.from(j['inactive'] as Map));
        }
        listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        store.applyListings(listings, off, keep: _pending);
      }, onError: (Object e) => error.value = 'listings: $e'),
    );
    _subs.add(_visits(_db.collection('tk2Visits').where('brokerUid', isEqualTo: _uid)));
    _subs.add(_deals('brokerUid', block: true));
    return saved != null && (saved['name'] as String? ?? '').isNotEmpty;
  }

  StreamSubscription<Object?> _visits(Query<Map<String, dynamic>> q, {bool withCodes = false}) => q.snapshots().listen((s) async {
    final visits = <Tk2Visit>[];
    for (final d in s.docs) {
      final j = d.data();
      var code = '';
      // The code doc can lag the visit by a moment; the code we made is kept then.
      if (withCodes && !d.metadata.hasPendingWrites) {
        try {
          code = (await d.reference.collection('secret').doc('code').get()).data()?['code'] as String? ?? '';
        } catch (_) {}
      }
      visits.add(Tk2Visit.fromJson({...j, 'id': d.id, 'code': code, 'createdAt': Tk2Cloud.millis(j['createdAt']), 'at': Tk2Cloud.millis(j['at'])}));
    }
    store.applyVisits(visits);
  }, onError: (Object e) => error.value = 'visits: $e');

  /// Name, phone, default token, contacts and account details.
  void profile() {
    if (_uid.isEmpty) return;
    _try(() => _db.doc('tk2Brokers/$_uid').set({...store.profileJson(), 'updatedAt': FieldValue.serverTimestamp()}), 'profile');
  }

  /// Houses an owner added from an invite (kept on every later save).
  final _addedBy = <String, ({String ownerUid, String? inviteId})>{};

  /// Saves one listing: photos first, then the public and private documents.
  void listing(String id) {
    final l = store.listing(id);
    if (l == null || l.sample || _uid.isEmpty) return;
    _pending.add(id);
    _try(() async {
      try {
        final up = await Tk2Cloud.uploadPhotos(l);
        if (!identical(up, l)) store.replacePhotos(id, up.photos);
        final owner = inviteId != null;
        final brokerUid = owner ? _inviteBrokerUid : _uid;
        if (owner) brokerOf[id] = brokerUid;
        final added = owner ? (ownerUid: _uid, inviteId: inviteId) : _addedBy[id];
        await _db
            .doc('tk2Listings/$id')
            .set(
              Tk2Cloud.publicDoc(
                up.copyWith(token: up.tokenOr(store.defaultToken)),
                brokerUid: brokerUid,
                brokerName: owner ? _inviteBroker : store.brokerName,
                brokerPhone: owner ? _inviteBrokerPhone : store.brokerPhone,
                active: store.isActive(id),
                ownerUid: added?.ownerUid,
                inviteId: added?.inviteId,
              ),
            );
        // Private doc after the public one (the rules check the listing exists).
        await _db.doc('tk2Private/$id').set({
          'brokerUid': brokerUid,
          if (added != null) 'ownerUid': added.ownerUid,
          if (added?.inviteId != null) 'inviteId': added!.inviteId,
          'listing': up.toJson(),
          'inactive': store.inactive(id)?.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (owner) await _db.doc('tk2Invites/$inviteId').update({'ownerUid': _uid, 'listingId': id, 'updatedAt': FieldValue.serverTimestamp()});
      } finally {
        _pending.remove(id);
      }
    }, 'listing $id');
  }

  void removeListing(String id) => _try(() async {
    await _db.doc('tk2Private/$id').delete();
    await _db.doc('tk2Listings/$id').delete();
  }, 'remove $id');

  /// "Send link to owner": saves the invite and returns its id for the link.
  String invite({required String houseName, required String ownerName}) {
    final ref = _db.collection('tk2Invites').doc();
    _try(
      () => ref.set({
        'brokerUid': _uid,
        'brokerName': store.brokerName,
        'brokerPhone': store.brokerPhone,
        'houseName': houseName,
        'ownerName': ownerName,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      'invite',
    );
    return ref.id;
  }

  void visitStatus(String id, String status) =>
      _try(() => _db.doc('tk2Visits/$id').update({'status': status, 'updatedAt': FieldValue.serverTimestamp()}), 'visit $id');

  Future<String> gatePass(String visitId, String path) async {
    final url = await Tk2Cloud.uploadGatePass(visitId, path);
    await _db.doc('tk2Visits/$visitId').update({'gatePass': url, 'updatedAt': FieldValue.serverTimestamp()});
    return url;
  }

  /// Delete account: the broker's listings and profile go; visit records stay
  /// (money history). Then the login itself is removed.
  Future<void> deleteAccount() async {
    stop();
    final mine = await _db.collection('tk2Private').where('brokerUid', isEqualTo: _uid).get();
    for (final d in mine.docs) {
      await d.reference.delete();
      await _db.doc('tk2Listings/${d.id}').delete();
    }
    await _db.doc('tk2Brokers/$_uid').delete();
    try {
      await Tk2Cloud.auth.currentUser?.delete();
    } catch (_) {
      await Tk2Cloud.signOut(); // needs a fresh login to delete; data is already gone
    }
  }

  // ---------------------------------------------------------------- web app

  /// Tenant link #l-ID: the public listing (null when removed or turned off).
  Future<Tk2Listing?> openListing(String id) async {
    final j = (await _db.doc('tk2Listings/$id').get()).data();
    if (j == null) return null;
    // Off the market: only the tenant who blocked it can still open it.
    if (j['active'] == false) {
      final mine = _uid.isNotEmpty && await _db.doc('tk2Deals/${_uid}_$id').get().then((d) => d.exists).catchError((Object _) => false);
      if (!mine) return null;
    }
    brokerOf[id] = j['brokerUid'] as String? ?? '';
    store.brokerName = j['bn'] as String? ?? '';
    store.brokerPhone = j['bp'] as String? ?? '';
    return tk2ListingFromPublic(j);
  }

  /// Owner link #i-ID: the broker and house name (null when not found).
  Future<({String brokerName, String houseName})?> openInvite(String id) async {
    final j = (await _db.doc('tk2Invites/$id').get()).data();
    if (j == null) return null;
    inviteId = id;
    _inviteBroker = j['brokerName'] as String? ?? '';
    _inviteBrokerPhone = j['brokerPhone'] as String? ?? '';
    _inviteBrokerUid = j['brokerUid'] as String? ?? '';
    return (brokerName: _inviteBroker, houseName: j['houseName'] as String? ?? '');
  }

  String _inviteBrokerUid = '';

  /// After the owner signs in: claim the invite, so the house they add is the broker's.
  Future<void> claimInvite(String ownerName) async {
    if (inviteId == null || _uid.isEmpty) return;
    await _db.doc('tk2Invites/$inviteId').update({'ownerUid': _uid, 'ownerName': ownerName, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Web: follow own visits (with their codes) and own deals after signing in.
  /// One person can be a tenant in one deal and an owner in another.
  void startTenant() {
    if (_uid.isEmpty) return;
    stop();
    _subs.add(_visits(_db.collection('tk2Visits').where('customerUid', isEqualTo: _uid), withCodes: true));
    _subs.add(_deals('tenantUid'));
    _subs.add(_deals('ownerUid'));
  }

  // ------------------------------------------------------------------ deals
  // tk2Deals/{id}: one document per finalised house. Each person writes only
  // their own part ('b' broker, 't' tenant, 'o' owner); the rules enforce it.

  final _dealsBy = <String, List<Tk2Deal>>{};

  StreamSubscription<Object?> _deals(String field, {bool block = false}) => _db.collection('tk2Deals').where(field, isEqualTo: _uid).snapshots().listen((q) {
    _dealsBy[field] = [
      for (final d in q.docs) Tk2Deal.fromJson({...d.data(), 'id': d.id, 'createdAt': Tk2Cloud.millis(d.data()['createdAt'])}),
    ];
    final all = {
      for (final list in _dealsBy.values)
        for (final d in list) d.id: d,
    };
    store.applyDeals(all.values.toList(), block: block);
  }, onError: (Object e) => error.value = 'deals: $e');

  /// Whose listing this is (the broker's own, or the one a tenant opened).
  String brokerUidFor(String listingId) => brokerOf[listingId] ?? (inviteId == null ? _uid : _inviteBrokerUid);

  /// Which side of [d] the signed-in person is on (web).
  DealRole roleIn(Tk2Deal d) => d.tenantUid == _uid ? DealRole.tenant : (d.brokerUid == _uid ? DealRole.broker : DealRole.owner);

  void createDeal(Tk2Deal d) =>
      _try(() => _db.doc('tk2Deals/${d.id}').set({...d.toJson()..remove('id'), 'createdAt': FieldValue.serverTimestamp()}), 'deal ${d.id}');

  /// Sends what [role] changed. The broker may also correct the owner's name and number, and end the deal.
  void dealPart(Tk2Deal d, DealRole role) => _try(
    () => _db.doc('tk2Deals/${d.id}').update({
      Tk2Deal.who(role)[0]: d.part(role),
      if (role == DealRole.broker) ...{'ownerName': d.ownerName, 'ownerPhone': d.ownerPhone},
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    'deal ${d.id}',
  );

  /// Web link #d-ID: the deal, for its tenant or its owner. The first owner to
  /// open it (matching the owner's phone, when the broker saved one) claims it.
  Future<Tk2Deal?> openDeal(String id) async {
    if (_uid.isEmpty) return null;
    final ref = _db.doc('tk2Deals/$id');
    var j = (await ref.get()).data();
    if (j == null) return null;
    if (j['tenantUid'] != _uid && j['ownerUid'] == null) {
      await ref.update({'ownerUid': _uid, 'updatedAt': FieldValue.serverTimestamp()});
      j = (await ref.get()).data()!;
    }
    final d = Tk2Deal.fromJson({...j, 'id': id, 'createdAt': Tk2Cloud.millis(j['createdAt'])});
    brokerOf[d.listingId] = d.brokerUid;
    await store.putDeal(d);
    return d;
  }

  static String _slug(String society) => society.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  /// A society's shared steps (null when no broker has written them yet).
  Future<List<dynamic>?> fetchPlaybook(String society) async {
    if (_slug(society).length < 2) return null;
    final j = (await _db.doc('tk2Playbooks/${_slug(society)}').get()).data();
    return j == null ? null : List<dynamic>.from(j['steps'] as List? ?? const []);
  }

  /// Shares a society's steps with other brokers. The first broker creates
  /// the playbook; later edits are kept as 'proposed' until TrustKeyper checks
  /// them (the team copies them into 'steps').
  void playbook(String society, List<dynamic> steps) => _try(() async {
    final ref = _db.doc('tk2Playbooks/${_slug(society)}');
    final mine = {'brokerUid': _uid, 'steps': steps, 'at': FieldValue.serverTimestamp()};
    if ((await ref.get()).exists) {
      await ref.update({'proposed': mine, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await ref.set({'name': society.trim(), 'steps': steps, 'brokerUid': _uid, 'checked': false, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }, 'playbook $society');

  /// Tenant books: the visit, then its code (only the tenant can read it).
  /// Payment is still a test (see docs).
  Future<void> bookVisit(Tk2Visit v) async {
    final ref = _db.doc('tk2Visits/${v.id}');
    await ref.set({
      'listingId': v.listingId,
      'brokerUid': brokerOf[v.listingId] ?? '',
      'customerUid': _uid,
      'customerName': v.customerName,
      'customerPhone': v.customerPhone,
      'at': v.at,
      'fee': v.fee,
      'status': v.status,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.collection('secret').doc('code').set({'code': v.code});
  }

  /// Tenant journey and owner answers kept by the web session. The owner's
  /// name and number go with their answers, for the broker's private block.
  void session(Map<String, Map<String, dynamic>> trips, Map<String, Map<String, dynamic>> owners, {String name = '', String contact = ''}) {
    if (_uid.isEmpty) return;
    for (final e in trips.entries) {
      final broker = brokerOf[e.key];
      if (broker == null || broker.isEmpty) continue;
      _try(
        () => _db.doc('tk2Trips/${_uid}_${e.key}').set({
          'customerUid': _uid,
          'brokerUid': broker,
          'listingId': e.key,
          'answers': e.value,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        'trip ${e.key}',
      );
    }
    for (final e in owners.entries) {
      if (!brokerOf.containsKey(e.key)) continue;
      _try(
        () => _db.doc('tk2Private/${e.key}').update({
          'ownerAnswers': {...e.value, 'ownerName': name, 'ownerContact': contact},
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        'owner ${e.key}',
      );
    }
  }
}

/// A house the owner added: their name, number and who has the keys fill the
/// broker's private block, unless the broker already typed them.
Tk2Listing tk2WithOwnerAnswers(Tk2Listing l, Map<String, dynamic> a) {
  String t(String k) => (a[k] as String? ?? '').trim();
  final keys = switch (t('keys')) {
    'Me' => 'With owner',
    'Security' => 'With security',
    _ => '',
  };
  final who = [t('keys'), t('keyName'), t('keyPhone')].where((x) => x.isNotEmpty && x != 'Me').join(' · ');
  final note = [if (who.isNotEmpty) 'Keys: $who', if (t('keyNote').isNotEmpty) t('keyNote')].join('\n');
  return l.copyWith(
    ownerName: l.ownerName.isEmpty ? t('ownerName') : null,
    ownerPhone: l.ownerPhone.isEmpty && !t('ownerContact').contains('@') ? t('ownerContact') : null,
    keys: l.keys.isEmpty && keys.isNotEmpty ? keys : null,
    note: l.note.isEmpty && note.isNotEmpty ? note : null,
  );
}
