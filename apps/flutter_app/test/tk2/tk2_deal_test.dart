import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/tk2/tk2_agreement.dart';
import 'package:trustkeyper/src/tk2/tk2_deal.dart';

Tk2Deal deal() => Tk2Deal(
  id: 'd1',
  listingId: 'l1',
  title: '2 BHK · Prestige Highfield',
  tenantName: 'Ravi Teja',
  tenantPhone: '+91 90000 00001',
  ownerName: 'Hari Rao',
  ownerPhone: '+91 90000 00002',
  brokerName: 'Suresh',
  token: 15000,
  rent: 30000,
  deposit: 60000,
  brokerage: 15000,
  createdAt: 0,
);

void main() {
  final now = DateTime(2026, 11, 12, 10);
  List<String> keys(Tk2Deal d, DealRole r, [DateTime? at]) => [for (final t in d.tasks(r, at ?? now)) t.key];

  test('the ten stages run in order, each person only gets their own step', () {
    final d = deal();
    final seen = <DealStage>[];
    // Everyone takes their turn until nobody has anything left to do.
    for (var i = 0; i < 60; i++) {
      final at = d.stage(now);
      if (seen.isEmpty || seen.last != at) seen.add(at);
      if (!DealRole.values.any((r) => d.demoDo(r, now))) break;
    }
    expect(seen, [DealStage.token, DealStage.docs, DealStage.draft, DealStage.approval, DealStage.signing, DealStage.payment, DealStage.handover, DealStage.repairs]);
    // Society steps ran beside handover and repairs; the 7 days then end.
    expect(d.societyDone, isTrue);
    expect(d.stage(now.add(const Duration(days: 8))), DealStage.living);
  });

  test('token: only the tenant pays; the split follows who backed out', () {
    final d = deal();
    expect(keys(d, DealRole.tenant), ['token']);
    expect(keys(d, DealRole.broker), isEmpty);
    expect(Tk2Deal.tokenSplit(15000, 'owner'), (tenant: 15000, owner: 0, broker: 0));
    expect(Tk2Deal.tokenSplit(15001, 'tenant'), (tenant: 0, owner: 7500, broker: 7501));
    d.b['ended'] = 'tenant';
    expect(keys(d, DealRole.tenant), isEmpty);
  });

  test('documents: broker checks each person; "ask again" stands until they resend', () {
    final d = deal()..t['tokenPaid'] = true;
    expect(keys(d, DealRole.tenant), ['docs']);
    expect(keys(d, DealRole.owner), ['docs']);
    d.t['docsAt'] = 100;
    expect(keys(d, DealRole.tenant), isEmpty);
    expect(keys(d, DealRole.broker), ['review:t']);
    d.b['redo'] = {
      'tenant': {'note': 'PAN is not clear', 'at': 200},
    };
    expect(d.redo(DealRole.tenant), 'PAN is not clear');
    expect(d.tasks(DealRole.tenant, now).single.label, 'Upload documents again');
    expect(keys(d, DealRole.broker), isEmpty);
    d.t['docsAt'] = 300;
    expect(d.redo(DealRole.tenant), '');
    expect(keys(d, DealRole.broker), ['review:t']);
  });

  test('agreement: a new version resets replies and lists what changed; signing needs the stamp paper', () {
    final d = deal()
      ..t.addAll({'tokenPaid': true, 'docsAt': 1})
      ..o['docsAt'] = 1
      ..b['docsOk'] = {'tenant': true, 'owner': true};
    expect(keys(d, DealRole.broker), ['terms']);
    d.sendVersion(d.defaultTerms(now), const [(name: 'Geyser', count: 2)]);
    expect(d.version, 1);
    d.t['reply'] = {'v': 1, 'ok': true};
    d.o['reply'] = {'v': 1, 'ok': false, 'note': 'Rent 31,000'};
    expect(d.stage(now), DealStage.approval);
    expect(keys(d, DealRole.broker), ['terms']);
    d.sendVersion({...d.terms, 'rent': 31000}, d.items);
    expect(d.changes, ['Rent: ₹30,000 → ₹31,000']);
    expect(d.replyOk(DealRole.tenant), isNull, reason: 'the yes was for version 1');
    expect(keys(d, DealRole.tenant), ['reply']);
    d.t['reply'] = {'v': 2, 'ok': true};
    d.o['reply'] = {'v': 2, 'ok': true};
    expect(d.stage(now), DealStage.signing);
    expect(keys(d, DealRole.tenant), isEmpty, reason: 'no signing before the stamp paper photo');
    expect(keys(d, DealRole.broker), ['stamp']);
    d.b['stamp'] = 'photo';
    expect(keys(d, DealRole.owner), ['sign']);
  });

  test('money: move-in total takes the token off and adds half the agreement fee', () {
    final d = deal();
    expect(Tk2Deal.feeShare * 2, Tk2Deal.agreementFee);
    expect(d.moveInTotal, 60000 + 30000 + 15000 + 250 - 15000);
  });

  Tk2Deal handedOver() {
    final d = deal();
    while (d.stage(now).index < DealStage.repairs.index) {
      DealRole.values.any((r) => d.demoDo(r, now));
    }
    return d;
  }

  test('handover: a later change counts only after owner and tenant both approve', () {
    final d = handedOver();
    expect(d.handover['keys'], 2);
    d.b['edit'] = {'v': 1, 'text': 'Third key found', 'keys': 3, 'meters': const {'Electricity': '1024'}};
    expect(keys(d, DealRole.tenant), contains('edit'));
    d.t['editOk'] = 1;
    expect(d.handover['keys'], 2);
    d.o['editOk'] = 1;
    expect(d.handover['keys'], 3);
  });

  test('repairs: tenant raises → broker quotes → owner approves → broker fixes → owner pays; 7-day window', () {
    final d = handedOver();
    expect(d.repairWindowOpen(now.add(const Duration(days: 6))), isTrue);
    expect(d.repairWindowOpen(now.add(const Duration(days: 7, minutes: 1))), isFalse);
    d.t['repairs'] = [
      {'id': 'r1', 'text': 'Geyser not heating', 'photo': 'p', 'at': 1},
    ];
    expect(keys(d, DealRole.broker), contains('quote:r1'));
    expect(keys(d, DealRole.owner), isNot(contains('approve:r1')), reason: 'nothing reaches the owner without the estimate');
    d.b['quotes'] = {
      'r1': {'min': 500, 'max': 800, 'days': 2},
    };
    expect(keys(d, DealRole.owner), contains('approve:r1'));
    d.o['rep'] = {
      'r1': {'ok': true},
    };
    expect(keys(d, DealRole.broker), contains('fixed:r1'));
    d.b['quotes'] = {
      'r1': {'min': 500, 'max': 800, 'days': 2, 'done': 5, 'photo': 'p', 'amount': 650},
    };
    expect(d.tasks(DealRole.owner, now).firstWhere((t) => t.key == 'payrepair:r1').label, 'Pay ₹650 for a repair');
    // An open request keeps the stage on repairs even after the 7 days.
    expect(d.stage(now.add(const Duration(days: 9))), DealStage.repairs);
    d.o['rep'] = {
      'r1': {'ok': true, 'paid': true},
    };
    expect(d.repairs.single.open, isFalse);
    // The owner can refuse, the tenant can take it back.
    expect(Tk2Repair({'id': 'x'}, const {}, const {'ok': false}).open, isFalse);
    expect(Tk2Repair({'id': 'x', 'off': true}, const {}, const {}).open, isFalse);
  });

  test('agreement text: the template fills from the terms, blanks stay visible', () {
    final d = deal()..sendVersion({...deal().defaultTerms(now), 'address': 'Flat 10141, Tower 10, Prestige Highfield, Hyderabad'}, const [(name: 'Geyser', count: 3)]);
    final text = Tk2Agreement.fill(File('assets/agreements/rent_leave_licence.md').readAsStringSync(), d, today: now);
    expect(text, contains('**Hari Rao**'));
    expect(text, contains('Rs. 30,000/-'));
    expect(text, contains('1st December, 2026 to 1st November, 2027'));
    expect(text, contains('1. 3 - Geyser.'));
    expect(text, contains('Pets are not allowed'));
    expect(text, isNot(contains('{')));
    expect(Tk2Agreement.gaps(text), 2, reason: 'owner address and tenant address are not filled yet');
  });
}
