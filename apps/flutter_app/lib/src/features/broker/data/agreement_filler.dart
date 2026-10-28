import 'package:flutter/services.dart' show rootBundle;

import 'agreement_templates.dart';
import 'property_onboarding.dart';

/// One piece of text on the agreement page.
enum SegKind { plain, filled, gap }

class AgSeg {
  const AgSeg(this.text, {this.kind = SegKind.plain, this.bold = false, this.italic = false, this.group});
  final String text;
  final SegKind kind;
  final bool bold;
  final bool italic;

  /// 'fee' | 'dates' | 'notes' when the text comes from one of the editable parts.
  final String? group;
}

enum AgLineKind { heading, para, bullet, tableRow }

class AgLine {
  const AgLine(this.kind, this.segs, {this.cells = const []});
  final AgLineKind kind;
  final List<AgSeg> segs;

  /// For table rows: one list of segments per cell.
  final List<List<AgSeg>> cells;
}

class FilledAgreement {
  const FilledAgreement(this.lines, this.missing);
  final List<AgLine> lines;

  /// Names of the details still empty (each once).
  final List<String> missing;
}

/// Fills a template copy with what the broker and the owners told us.
/// Anything we do not know is left as a visible grey gap, never guessed.
abstract final class AgreementFiller {
  static final Map<String, String> _cache = {};

  /// The template words (bundled copy; see assets/agreements/README).
  static Future<String> load(AgreementTemplate t) async {
    final cached = _cache[t.id];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/agreements/${t.fileName}');
    return _cache[t.id] = raw;
  }

  static final _token = RegExp(r'\[[^\[\]\n]{1,140}\]');

  static bool _isToken(String inner) =>
      !inner.startsWith('*') && !inner.contains('remainder') && !inner.startsWith('The ');

  static const _words = {
    1: 'one (1)', 2: 'two (2)', 3: 'three (3)', 4: 'four (4)', 5: 'five (5)', 6: 'six (6)', 7: 'seven (7)',
    8: 'eight (8)', 9: 'nine (9)', 10: 'ten (10)', 12: 'twelve (12)', 15: 'fifteen (15)', 20: 'twenty (20)', 30: 'thirty (30)',
  };

