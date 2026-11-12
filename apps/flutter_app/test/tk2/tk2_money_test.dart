import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trustkeyper/src/tk2/tk2_deal.dart';
import 'package:trustkeyper/src/tk2/tk2_money.dart';
import 'package:trustkeyper/src/tk2/tk2_notes.dart';
import 'package:trustkeyper/src/tk2/tk2_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Tk2Store> fresh() async {
    final store = Tk2Store.forTest();
    await store.load();
    return store;
  }

  test('payments: every visit fee is listed with what is yours, held or refunded', () async {
    final store = await fresh();
    final soon = DateTime.now().add(const Duration(hours: 3));
    final done = await store.bookVisit(listingId: 'sample', name: 'Ravi', phone: '', at: soon);
    final away = await store.bookVisit(listingId: 'sample', name: 'Sita', phone: '', at: soon);
    final off = await store.bookVisit(listingId: 'sample', name: 'Anil', phone: '', at: soon);
    await store.bookVisit(listingId: 'sample', name: 'Meena', phone: '', at: soon);
    expect(await store.confirmVisit(done.id, done.code), isNull);
    await store.closeVisit(away.id, VisitStatus.noShow);
    await store.customerCancel(off.id);

    final all = tk2Ledger(store);
    Tk2Txn of(String visitId) => all.firstWhere((x) => x.visitId == visitId);
    expect((of(done.id).state, of(done.id).yours), ('received', 150));
    expect((of(away.id).state, of(away.id).yours), ('received', 75));
    expect((of(off.id).state, of(off.id).yours, of(off.id).shown), ('refunded', 0, 150));
    expect(of(off.id).split, contains(('Back to Anil', 147)));
    expect(all.where((x) => x.state == 'held').single.from, 'Meena');

    final totals = tk2MoneyTotals(store, all, DateTime.now());
    expect(totals.received, 225);
    expect(totals.month, 225);
    expect(totals.coming, 150);
  });

  test('payments: a deal adds token, move-in and owner payment; brokerage counts once paid', () async {
    final store = await fresh();
    final now = DateTime.now();
    final d = Tk2Deal(
      id: 'd1',
      listingId: 'l1',
      title: '2 BHK · Prestige Highfield',
      tenantName: 'Ravi',
      tenantPhone: '',
      ownerName: 'Hari',
      token: 15000,
      rent: 30000,
      deposit: 60000,
      brokerage: 15000,
      ownerBrokerage: 10000,
      createdAt: 1,
    );
    await store.putDeal(d);
    expect(tk2MoneyTotals(store, tk2Ledger(store), now).coming, 25000);
    while (d.stage(now).index < DealStage.handover.index) {
      DealRole.values.any((r) => d.demoDo(r, now));
    }
    final all = tk2Ledger(store);
    expect(all.map((x) => x.kind).toSet(), {'token', 'movein', 'owner'});
    expect(all.firstWhere((x) => x.kind == 'movein').paid, d.moveInTotal);
    expect(all.firstWhere((x) => x.kind == 'owner').paid, 10000 + Tk2Deal.feeShare);
    final totals = tk2MoneyTotals(store, all, now);
    expect(totals.received, 25000);
    expect(totals.coming, 0);
  });

  test('notifications: booking and code reminder; read one, read all, turn a kind off', () async {
    final store = await fresh();
    final v = await store.bookVisit(listingId: 'sample', name: 'Ravi', phone: '', at: DateTime.now().subtract(const Duration(hours: 2)));
    final now = DateTime.now().add(const Duration(minutes: 1));
    final notes = tk2Notes(store, now);
    expect(notes.map((n) => n.id), containsAll(['vb:${v.id}', 'vc:${v.id}']));
    expect(tk2UnreadNotes(store, now), 2);

    await store.readNote('vc:${v.id}');
    expect(tk2UnreadNotes(store, now), 1);
    await store.readAllNotes();
    expect(tk2UnreadNotes(store, now), 0);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await store.confirmVisit(v.id, v.code);
    final later = DateTime.now().add(const Duration(minutes: 5));
    expect(tk2Notes(store, later).first.title, '₹150 is yours');
    expect(tk2UnreadNotes(store, later), 1);
    await store.muteNotes('money', off: true);
    expect(tk2UnreadNotes(store, later), 0, reason: 'turned-off kinds do not count on the bell');
  });
}
