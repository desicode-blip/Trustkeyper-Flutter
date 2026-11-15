import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../tk2/tk2_cloud.dart';
import '../tk2/tk2_store.dart';
import 'tkdesk_import.dart';
import 'tkdesk_lead.dart';
import 'tkdesk_match.dart';
import 'tkdesk_web.dart';

/// The desk's data: leads, their history, call notes, imports and the
/// "send" log. Rule from Aman: nothing a salesperson types may ever be lost.
/// - Saved on the device at once (offline first, like Tk2Store).
/// - With the backend on, every lead is also written to Firestore `tk2Leads`.
/// - Nothing is ever deleted: delete, cancel and "not active" only change a status.
/// - Every edit is kept in the lead's history (old value, new value, time).
/// - Download everything / restore, and a daily backup reminder.
class DeskStore extends ChangeNotifier {
  DeskStore(this.app);
  static final instance = DeskStore(Tk2Store.instance);

  final Tk2Store app;
  static const _key = 'tkdesk_v1';

  final Map<String, Lead> _leads = {};
  final List<Map<String, dynamic>> sendLog = [];
  final List<Map<String, dynamic>> imports = [];
  final Set<String> loadedBatches = {};
  int lastBackup = 0;
  bool loaded = false;

  Iterable<Lead> get leads => _leads.values;
  Lead? byId(String id) => _leads[id] ?? (id.startsWith('tk2:') ? _fromListing(id.substring(4)) : null);

  List<Lead> get tenants => leads.where((l) => l.isTenant).toList()..sort((a, b) => b.changed.compareTo(a.changed));

  /// Home leads plus the broker's own TK2 properties, so both are matched.
  List<Lead> get homes {
    final out = leads.where((l) => l.isHome).toList();
    final linked = {for (final l in out) l.listingId};
    for (final x in app.listings) {
      if (x.sample || linked.contains(x.id)) continue;
      final l = _fromListing(x.id);
      if (l != null) out.add(l);
    }
    return out..sort((a, b) => b.changed.compareTo(a.changed));
  }

  List<Lead> get activeHomes => homes.where((h) => h.status == HomeState.active).toList();