  static String _num(num v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  static String _daysText(num v) => v % 1 == 0 && _words.containsKey(v.toInt()) ? _words[v.toInt()]! : _num(v);

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static String _ord(int d) => d >= 11 && d <= 13 ? '${d}th' : '$d${const {1: 'st', 2: 'nd', 3: 'rd'}[d % 10] ?? 'th'}';
  static String prettyDate(DateTime d) => '${_ord(d.day)} ${_months[d.month - 1]}, ${d.year}';

  /// Raw template text -> clean lines with {{owner}} etc. not yet filled.
  static String _normalize(String raw) {
    var t = raw.replaceAll('\r', '');
    t = t.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    t = t.replaceAll(r'\[', '[').replaceAll(r'\]', ']').replaceAll(r'\_', '_').replaceAll(r'\-', '-').replaceAll(r'\*', '*').replaceAll(r'\)', ')').replaceAll(r'\(', '(').replaceAll(r'\.', '.');
    return t;
  }

  static FilledAgreement fill(String raw, PropertyOnboarding item, AgreementTemplate template, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final a = item.answers;
    var text = _normalize(raw);

    // ---- words that depend on the answers ----
    final days = a.feeValue;
    text = text
        .replaceAll('**three (3) days’ rent**', '**[FEE DAYS TEXT] days’ rent**')
        .replaceAll('multiplied by three (3)', 'multiplied by [FEE DAYS TEXT]')
        .replaceAll('ten percent (10%)', '[FEE PERCENT OF RENT TEXT]')
        .replaceAll('equivalent to 15days of', 'equivalent to [FEE DAYS TEXT] days of')
        .replaceAll('equivalent to fifteen (15) days of', 'equivalent to [FEE DAYS TEXT] days of')
        .replaceAll('[OWNER 1 FULL NAME], [OWNER 2 FULL NAME] and Paravent', '[OWNER NAMES] and Paravent')
        .replaceAll('[OWNER 1 FULL NAME] and [OWNER 2 FULL NAME], and Paravent', '[OWNER NAMES] and Paravent')
        .replaceAll('[OWNER 1 EMAIL] (Owner 1) and [OWNER 2 EMAIL] (Owner 2)', '[OWNER EMAIL ADDRESS]');
    text = text.replaceAllMapped(RegExp(r'initial period of one \(1\) year'), (m) => 'initial period of [TERM TEXT]');

    // ---- the parts the answers decide ----
    DateTime? start = DateTime.tryParse(a.startDate);
    DateTime? end = start == null ? null : DateTime(start.year, start.month + a.months, start.day - 1);
    String emailsText() {
      final out = <String>[];
      for (var i = 0; i < item.ownerCount; i++) {
        final p = item.paperAt(i, PaperKeys.email);
        var v = p.value.trim();
        if (v.isEmpty && item.ownerChannelAt(i) == 'email') v = item.ownerContactAt(i).trim();
        if (v.isNotEmpty) out.add(item.ownerCount > 1 ? '$v (Owner ${i + 1})' : v);
      }
      return out.join(' and ');
    }

    final missing = <String>[];
    (String?, String?) value(String label, int? owner) {
      switch (label) {
        case 'EXECUTION DATE':
          return (prettyDate(now), 'dates');
        case 'EFFECTIVE DATE':
          return (start == null ? null : prettyDate(start), 'dates');
        case 'END DATE OF INITIAL TERM':
          return (end == null ? null : prettyDate(end), 'dates');
        case 'TERM TEXT':
          return (a.months == 12 ? 'one (1) year' : '${a.months} months', 'dates');
        case 'FEE PERCENT':
          return (a.feeType == 'percent' && a.feeValue > 0 ? _num(a.feeValue) : null, 'fee');
        case 'FEE DAYS TEXT':
          return (days > 0 ? _daysText(days) : null, 'fee');
        case 'FEE PERCENT OF RENT TEXT':
          return (days > 0 ? (days == 3 ? 'ten percent (10%)' : '${_num(days / 30 * 100)}%') : null, 'fee');
        case 'OWNER NAMES':
        case 'OWNER FULL NAME':
          return (item.ownersFull.replaceFirstMapped(RegExp(r', (?=[^,]*$)'), (_) => ' and '), null);
        case 'OWNER EMAIL ADDRESS':
          final e = emailsText();
          return (e.isEmpty ? null : e, null);
        case 'PROPERTY ADDRESS':
        case 'FULL ADDRESS OF THE PROPERTY WITH PIN CODE':
          return (item.address.trim().isEmpty ? null : item.address.trim(), null);
      }
      final m = RegExp(r'^OWNER (\d) FULL NAME$').firstMatch(label);
      if (m != null && owner != null) return (item.ownerNameAt(owner).trim().isEmpty ? null : item.ownerNameAt(owner).trim(), null);
      return (null, null);
    }

    // ---- lines: repeat owner lines for every owner, drop "owner 2" lines ----
    final src = text.split('\n');
    final lines = <String>[];
    for (final l in src) {
      if (l.contains('OWNER 2') && !l.contains('OWNER 1')) {
        continue;
      }
      if (l.contains('OWNER 1') && !l.trimLeft().startsWith('|')) {
        for (var i = 0; i < item.ownerCount; i++) {
          lines.add(l.replaceAll('OWNER 1', 'OWNER ${i + 1}'));
        }
        continue;
      }
      lines.add(l);
    }

    // ---- extra notes: kept as an added clause before the signing page ----
    final notes = a.notes.trim();
    final out = <AgLine>[];
    var notesAdded = false;

    List<AgSeg> segsOf(String line, {int? owner}) {
      final res = <AgSeg>[];
      var bold = false;
      var italic = false;
      void plain(String chunk) {
        // **bold** and *italic* toggles
        final parts = chunk.split(RegExp(r'(\*\*|\*)'));
        final marks = RegExp(r'(\*\*|\*)').allMatches(chunk).map((m) => m.group(0)!).toList();
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) res.add(AgSeg(parts[i], bold: bold, italic: italic));
          if (i < marks.length) {
            if (marks[i] == '**') {
              bold = !bold;
            } else {
              italic = !italic;
            }
          }
        }
      }

      var last = 0;
      for (final m in _token.allMatches(line)) {
        final inner = m.group(0)!.substring(1, m.group(0)!.length - 1);
        if (!_isToken(inner)) continue;
        plain(line.substring(last, m.start));
        // the line index for "OWNER n" lines comes from the label itself
        final idx = RegExp(r'OWNER (\d)').firstMatch(inner);
        final who = idx == null ? owner : int.parse(idx.group(1)!) - 1;
        final (v, group) = value(inner, who);
        if (v == null) {
          res.add(AgSeg(m.group(0)!, kind: SegKind.gap, bold: bold, italic: italic, group: group));
          if (!_ignoredGap(inner) && !missing.contains(_cleanLabel(inner))) missing.add(_cleanLabel(inner));
        } else {
          res.add(AgSeg(v, kind: SegKind.filled, bold: bold, italic: italic, group: group));
        }
        last = m.end;
      }
      plain(line.substring(last));
      return res;
    }

