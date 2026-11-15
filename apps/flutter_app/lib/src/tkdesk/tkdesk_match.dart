/// Matching one tenant to homes, and one home to tenants. Pure functions:
/// no state, no screens, fully tested in test/tk2/tkdesk_match_test.dart.
///
/// Rules (Aman, 15 Nov 2026):
/// - A tenant needs a size (BHK) to be matched; a home needs a size and a rent,
///   and must be Active.
/// - Size: same, or within half a BHK.
/// - Budget (if given): cost up to the top of the range fits; up to 10% over
///   shows as "slightly over"; more is out. No budget: money is not checked.
/// - "Must have" on either side is a hard rule. If the other side's value is
///   unknown, the match stays and shows "Ask on call".
/// - Everything else only changes the order and shows as a tick or a mark.
library;

import 'tkdesk_lead.dart';

/// Localities of west Hyderabad that sit close to each other.
const _near = [
  ['financial district', 'nanakramguda', 'gachibowli', 'puppalaguda', 'narsingi', 'kokapet', 'khajaguda', 'manikonda'],
  ['gachibowli', 'kondapur', 'hitech city', 'madhapur', 'raidurg', 'kothaguda'],
  ['madhapur', 'jubilee hills', 'hitech city', 'kondapur', 'ayyappa society', 'banjara hills'],
  ['kondapur', 'kothaguda', 'hafeezpet', 'miyapur', 'chanda nagar', 'botanical garden'],
  ['kukatpally', 'kphb', 'miyapur', 'nizampet', 'bachupally', 'pragathi nagar'],
  ['manikonda', 'puppalaguda', 'narsingi', 'tolichowki', 'shaikpet', 'lanco hills'],
  ['tellapur', 'nallagandla', 'gopanpally', 'serilingampally', 'lingampally', 'chandanagar', 'kollur', 'ameenpur'],
];

const _alias = {
  'fd': 'financial district',
  'fin district': 'financial district',
  'nanakram guda': 'nanakramguda',
  'hi tech city': 'hitech city',
  'hitec city': 'hitech city',
  'hitec': 'hitech city',
  'hitech': 'hitech city',
  'hitex': 'hitech city',
  'hitex city': 'hitech city',
  'gachi bowli': 'gachibowli',
  'tngo colony': 'gachibowli',
  'tngos colony': 'gachibowli',
  'kokapet sez': 'kokapet',
  'phf': 'financial district',
  'prestige high fields': 'financial district',
  'prestige highfields': 'financial district',
  'asbl spectra': 'financial district',
  'aparna zenon': 'puppalaguda',
  'my home bhooja': 'hitech city',
  'indis viva city': 'kondapur',
  'bollineni bion': 'kondapur',
  'aparna one': 'shaikpet',
  'accurate wind chimes': 'narsingi',
};

/// Every known locality, for pickers.
final allAreas = {for (final g in _near) ...g}.toList()..sort();

/// The usual name of a place ("Hi-tech City" → "hitech city").
String areaKey(String s) {
  final k = s.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return _alias[k] ?? k;
}

bool areasNear(String a, String b) => _near.any((g) => g.contains(a) && g.contains(b));

/// What the tenant pays each month for this home, as their budget counts it.
int monthlyCost(Lead t, Lead h) {
  final rentOnly = t.yes('budgetRentOnly');
  final maint = h.yes('maintIncl') ? 0 : h.numOf('maint').round();
  return rentOnly ? h.rent : h.rent + maint;
}

class Fit {
  Fit(this.home);
  final Lead home;
  int score = 0;

  /// What fits (green ticks).
  final List<String> ticks = [];

  /// What does not fit but is allowed (orange marks).
  final List<String> marks = [];

  /// Must-haves where the other side has not said: ask on the call.
  final List<String> ask = [];

  /// Why this home is out. Empty = a real match.
  final List<String> blocks = [];

  bool get ok => blocks.isEmpty;
}