  /// A TK2 property seen as a home lead (read only on the desk).
  Lead? _fromListing(String id) {
    final x = app.listing(id);
    if (x == null) return null;
    final p = x.property;
    final who = x.tenants.toLowerCase();
    return Lead(
      id: 'tk2:${x.id}',
      kind: LeadKind.home,
      status: app.isActive(x.id) ? HomeState.active : HomeState.inactive,
      at: x.createdAt,
      changed: x.createdAt,
      listingId: x.id,
      source: {'type': 'Your properties', 'group': 'TrustKeyper app'},
      f: {
        'society': x.society.isNotEmpty ? x.society : p.society,
        'area': x.locality.isNotEmpty ? x.locality : p.area,
        'flat': x.door.isNotEmpty ? x.door : p.flat,
        'bhk': toNum(p.rooms),
        'rent': x.rent,
        'maint': x.maintenance,
        'maintIncl': x.maintenanceIncluded,
        'furnishing': switch (p.furnishing.toLowerCase()) {
          'full' => 'fully furnished',
          'semi' => 'semi-furnished',
          'empty' => 'unfurnished',
          final f => f,
        },
        'sqft': p.sizeSqFt,
        'floor': p.floor,
        'floors': p.totalFloors,
        'facing': p.facing,
        'parking': p.carParking,
        'who': who.contains('famil') ? 'family' : (who.contains('bachelor') ? 'bachelors' : 'any'),
        'pets': x.pets,
        'availableFrom': x.availableFrom,
        'ownerName': x.ownerName,
        'ownerPhone': x.ownerPhone,
        'keys': x.keys,
        'remarks': x.note,
      }..removeWhere((k, v) => v == null || v == ''),
    );
  }

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    teamPass = prefs.getString(_passKey) ?? '';
    final raw = prefs.getString(_key);
    if (raw != null) _apply(jsonDecode(raw) as Map<String, dynamic>, replace: true);
    loaded = true;
    notifyListeners();
    await _pull();
    // See colleagues' changes without reloading (web desk only).
    if (kIsWeb) {
      _timer ??= Timer.periodic(const Duration(seconds: 60), (_) {
        if (teamPass.isNotEmpty) refresh();
      });
    }
  }

  void _apply(Map<String, dynamic> j, {required bool replace}) {
    if (replace) {
      _leads.clear();
      sendLog.clear();
      imports.clear();
      loadedBatches.clear();
    }
    for (final e in (j['leads'] as List? ?? const [])) {
      final l = Lead.fromJson(Map<String, dynamic>.from(e as Map));
      final old = _leads[l.id];
      if (old == null || old.changed <= l.changed) _leads[l.id] = l;
    }
    sendLog.addAll([for (final e in (j['sendLog'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)]);
    imports.addAll([for (final e in (j['imports'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)]);
    loadedBatches.addAll([for (final e in (j['loadedBatches'] as List? ?? const [])) e.toString()]);
    lastBackup = max(lastBackup, (j['lastBackup'] as num? ?? 0).toInt());
  }

  Map<String, dynamic> toJson() => {
    'format': 'tk-desk-1',
    'savedAt': DateTime.now().toIso8601String(),
    'leads': [for (final l in _leads.values) l.toJson()],
    'sendLog': sendLog,
    'imports': imports,
    'loadedBatches': loadedBatches.toList(),
    'lastBackup': lastBackup,
  };

  /// One file with everything typed on the desk (TK Lead Format + history).
  String exportAll() => const JsonEncoder.withIndent(' ').convert(toJson());

  /// Brings back a downloaded file. Newer edits on this device are kept.
  int restore(String text) {
    final before = _leads.length;
    _apply(jsonDecode(text) as Map<String, dynamic>, replace: false);
    _save(all: true);
    return _leads.length - before;
  }

  void markBackedUp() {
    lastBackup = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  bool get backupDue => _leads.isNotEmpty && DateTime.now().millisecondsSinceEpoch - lastBackup > const Duration(hours: 20).inMilliseconds;

  /// Saves on the device, then (backend on) the changed leads to Firestore.
  Future<void> _save({Iterable<Lead> changed = const [], bool all = false}) async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
    await _push(all ? _leads.values : changed);
  }

  /// True when leads also go to the cloud: the team storage (web build on
  /// app.trustkeyper.com) or Ajay's Firestore (backend build, signed in).
  bool get cloud => teamCloud || (Tk2Cloud.on && Tk2Cloud.uid != null);

  // ---- Team storage: /api/leads on the same site (Cloudflare, tool/tkdesk/_worker.js) ----
  static const _passKey = 'tkdesk_team_pass';
  String teamPass = '';
  bool teamCloud = false;
  String cloudError = '';
  DateTime? lastSync;

  /// Server time of the last fetch: the next one asks only for newer saves.
  int _since = 0;
  Timer? _timer;

  Uri _api(String path) => Uri.base.resolve(path);

  /// Connects this laptop to the team storage with the team password.
  Future<bool> connect(String pass) async {
    teamPass = pass.trim();
    _since = 0;
    final ok = await _pullTeam();
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_passKey, teamPass);
      // Anything typed here before connecting goes up now.
      await _push(_leads.values);
      await loadPublished();
    } else {
      teamPass = '';
    }
    notifyListeners();
    return ok;
  }

  Future<bool> _pullTeam() async {
    if (teamPass.isEmpty || !kIsWeb) return false;
    try {
      final r = await http.get(_api('api/leads?since=$_since'), headers: {'x-tk-pass': teamPass});
      if (r.statusCode != 200) {
        teamCloud = false;
        cloudError = r.statusCode == 401 ? 'Wrong team password' : 'Team storage not reachable (${r.statusCode})';
        return false;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _apply({'leads': j['leads'] as List? ?? const []}, replace: false);
      _since = (j['at'] as num? ?? 0).toInt();
      teamCloud = true;
      cloudError = '';
      lastSync = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
      return true;
    } catch (e) {
      teamCloud = false;
      cloudError = 'Team storage not reachable';
      return false;
    }
  }

  /// Adds lead batches the team published on the site (encrypted; opened
  /// with the team password). Each batch is added once per device; leads
  /// already on the desk only get empty details filled.
  Future<int> loadPublished() async {
    if (teamPass.isEmpty) return 0;
    final waiting = (await publishedBatches()).where((b) => !loadedBatches.contains(b)).toList();
    if (waiting.isEmpty) return 0;
    final text = await openPublishedLeads(teamPass, loadedBatches.toList());
    if (text == null) return 0;
    final j = jsonDecode(text) as Map<String, dynamic>;
    final p = parseLeadFile(jsonEncode(j['data']));
    final (added, _, _) = importLeads(p.leads, by: 'Published (team)', file: (j['files'] as List).join(', '), rejected: p.rejected.length);
    loadedBatches.addAll([for (final x in j['files'] as List) x.toString()]);
    await _save();
    return added;
  }

  /// Fetches what others on the team changed.
  Future<void> refresh() async {
    if (await _pullTeam()) notifyListeners();
  }

  Future<void> _push(Iterable<Lead> changed) async {
    final list = [
      for (final l in changed)
        if (!l.id.startsWith('tk2:')) l,
    ];
    if (list.isEmpty) return;
    if (teamPass.isNotEmpty && kIsWeb) {
      try {
        final r = await http.post(
          _api('api/leads'),
          headers: {'x-tk-pass': teamPass, 'content-type': 'application/json'},
          body: jsonEncode({
            'leads': [for (final l in list) l.toJson()],
            'by': app.brokerName,
          }),
        );
        teamCloud = r.statusCode == 200;
        cloudError = teamCloud ? '' : 'Not saved to the cloud (${r.statusCode}). Saved on this laptop.';
        if (teamCloud) lastSync = DateTime.now();
      } catch (e) {
        teamCloud = false;
        cloudError = 'Offline: saved on this laptop, will go up with the next change.';
      }
      notifyListeners();
    }
    if (!(Tk2Cloud.on && Tk2Cloud.uid != null)) return;
    final db = FirebaseFirestore.instance;
    for (final l in list) {
      try {
        await db.collection('tk2Leads').doc(l.id).set({...l.toJson(), 'brokerUid': Tk2Cloud.uid});
      } catch (e) {
        debugPrint('tk2Leads write failed: $e');
      }
    }
  }

  Future<void> _pull() async {
    if (teamPass.isNotEmpty) {
      if (await _pullTeam()) await loadPublished();
      notifyListeners();
    }
    if (!(Tk2Cloud.on && Tk2Cloud.uid != null)) return;
    try {
      final q = await FirebaseFirestore.instance.collection('tk2Leads').where('brokerUid', isEqualTo: Tk2Cloud.uid).get();
      _apply({
        'leads': [for (final d in q.docs) d.data()],
      }, replace: false);
      notifyListeners();
    } catch (e) {
      debugPrint('tk2Leads read failed: $e');
    }
  }

  static String newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(999)}';

  Lead add(LeadKind kind) {
    final l = Lead(
      id: newId(kind == LeadKind.tenant ? 'lt' : 'lh'),
      kind: kind,
      status: kind == LeadKind.tenant ? 'new' : HomeState.active,
      source: {'type': 'Added by hand'},
    );
    _leads[l.id] = l;
    _save(changed: [l]);
    return l;
  }

  void _log(Lead l, String k, Object? o, Object? n) {
    l.history.add({'k': k, 'o': o, 'n': n, 't': DateTime.now().millisecondsSinceEpoch, if (app.brokerName.isNotEmpty) 'by': app.brokerName});
    l.changed = DateTime.now().millisecondsSinceEpoch;
  }

  void edit(Lead l, String key, Object? value) {
    if (l.id.startsWith('tk2:')) return;
    final old = l.f[key];
    if (old == value || (old ?? '').toString() == (value ?? '').toString()) return;
    _log(l, key, old, value);
    if (value == null || value == '') {
      l.f.remove(key);
    } else {
      l.f[key] = value;
    }
    _save(changed: [l]);
  }

  void toggleMust(Lead l, String key) {
    if (l.id.startsWith('tk2:')) return;
    final on = !l.must.contains(key);
    _log(l, 'mustHave:$key', !on, on);
    on ? l.must.add(key) : l.must.remove(key);
    _save(changed: [l]);
  }

  void setStatus(Lead l, String status, {Map<String, dynamic>? off}) {
    if (l.id.startsWith('tk2:')) return;
    _log(l, 'status', l.status, status);
    l.status = status;
    if (off != null) l.off = {...off, 'at': DateTime.now().millisecondsSinceEpoch};
    _save(changed: [l]);
  }

  void addNote(Lead l, String text) {
    if (text.trim().isEmpty || l.id.startsWith('tk2:')) return;
    l.notes.add({'text': text.trim(), 't': DateTime.now().millisecondsSinceEpoch});
    l.changed = DateTime.now().millisecondsSinceEpoch;
    _save(changed: [l]);
  }

  void linkListing(Lead l, String listingId) {
    _log(l, 'listingId', l.listingId, listingId);
    l.listingId = listingId;
    _save(changed: [l]);
  }

  /// "Send homes" is coming soon; each press is recorded to see demand.
  void logSend(Lead t, int homes) {
    sendLog.add({'tenant': t.id, 'homes': homes, 't': DateTime.now().millisecondsSinceEpoch});
    _save();
  }

  /// Finds the same person or home already on the desk.
  Lead? existing(Lead l) {
    final k = dedupeKey(l);
    for (final x in _leads.values) {
      if (x.kind == l.kind && (x.id == l.id || dedupeKey(x) == k)) return x;
    }
    return null;
  }

  /// Adds the chosen leads. A lead already here is never overwritten: only
  /// its empty fields are filled. Returns (added, filled, unchanged).
  (int, int, int) importLeads(List<Lead> chosen, {required String by, required String file, int rejected = 0}) {
    var added = 0, filled = 0, same = 0;
    final changed = <Lead>[];
    for (final l in chosen) {
      final x = existing(l);
      if (x == null) {
        final id = l.id.isEmpty ? newId(l.isTenant ? 'lt' : 'lh') : l.id;
        final n = Lead.fromJson({...l.toJson(), 'id': id}, kind: l.kind);
        if (by.isNotEmpty) n.source['by'] = by;
        _leads[id] = n;
        changed.add(n);
        added++;
        continue;
      }
      var any = false;
      for (final e in l.f.entries) {
        if (!x.has(e.key) && e.value != null && e.value != '') {
          _log(x, e.key, null, e.value);
          x.f[e.key] = e.value;
          any = true;
        }
      }
      if (any) {
        filled++;
        changed.add(x);
      } else {
        same++;
      }
    }
    imports.add({
      'by': by,
      'file': file,
      't': DateTime.now().millisecondsSinceEpoch,
      'added': added,
      'filled': filled,
      'duplicates': filled + same,
      'rejected': rejected,
      'ready': chosen.where((l) => l.ready).length,
      'ids': [for (final l in changed) l.id],
    });
    _save(changed: changed);
    return (added, filled, same);
  }

  // ---- Lists the screens show ----

  /// Tenants who can be matched and are still looking.
  List<Lead> get readyTenants => tenants.where((t) => t.active && t.ready).toList();

  /// Leads that need a call to get the basics (tenant: size; home: size or rent).
  List<Lead> get needCall => [...tenants.where((t) => t.active && !t.ready), ...homes.where((h) => h.status == HomeState.active && !h.ready)];

  List<Lead> get followUps {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day, 23, 59);
    return leads.where((l) {
      final d = DateTime.tryParse(l.str('followUp'));
      return l.active && d != null && !d.isAfter(end);
    }).toList();
  }

  Recommendation recommend(Lead t) => homesFor(t, activeHomes);

  // ---- When to bring in another AI helper (docs/AI-HELPERS.md) ----
  List<(String, String)> helperNotices() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 86400000;
    final out = <(String, String)>[];
    final fresh = tenants.where((t) => t.ready && now - t.at < 3 * day && t.source['type'] != 'Added by hand').length;
    if (_leads.isNotEmpty && fresh < 5) {
      out.add(('Fewer than 5 new tenants ready to match in 3 days.', 'Job 1 (Facebook groups) or Job 2 (WhatsApp chat export)'));
    }
    final week = leads.where((l) => now - l.at < 7 * day).toList();
    if (week.length >= 10 && week.where((l) => !l.ready).length / week.length > 0.3) {
      out.add(('More than 30% of this week\'s leads miss size or rent.', 'Job 4 (clean a lead file)'));
    }
    final recent = imports.where((i) => now - (i['t'] as num) < 7 * day).toList();
    final total = recent.fold<int>(0, (s, i) => s + (i['added'] as int) + (i['duplicates'] as int));
    final dup = recent.fold<int>(0, (s, i) => s + (i['duplicates'] as int));
    if (total >= 10 && dup / total > 0.2) out.add(('More than 20% of imported rows were already here.', 'Job 4 (clean a lead file)'));
    return out;
  }

  /// Per-source totals for the Helpers page.
  Map<String, Map<String, int>> sourceStats() {
    final out = <String, Map<String, int>>{};
    for (final i in imports) {
      final s = out.putIfAbsent(
        (i['by'] ?? '').toString().isEmpty ? 'Not said' : i['by'].toString(),
        () => {'files': 0, 'added': 0, 'duplicates': 0, 'rejected': 0, 'ready': 0},
      );
      s['files'] = s['files']! + 1;
      for (final k in ['added', 'duplicates', 'rejected', 'ready']) {
        s[k] = s[k]! + ((i[k] as num?) ?? 0).toInt();
      }
    }
    return out;
  }

  /// Parse helper used by Import and by the published-leads loader.
  ParsedFile parse(String text, String by) => parseLeadFile(text, by: by);
}
