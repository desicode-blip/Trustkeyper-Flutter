import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/tkdesk/tkdesk_import.dart';
import 'package:trustkeyper/src/tkdesk/tkdesk_lead.dart';
import 'package:trustkeyper/src/tkdesk/tkdesk_match.dart';

Lead t(Map<String, dynamic> f, {Set<String> must = const {}}) => Lead(id: 't', kind: LeadKind.tenant, f: f, must: {...must}, status: 'new');
Lead h(String id, Map<String, dynamic> f, {String status = HomeState.active, Set<String> must = const {}}) =>
    Lead(id: id, kind: LeadKind.home, f: f, must: {...must}, status: status);

void main() {
  test('needs size for tenants, size and rent for homes', () {
    expect(t({'phone': '9999999999'}).ready, false);
    expect(t({'bhk': 2}).ready, true);
    expect(h('a', {'bhk': 2}).ready, false);
    expect(h('a', {'bhk': 2, 'rent': 30000}).ready, true);
  });

  test('size within half a BHK, budget up to 10% over is a mark', () {
    final ten = t({'bhk': 2, 'budgetMax': 50000});
    expect(fit(ten, h('a', {'bhk': 2, 'rent': 48000})).ok, true);
    expect(fit(ten, h('b', {'bhk': 2.5, 'rent': 45000})).ok, true);
    expect(fit(ten, h('c', {'bhk': 3, 'rent': 45000})).ok, false);
    final over = fit(ten, h('d', {'bhk': 2, 'rent': 54000}));
    expect(over.ok, true);
    expect(over.marks.any((m) => m.contains('over budget')), true);
    expect(fit(ten, h('e', {'bhk': 2, 'rent': 60000})).ok, false);
    expect(fit(ten, h('f', {'bhk': 2, 'rent': 45000, 'maint': 4000})).ticks.contains('In budget'), true);
    expect(fit(ten, h('g', {'bhk': 2, 'rent': 47000, 'maint': 5000})).marks.isNotEmpty, true);
  });

  test('no budget: money is not checked', () {
    expect(fit(t({'bhk': 3}), h('a', {'bhk': 3, 'rent': 200000})).ok, true);
  });

  test('not active and cancelled homes never match', () {
    final ten = t({'bhk': 2});
    expect(fit(ten, h('a', {'bhk': 2, 'rent': 1}, status: HomeState.inactive)).ok, false);
    expect(fit(ten, h('b', {'bhk': 2, 'rent': 1}, status: HomeState.cancelled)).ok, false);
  });

  test('must-have is a hard rule; unknown means ask on call', () {
    final ten = t({'bhk': 2, 'furnishing': 'fully furnished'}, must: {'furnishing'});
    expect(fit(ten, h('a', {'bhk': 2, 'rent': 1, 'furnishing': 'semi-furnished'})).ok, false);
    final unknown = fit(ten, h('b', {'bhk': 2, 'rent': 1}));
    expect(unknown.ok, true);
    expect(unknown.ask, ['Furnishing']);
    final soft = fit(t({'bhk': 2, 'furnishing': 'fully furnished'}), h('c', {'bhk': 2, 'rent': 1, 'furnishing': 'semi-furnished'}));
    expect(soft.ok, true);
    expect(soft.marks.isNotEmpty, true);
    // Owner's must-have
    final fam = h('d', {'bhk': 2, 'rent': 1, 'who': 'family'}, must: {'who'});
    expect(fit(t({'bhk': 2, 'who': 'bachelors'}), fam).ok, false);
  });

  test('areas: same, near, far (far only blocks when a must-have)', () {
    final ten = t({'bhk': 2, 'areas': ['Gachibowli']});
    expect(fit(ten, h('a', {'bhk': 2, 'rent': 1, 'area': 'gachibowli'})).ticks.first, contains('BHK'));
    expect(fit(ten, h('b', {'bhk': 2, 'rent': 1, 'area': 'Kondapur'})).ticks.any((x) => x.startsWith('Near')), true);
    expect(fit(ten, h('c', {'bhk': 2, 'rent': 1, 'area': 'kukatpally'})).ok, true);
    final strict = t({'bhk': 2, 'areas': ['Gachibowli']}, must: {'areas'});
    expect(fit(strict, h('c', {'bhk': 2, 'rent': 1, 'area': 'kukatpally'})).ok, false);
    expect(areaKey('PHF'), 'financial district');
  });

  test('fewer than 3 matches: closest misses are added', () {
    final ten = t({'bhk': 2, 'budgetMax': 40000});
    final r = homesFor(ten, [
      h('a', {'bhk': 2, 'rent': 39000}),
      h('b', {'bhk': 2, 'rent': 50000}),
      h('c', {'bhk': 3, 'rent': 30000}),
      h('d', {'bhk': 2, 'rent': 30000}, status: HomeState.inactive),
    ]);
    expect(r.matches.map((f) => f.home.id), ['a']);
    expect(r.near.map((f) => f.home.id).toSet(), {'b', 'c'});
  });

  test('import: JSON and sheet CSV, statuses, no overwrite key', () {
    final p = parseLeadFile('{"format":"tk-leads-1","tenants":[{"phone":"98480 12345","bhk":"2bhk","budgetMax":"60k"}],"homes":[{"society":"PHF","bhk":2.5,"rent":"65","status":"NOT active"},{}]}');
    expect(p.leads.length, 2);
    expect(p.rejected.length, 1);
    expect(p.leads.first.bhk, 2);
    expect(p.leads.first.numOf('budgetMax'), 60000);
    expect(p.leads.last.rent, 65000);
    expect(p.leads.last.status, HomeState.inactive);
    final c = parseLeadFile('STATUS,Society,OWNER MOBILE NO,TYPE OF FLAT,RENT\nACTIVE,"ASBL, Spectra",9000000001,3BHK,80000\n');
    expect(c.leads.single.str('society'), 'ASBL, Spectra');
    expect(c.leads.single.isHome, true);
    expect(c.leads.single.rent, 80000);
  });
}