    for (var raw in lines) {
      var l = raw.trim();
      if (l.isEmpty) continue;
      if (RegExp(r'^[-\s]*Please write or type below this line[-\s]*$').hasMatch(l) || RegExp(r'^(- ){3,}').hasMatch(l)) continue;
      if (l == '---' || RegExp(r'^\|[\s:\-|]+\|$').hasMatch(l)) continue;
      if (l.contains('remainder of this page') && notes.isNotEmpty && !notesAdded) {
        notesAdded = true;
        out.add(const AgLine(AgLineKind.heading, [AgSeg('ADDITIONAL TERMS', bold: true)]));
        out.add(AgLine(AgLineKind.para, [AgSeg(notes, kind: SegKind.filled, group: 'notes')]));
      }
      if (l.startsWith('|')) {
        final cells = l.substring(1, l.endsWith('|') ? l.length - 1 : l.length).split('|').map((c) => c.trim()).toList();
        out.add(AgLine(AgLineKind.tableRow, const [], cells: [for (final c in cells) segsOf(c)]));
        continue;
      }
      var kind = AgLineKind.para;
      l = l.replaceFirstMapped(RegExp(r'^(\d+\))\s*#{1,6}\s*'), (m) => '${m.group(1)} ');
      final h = RegExp(r'^#{1,6}\s*').firstMatch(l);
      if (h != null) {
        l = l.substring(h.end);
        if (l.length < 90) kind = AgLineKind.heading;
      } else if (l.startsWith('>')) {
        l = l.substring(1).trim();
        if (l.startsWith('* ') || l.startsWith('- ')) {
          kind = AgLineKind.bullet;
          l = l.substring(2);
        }
      } else if (l.startsWith('* ') || l.startsWith('- ')) {
        kind = AgLineKind.bullet;
        l = l.substring(2);
      }
      l = l.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s{2,}$'), '');
      if (l.trim().isEmpty) continue;
      out.add(AgLine(kind, segsOf(l)));
    }
    if (notes.isNotEmpty && !notesAdded) {
      out.add(const AgLine(AgLineKind.heading, [AgSeg('ADDITIONAL TERMS', bold: true)]));
      out.add(AgLine(AgLineKind.para, [AgSeg(notes, kind: SegKind.filled, group: 'notes')]));
    }
    return FilledAgreement(out, missing);
  }

  /// Items lists, quantities and brands are the owner's later job: not counted as "missing".
  static bool _ignoredGap(String label) =>
      label == 'Qty' || label == 'Brand' || label.startsWith('ITEM') || label == 'CONDITION' || label.startsWith('__') || label.startsWith('OPTIONAL') || label.startsWith('NAME AS ON');

  static String _cleanLabel(String label) {
    final t = label.replaceAll(RegExp(r'OWNER \d '), '').trim().toLowerCase();
    return t.isEmpty ? label : t[0].toUpperCase() + t.substring(1);
  }
}
