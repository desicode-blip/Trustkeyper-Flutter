import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_filler.dart';
import 'package:trustkeyper/src/features/broker/data/agreement_templates.dart';
import 'package:trustkeyper/src/features/broker/data/property_onboarding.dart';

String plain(FilledAgreement f) => [
  for (final l in f.lines)
    if (l.kind == AgLineKind.tableRow) l.cells.map((c) => c.map((s) => s.text).join()).join(' | ') else l.segs.map((s) => s.text).join(),
].join('\n');

String read(AgreementTemplate t) => File('assets/agreements/${t.fileName}').readAsStringSync();

PropertyOnboarding house({AgreementAnswers? answers, List<CoOwner> co = const []}) => PropertyOnboarding(
  id: 'h1',
  ownerName: 'Ravi Kumar',
  channel: 'email',
  contact: 'ravi@example.com',
  createdAt: 0,
  address: 'Flat 12, Green Towers, Hyderabad 500032',
  rent: 40000,
  deposit: 80000,
  coOwners: co,
  answers: answers ?? const AgreementAnswers(),
);

void main() {
  test('percent template: owners, address, fee, dates come from the inputs', () {
    final item = house(
      answers: const AgreementAnswers(feeType: 'percent', feeValue: 8, payWay: 'cut', startDate: '2026-11-01', months: 11, notes: 'Painting before move-in'),
      co: [CoOwner(name: 'Sita Kumar', channel: 'whatsapp', contact: '9876543210')],
    );
    final out = plain(AgreementFiller.fill(read(AgreementTemplates.monthlyPercent), item, AgreementTemplates.monthlyPercent, today: DateTime(2026, 10, 28)));
    expect(out, contains('Ravi Kumar and Sita Kumar and Paravent'));
    expect(out, contains('equivalent to 8% of the total monthly consideration'));
    expect(out, contains('executed on 28th October, 2026'));
    expect(out, contains('effective from 1st November, 2026'));
    expect(out, contains('initial period of 11 months, up to and including 30th September, 2027'));
    expect(out, contains('Flat 12, Green Towers, Hyderabad 500032'));
    expect(out, contains('Painting before move-in'));
    expect(out, contains('ravi@example.com (Owner 1)'));
    expect(out, contains('Name: Ravi Kumar'));
    expect(out, contains('Name: Sita Kumar'));
    // nothing from past owners
    expect(out, isNot(contains('Krishna')));
    expect(out, isNot(contains('9.1%')));
  });

  test('what we do not know stays an empty gap, never invented', () {
    final item = house(answers: const AgreementAnswers(feeType: 'percent', feeValue: 8, payWay: 'cut'));
    final f = AgreementFiller.fill(read(AgreementTemplates.monthlyPercent), item, AgreementTemplates.monthlyPercent);
    final text = plain(f);
    expect(text, contains('[FATHER’S / SPOUSE’S NAME]'));
    expect(text, contains('[EFFECTIVE DATE]')); // no start date given yet
    expect(f.missing, contains('Father’s / spouse’s name'));
    expect(f.missing, contains('Effective date'));
  });

  test('3 days template: any number of days is written in the fee and the percent', () {
    final three = plain(AgreementFiller.fill(
      read(AgreementTemplates.monthlyDays),
      house(answers: const AgreementAnswers(feeType: 'daysMonthly', feeValue: 3, payWay: 'cut', startDate: '2026-11-01')),
      AgreementTemplates.monthlyDays,
    ));
    expect(three, contains('three (3) days’ rent'));
    expect(three, contains('ten percent (10%)'));
    final five = plain(AgreementFiller.fill(
      read(AgreementTemplates.monthlyDays),
      house(answers: const AgreementAnswers(feeType: 'daysMonthly', feeValue: 5, payWay: 'cut', startDate: '2026-11-01')),
      AgreementTemplates.monthlyDays,
    ));
    expect(five, contains('five (5) days’ rent'));
    expect(five, contains('multiplied by five (5)'));
    expect(five, contains('16.7%'));
  });

  test('15 days template: days and one-year term follow the inputs', () {
    final item = house(answers: const AgreementAnswers(feeType: 'days', feeValue: 10, payWay: 'cut', startDate: '2026-11-01', months: 12));
    final out = plain(AgreementFiller.fill(read(AgreementTemplates.yearlyDays), item, AgreementTemplates.yearlyDays));
    expect(out, contains('equivalent to ten (10) days of the one-month rent'));
    expect(out, contains('equivalent to ten (10) days of the prevailing monthly rent'));
    expect(out, contains('commence on 1st November, 2026'));
    expect(out, contains('initial period of one (1) year'));
    expect(out, isNot(contains('25 June 2026')));
  });

  test('NRI template: owner name and fee filled; owner bank stays empty', () {
    final item = house(answers: const AgreementAnswers(feeType: 'percent', feeValue: 6, payWay: 'cut', startDate: '2026-12-01'));
    final f = AgreementFiller.fill(read(AgreementTemplates.nri), item, AgreementTemplates.nri);
    final out = plain(f);
    expect(out, contains('equivalent to 6% of'));
    expect(out, contains('Ravi Kumar'));
    expect(out, contains('[ACCOUNT NUMBER]'));
    expect(f.missing, contains('Account number'));
  });
}