/// How [h] fits tenant [t]. Always returns a [Fit]; check [Fit.ok].
Fit fit(Lead t, Lead h) {
  final r = Fit(h);
  if (h.status != HomeState.active) {
    r.blocks.add(h.status == HomeState.cancelled ? 'Cancelled' : 'Not active');
    return r;
  }
  if (!t.ready || !h.ready) {
    r.blocks.add('Missing size or rent');
    return r;
  }
  bool must(String k) => t.must.contains(k) || h.must.contains(k);

  // Size
  final d = (h.bhk - t.bhk).abs();
  if (d == 0) {
    r.score += 30;
    r.ticks.add(bhkText(h.bhk));
  } else if (d <= 0.5) {
    r.score += 18;
    r.marks.add('${bhkText(h.bhk)} (asked ${bhkText(t.bhk)})');
  } else {
    r.blocks.add('${bhkText(h.bhk)}, asked ${bhkText(t.bhk)}');
  }

  // Money
  final max = t.numOf('budgetMax');
  if (max > 0) {
    final cost = monthlyCost(t, h);
    if (cost <= max) {
      r.score += 30;
      r.ticks.add('In budget');
    } else if (cost <= max * 1.1) {
      r.score += 12;
      if (must('budgetMax')) {
        r.blocks.add('${rupees(cost - max)} over budget (must have)');
      } else {
        r.marks.add('Slightly over budget (${rupees(cost - max)})');
      }
    } else {
      r.blocks.add('${rupees(cost - max)} over budget');
    }
  } else {
    r.score += 12;
  }

  // Place
  final want = t.areas.map(areaKey).where((e) => e.isNotEmpty).toList();
  final at = [areaKey(h.str('area')), areaKey(h.str('society'))].where((e) => e.isNotEmpty).toList();
  if (want.isNotEmpty) {
    if (at.isEmpty) {
      if (must('areas')) r.ask.add('Area');
    } else if (want.any(at.contains)) {
      r.score += 25;
      r.ticks.add('In ${cap(at.first)}');
    } else if (want.any((w) => at.any((a) => areasNear(w, a)))) {
      r.score += 14;
      r.ticks.add('Near ${cap(want.first)}');
    } else if (must('areas') || must('area')) {
      r.blocks.add('${cap(at.first)}, wants ${want.map(cap).join(' / ')}');
    } else {
      r.marks.add('${cap(at.first)} (wants ${cap(want.first)})');
    }
  } else {
    r.score += 10;
  }

  // Plain preferences: same value fits; different is a mark, or a block if a must-have.
  void pref(String key, String label, {required bool Function(String tv, String hv) okIf, String Function(String hv)? tickText}) {
    final tv = t.str(key).toLowerCase();
    final hv = h.str(key).toLowerCase();
    final isMust = must(key);
    if (tv.isEmpty || hv.isEmpty) {
      if (isMust && (tv.isEmpty != hv.isEmpty)) r.ask.add(label);
      return;
    }
    if (okIf(tv, hv)) {
      r.score += 4;
      if (tickText != null) r.ticks.add(tickText(hv));
    } else if (isMust) {
      r.blocks.add('$label: ${cap(hv)}, wants ${cap(tv)}');
    } else {
      r.marks.add('$label: ${cap(hv)} (wants ${cap(tv)})');
    }
  }

  pref('furnishing', 'Furnishing', okIf: (tv, hv) => tv == hv, tickText: cap);
  pref(
    'who',
    'Owner wants',
    okIf: (tv, hv) => hv == 'any' || hv == tv || (hv.startsWith('bachelor') && tv == 'couple'),
    tickText: (hv) => hv == 'any' ? 'Anyone welcome' : (hv == 'family' ? 'Family welcome' : 'Bachelors welcome'),
  );
  pref('food', 'Food', okIf: (tv, hv) => hv == 'any' || tv == 'veg' || hv != 'veg only');
  pref('facing', 'Facing', okIf: (tv, hv) => tv == hv, tickText: (hv) => '${cap(hv)} facing');

  // Pets: the tenant has pets, the owner does not allow them.
  if (t.has('pets') && t.yes('pets')) {
    if (!h.has('pets')) {
      if (must('pets')) r.ask.add('Pets');
    } else if (!h.yes('pets')) {
      if (must('pets')) {
        r.blocks.add('No pets allowed');
      } else {
        r.marks.add('No pets allowed');
      }
    } else {
      r.ticks.add('Pets allowed');
    }
  }

  // Parking
  final carNeed = t.numOf('parking');
  if (carNeed > 0) {
    final hp = h.numOf('parking');
    if (!h.has('parking')) {
      if (must('parking')) r.ask.add('Parking');
    } else if (hp < carNeed) {
      (must('parking') ? r.blocks : r.marks).add('Parking for ${hp.toInt()}');
    } else {
      r.ticks.add('Parking');
    }
  }

  // Move-in: home free more than 15 days after the tenant wants to move.
  final tm = DateTime.tryParse(t.str('moveIn'));
  final hf = DateTime.tryParse(h.str('availableFrom'));
  if (tm != null && hf != null && hf.isAfter(tm.add(const Duration(days: 15)))) {
    (must('moveIn') || must('availableFrom') ? r.blocks : r.marks).add('Free from ${hf.day}/${hf.month}');
  } else if (tm != null && hf == null && must('moveIn')) {
    r.ask.add('Free from');
  }

  r.score = r.score.clamp(0, 100);
  return r;
}

class Recommendation {
  Recommendation(this.matches, this.near);

  /// Homes that fit, best first.
  final List<Fit> matches;

  /// When fewer than 3 fit: homes that miss on one point, best first.
  final List<Fit> near;
  List<Fit> get all => [...matches, ...near];
}

/// Homes for a tenant: real matches first; if fewer than [atLeast], the closest
/// misses (one block only) are added so the caller always has options to try.
Recommendation homesFor(Lead t, Iterable<Lead> homes, {int atLeast = 3, int limit = 12}) {
  if (!t.ready) return Recommendation([], []);
  final all = [for (final h in homes) fit(t, h)];
  int order(Fit a, Fit b) => b.score != a.score ? b.score.compareTo(a.score) : monthlyCost(t, a.home).compareTo(monthlyCost(t, b.home));
  final ok = all.where((f) => f.ok).toList()..sort(order);
  final near = ok.length >= atLeast
      ? <Fit>[]
      : (all.where((f) => f.blocks.length == 1 && f.home.status == HomeState.active && f.home.ready).toList()..sort(order)).take(atLeast - ok.length).toList();
  return Recommendation(ok.take(limit).toList(), near);
}

/// Tenants a home suits, best first.
List<(Lead, Fit)> tenantsFor(Lead h, Iterable<Lead> tenants) {
  final out = [
    for (final t in tenants)
      if (t.active && t.ready) (t, fit(t, h)),
  ].where((e) => e.$2.ok).toList()..sort((a, b) => b.$2.score.compareTo(a.$2.score));
  return out;
}
