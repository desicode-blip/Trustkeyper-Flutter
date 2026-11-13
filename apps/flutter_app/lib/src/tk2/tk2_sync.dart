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
  final _queuedListings = <String>{};

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
        final code = e is FirebaseException ? e.code : 'failed';
        error.value = '$what: $code';
        debugPrint('TK2 sync: ${error.value}');
      }),
    );
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _dealsBy.clear();
  }

  void clearWebSession() {
    stop();
    inviteId = null;
    _inviteBroker = '';
    _inviteBrokerPhone = '';
    _inviteBrokerUid = '';
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
      visits.add(Tk2Visit.fromJson({
        ...j,
        'id': d.id,
        'code': code,
        'createdAt': Tk2Cloud.millis(j['createdAt']),
        'at': Tk2Cloud.millis(j['at']),
        'changedAt': j['status'] == VisitStatus.done ? Tk2Cloud.millis(j['doneAt']) : Tk2Cloud.millis(j['updatedAt']),
      }));
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

  /// The house owner filled this listing in from the broker's invite link.
  bool addedByOwner(String listingId) => _addedBy.containsKey(listingId);

  /// Saves a broker listing. The owner submits their draft at the last step.
  void listing(String id) {
    final l = store.listing(id);
    if (l == null || l.sample || _uid.isEmpty || inviteId != null) return;
    if (!_pending.add(id)) {
      _queuedListings.add(id);
      return;
    }
    _try(() async {
      try {
        await _writeListing(l, added: _addedBy[id]);
      } finally {
        _pending.remove(id);
        if (_queuedListings.remove(id)) listing(id);
      }
    }, 'listing $id');
  }

  Future<void> submitOwnerListing(String id, Map<String, dynamic> answers, {required String name, required String contact}) async {
    final invite = inviteId;
    final listing = store.listing(id);
    if (invite == null || listing == null || _uid.isEmpty) throw StateError('An owner invite is required');
    await _writeListing(listing, added: (ownerUid: _uid, inviteId: invite), ownerAnswers: {...answers, 'ownerName': name, 'ownerContact': contact});
  }

  Future<void> _writeListing(Tk2Listing listing, {required ({String ownerUid, String? inviteId})? added, Map<String, dynamic>? ownerAnswers}) async {
    final id = listing.id;
    final owner = ownerAnswers != null;
    final brokerUid = owner ? _inviteBrokerUid : _uid;
    final ref = _db.doc('tk2Listings/$id');
    Map<String, Object?> publicDoc(Tk2Listing l, {required bool active}) => Tk2Cloud.publicDoc(
      l.copyWith(token: l.tokenOr(store.defaultToken)),
      brokerUid: brokerUid,
      brokerName: owner ? _inviteBroker : store.brokerName,
      brokerPhone: owner ? _inviteBrokerPhone : store.brokerPhone,
      active: active,
      ownerUid: added?.ownerUid,
      inviteId: added?.inviteId,
    );

    // Storage checks the listing's ownership. A new draft stays inactive until
    // its photos and private answers have been saved.
    if (listing.photos.any((p) => !p.startsWith('http')) && !(await ref.get(const GetOptions(source: Source.server))).exists) {
      await ref.set(publicDoc(listing, active: false));
    }
    final uploaded = await Tk2Cloud.uploadPhotos(listing);
    final batch = _db.batch()
      ..set(ref, publicDoc(uploaded, active: store.isActive(id)))
      ..set(_db.doc('tk2Private/$id'), {
        'brokerUid': brokerUid,
        if (added != null) 'ownerUid': added.ownerUid,
        if (added?.inviteId != null) 'inviteId': added!.inviteId,
        if (added == null && !owner) 'ownerContact': _recipient(listing.ownerPhone),
        if (owner) 'ownerAnswers': ownerAnswers,
        'listing': uploaded.toJson(),
        'inactive': store.inactive(id)?.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    if (owner) {
      batch.update(_db.doc('tk2Invites/${added!.inviteId}'), {'ownerUid': _uid, 'listingId': id, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
    if (!identical(uploaded, listing) && identical(store.listing(id), listing)) store.replacePhotos(id, uploaded.photos);
  }

  void removeListing(String id) => _try(() async {
    await _db.doc('tk2Private/$id').delete();
    await _db.doc('tk2Listings/$id').delete();
  }, 'remove $id');

  /// "Send link to owner": saves the invite and returns its id for the link.
  Future<String> invite({required String houseName, required String ownerName, required String recipient}) async {
    final ref = _db.collection('tk2Invites').doc();
    await ref.set({
      'brokerUid': _uid,
      'brokerName': store.brokerName,
      'brokerPhone': store.brokerPhone,
      'houseName': houseName,
      'ownerName': ownerName,
      'recipient': _recipient(recipient),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String _recipient(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty || text.contains('@')) return text;
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return !text.startsWith('+') && digits.length == 10 ? '+91$digits' : '+$digits';
  }

  Future<void> visitStatus(String id, String status) =>
      _db.doc('tk2Visits/$id').update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});

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

  String _inviteBrokerUid = '';

  /// Verify ownership before using any invite details in this session.
  Future<({String brokerName, bool submitted})> claimInvite(String id, String ownerName) async {
    if (_uid.isEmpty) throw StateError('Sign in to open this invite');
    final ref = _db.doc('tk2Invites/$id');
    final j = await _db.runTransaction((tx) async {
      final data = (await tx.get(ref)).data();
      if (data == null || data['brokerUid'] == _uid) throw StateError('Invite unavailable');
      if (data['ownerUid'] != _uid) {
        tx.update(ref, {'ownerUid': _uid, 'ownerName': ownerName, 'updatedAt': FieldValue.serverTimestamp()});
      }
      return data;
    });
    inviteId = id;
    _inviteBroker = j['brokerName'] as String? ?? '';
    _inviteBrokerPhone = j['brokerPhone'] as String? ?? '';
    _inviteBrokerUid = j['brokerUid'] as String? ?? '';
    return (brokerName: _inviteBroker, submitted: j['listingId'] != null);
  }

  /// Web: follow own visits (with their codes) and own deals after signing in.
  /// One person can be a tenant in one deal and an owner in another.
  void startTenant() {
    if (_uid.isEmpty) return;
    stop();
    _subs.add(_visits(_db.collection('tk2Visits').where('customerUid', isEqualTo: _uid), withCodes: true));
    _subs.add(_deals('tenantUid'));
    _subs.add(_deals('verifiedOwnerUid'));
  }

  // ------------------------------------------------------------------ deals
  // tk2Deals/{id}: one document per finalised house. Each person writes only
  // their own part ('b' broker, 't' tenant, 'o' owner); the rules enforce it.

  final _dealsBy = <String, List<Tk2Deal>>{};

  StreamSubscription<Object?> _deals(String field, {bool block = false}) => _db.collection('tk2Deals').where(field, isEqualTo: _uid).snapshots().listen((q) {
    _dealsBy[field] = [
      for (final d in q.docs) _dealFromCloud(d.id, d.data()),
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
  DealRole? roleIn(Tk2Deal d) {
    if (_uid.isEmpty) return null;
    if (d.tenantUid == _uid) return DealRole.tenant;
    if (d.brokerUid == _uid) return DealRole.broker;
    return d.ownerUid == _uid ? DealRole.owner : null;
  }

  /// Sends what [role] changed. The broker may also correct the owner's name and number, and end the deal.
  void dealPart(Tk2Deal d, DealRole role) => _try(
    () => _db.doc('tk2Deals/${d.id}').update({
      Tk2Deal.who(role)[0]: _clientDealPart(d, role),
      if (role == DealRole.broker) ...{'ownerName': d.ownerName, 'ownerPhone': d.ownerPhone},
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    'deal ${d.id}',
  );

  /// Try to open as a party first. A verified owner can claim using only the
  /// id, so the deal contents remain private until the claim succeeds.
  Future<Tk2Deal?> openDeal(String id) async {
    if (_uid.isEmpty) return null;
    final ref = _db.doc('tk2Deals/$id');
    const server = GetOptions(source: Source.server);
    Map<String, dynamic>? j;
    try {
      j = (await ref.get(server)).data();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      try {
        await ref.update({'verifiedOwnerUid': _uid, 'updatedAt': FieldValue.serverTimestamp()});
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
      }
      j = (await ref.get(server)).data();
    }
    if (j == null) return null;
    final d = _dealFromCloud(id, j);
    brokerOf[d.listingId] = d.brokerUid;
    await store.putDeal(d);
    return d;
  }

  static const _completionFields = {
    DealRole.tenant: {'tokenPaid', 'tokenAt', 'paid', 'paidAt', 'signed', 'signedAt'},
    DealRole.owner: {'feePaid', 'feeAt', 'brokPaid', 'paidAt', 'signed', 'signedAt'},
  };

  Map<String, dynamic> _clientDealPart(Tk2Deal deal, DealRole role) {
    final client = {...deal.part(role)}..removeWhere((key, _) => _completionFields[role]?.contains(key) ?? false);
    if (role == DealRole.owner) {
      final replies = client.remove('rep') as Map? ?? const {};
      client['repairApprovals'] = {
        for (final entry in replies.entries)
          if (entry.value is Map && entry.value['ok'] is bool) '${entry.key}': entry.value['ok'],
      };
    }
    return client;
  }

  Tk2Deal _dealFromCloud(String id, Map<String, dynamic> data) {
    final completion = data['completion'] as Map? ?? const {};
    final deal = {...data, 'id': id, 'ownerUid': data['verifiedOwnerUid'], 'createdAt': Tk2Cloud.millis(data['createdAt'])};
    for (final entry in _completionFields.entries) {
      final key = Tk2Deal.who(entry.key)[0];
      final client = Map<String, dynamic>.from(data[key] as Map? ?? const {});
      final server = completion[key] as Map? ?? const {};
      client.removeWhere((key, _) => entry.value.contains(key));
      if (entry.key == DealRole.owner) {
        final approvals = client.remove('repairApprovals') as Map? ?? const {};
        final payments = server['rep'] as Map? ?? const {};
        client['rep'] = {
          for (final id in {...approvals.keys, ...payments.keys})
            '$id': {
              if (approvals[id] is bool) 'ok': approvals[id],
              if (payments[id] is Map && payments[id]['paid'] == true) ...{'paid': true, 'at': payments[id]['at']},
            },
        };
      }
      deal[key] = {...client, for (final field in entry.value) if (server.containsKey(field)) field: server[field]};
    }
    return Tk2Deal.fromJson(deal);
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
    final phone = Tk2Cloud.auth.currentUser?.phoneNumber;
    if (phone == null) throw StateError('A verified phone is required to book');
    final batch = _db.batch();
    batch.set(ref, {
      'listingId': v.listingId,
      'brokerUid': brokerOf[v.listingId] ?? '',
      'customerUid': _uid,
      'customerName': v.customerName,
      'customerPhone': phone,
      'at': v.at,
      'fee': v.fee,
      'status': v.status,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('secret').doc('code'), {'code': v.code});
    await batch.commit();
  }

  /// Tenant journeys kept by the web session.
  void session(Map<String, Map<String, dynamic>> trips) {
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
