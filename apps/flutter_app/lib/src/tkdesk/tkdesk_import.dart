/// Reading lead files: TK Lead Format v1 (JSON) or a CSV with the sheet's own
/// column headers. Nothing here saves; the Import screen shows a preview and
/// the salesperson presses Import (docs/TK-LEAD-FORMAT.md).
library;

import 'dart:convert';

import 'tkdesk_lead.dart';

class ParsedFile {
  ParsedFile(this.leads, this.rejected);
  final List<Lead> leads;

  /// Rows that could not be used, with why.
  final List<String> rejected;
}

/// Sheet headers (any case) → field keys.
const _csvTenant = {
  'name': 'name',
  'client no': 'phone',
  'phone': 'phone',
  'requirement': 'bhk',
  'bhk': 'bhk',
  'budget': 'budgetMax',
  'veg/non-veg': 'food',
  'from date': 'moveIn',
  'type': 'who',
  'next followup date': 'followUp',
  'remarks': 'remarks',
  'linkdein': 'linkedin',
  'linkedin': 'linkedin',
  'status': 'status',
  'date added': 'at',
  'areas': 'areas',
};
const _csvHome = {
  'status': 'status',
  'entry date': 'at',
  'name': 'ownerName',
  'flat no': 'flat',
  'sq fit(built up area)': 'sqft',
  'tower no': 'tower',
  'society': 'society',
  'owner mobile no': 'ownerPhone',
  'type of flat': 'bhk',
  'rent': 'rent',
  'furnished state': 'furnishing',
  'tenant preferance - marrital status': 'who',
  'tenant preferance': 'who',
  'tenant preferance - working preferance': 'work',
  'veg/nonveg': 'food',
  'key location': 'keys',
  'parking': 'parking',
  'pictures': 'pictures',
  'next followup date': 'followUp',
  'remarks': 'remarks',
  'total floors in building': 'floors',
  'floor of the flat': 'floor',
  'brokerage charges': 'brokerage',
  'maintenance charges': 'maint',
  'property facing': 'facing',
  'power backup- none/partial/full': 'powerBackup',
  'security deposit': 'deposit',
  'lock in period': 'lockIn',
  'balconies': 'balconies',
  'washrooms': 'washrooms',
  'carpet area': 'carpet',
  'super built up area': 'superArea',
  'area': 'area',
  'location': 'area',
  'available from': 'availableFrom',
};

ParsedFile parseLeadFile(String text, {String by = ''}) {
  final t = text.trim();
  if (t.startsWith('{') || t.startsWith('[')) return _json(t, by);
  return _csv(t, by);
}

ParsedFile _json(String text, String by) {
  final leads = <Lead>[];
  final rejected = <String>[];
  Object? data;
  try {
    data = jsonDecode(text);
  } catch (e) {
    return ParsedFile([], ['Not valid JSON: $e']);
  }
  List rows(String k) => data is Map ? (data[k] as List? ?? const []) : const [];
  final tenants = data is List ? data.where((e) => e is Map && e['kind'] != 'home').toList() : rows('tenants');
  final homes = data is List ? data.where((e) => e is Map && e['kind'] == 'home').toList() : rows('homes');
  var i = 0;
  for (final (kind, list) in [(LeadKind.tenant, tenants), (LeadKind.home, homes)]) {
    for (final row in list) {
      i++;
      if (row is! Map) {
        rejected.add('Row $i is not an object');
        continue;
      }
      final l = Lead.fromJson(Map<String, dynamic>.from(row), kind: kind);
      _finish(l, by, i, leads, rejected);
    }
  }
  return ParsedFile(leads, rejected);
}

ParsedFile _csv(String text, String by) {
  final rows = _csvRows(text);
  if (rows.length < 2) return ParsedFile([], ['No rows found']);
  final head = [for (final h in rows.first) h.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()];
  final isHome = head.contains('owner mobile no') || head.contains('type of flat') || head.contains('society');
  final map = isHome ? _csvHome : _csvTenant;
  final kind = isHome ? LeadKind.home : LeadKind.tenant;
  final leads = <Lead>[];
  final rejected = <String>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.every((c) => c.trim().isEmpty)) continue;
    final j = <String, dynamic>{};
    for (var c = 0; c < head.length && c < row.length; c++) {
      final key = map[head[c]];
      final v = row[c].trim();
      if (key == null || v.isEmpty || j.containsKey(key)) continue;
      j[key] = v;
    }
    final l = Lead.fromJson(j, kind: kind);
    _finish(l, by, r + 1, leads, rejected);
  }
  return ParsedFile(leads, rejected);
}

/// Cleans one row and decides if it can come in.
void _finish(Lead l, String by, int row, List<Lead> out, List<String> rejected) {
  final f = l.f;
  // Numbers people write as text.
  for (final k in ['bhk', 'rent', 'maint', 'budgetMin', 'budgetMax', 'sqft', 'parking']) {
    if (f[k] is String) {
      final n = toNum(f[k]);
      if (n > 0) {
        // "65" in a rent or budget column means 65,000.
        f[k] = (k != 'bhk' && k != 'sqft' && k != 'parking' && n < 1000) ? n * 1000 : n;
      } else {
        f.remove(k);
      }
    }
  }
  if (f['areas'] is String) f['areas'] = listOf(f['areas']);
  final st = l.status.toLowerCase().trim();
  if (l.isHome) {
    l.status = switch (st) {
      'not active' || 'inactive' || 'rented' || 'off' => HomeState.inactive,
      'cancel permanently' || 'cancelled' || 'cancel' || 'dead' => HomeState.cancelled,
      _ => HomeState.active,
    };
  } else {
    l.status = tenantStatuses.contains(st) ? st : (st == 'not active' || st == 'cancel permanently' ? 'lost' : 'new');
  }
  final text = (l.source['text'] ?? '').toString();
  if (l.phone.isEmpty && text.isEmpty && !l.ready) {
    rejected.add('Row $row: no phone, no post text and no details');
    return;
  }
  if (by.isNotEmpty) l.source['by'] = by;
  out.add(l);
}

/// Key used to find the same person or home again.
String dedupeKey(Lead l) {
  final p = l.phone.replaceAll(RegExp(r'\D'), '');
  final ph = p.length > 10 ? p.substring(p.length - 10) : p;
  if (l.isTenant) return ph.isNotEmpty ? 't:$ph' : 't:id:${l.id}';
  final where = '${l.str('society').toLowerCase()}|${l.str('tower').toLowerCase()}|${l.str('flat').toLowerCase()}';
  if (l.str('flat').isNotEmpty && l.str('society').isNotEmpty) return 'h:$where';
  return ph.isNotEmpty ? 'h:$ph|${l.bhk}|${l.rent}|${l.str('society').toLowerCase()}' : 'h:id:${l.id}';
}

List<List<String>> _csvRows(String s) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = [];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}
