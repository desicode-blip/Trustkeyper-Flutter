import 'dart:convert';

import 'package:intl/intl.dart';

import 'agreement_draft.dart';

class DemoAgreementField {
  const DemoAgreementField(this.id, this.label, this.value);
  final String id;
  final String label;
  final String value;
}

class DemoAgreement {
  DemoAgreement(AgreementDraft draft) {
    if (draft.validationError != null) {
      throw ArgumentError(draft.validationError);
    }
    fields = List.unmodifiable([
      DemoAgreementField('property', 'Property', draft.propertyAddress),
      DemoAgreementField('owners', 'Owners', _people(draft.owners, false)),
      DemoAgreementField(
        'tenants',
        'Tenants and shares',
        _people(draft.tenants, true),
      ),
      DemoAgreementField(
        'rent',
        'Monthly rent',
        _money(draft.monthlyRentPaise),
      ),
      DemoAgreementField(
        'maintenance',
        'Monthly maintenance',
        _money(draft.maintenancePaise),
      ),
      DemoAgreementField(
        'deposit',
        'Security deposit',
        _money(draft.depositPaise),
      ),
      DemoAgreementField(
        'term',
        'Agreement period',
        '${_date(draft.startDate!)} to ${_date(draft.endDate!)} (inclusive)',
      ),
      DemoAgreementField(
        'due',
        'Rent due day',
        '${draft.rentDueDay} of each month',
      ),
      DemoAgreementField(
        'lock',
        'Lock-in period',
        '${draft.lockInMonths} months',
      ),
      DemoAgreementField(
        'notice',
        'Notice period',
        '${draft.noticeMonths} months',
      ),
      DemoAgreementField(
        'brokerage',
        'Brokerage',
        'Owner: ${_money(draft.ownerBrokeragePaise)}\nTenant: ${_money(draft.tenantBrokeragePaise)}\nTotal: ${_money(draft.brokeragePaise)}',
      ),
    ]);
    revision = draft.revision;
    draftId = draft.id;
  }
  static const warning =
      'DEMO ONLY — NOT FOR SIGNING. This is a software-test template, not a legally approved agreement. No legal consent, signature, stamp duty or payment is recorded.';
  static const templateVersion = 'demo-v1';
  late final List<DemoAgreementField> fields;
  late final int revision;
  late final String draftId;

  String get snapshot => jsonEncode({
    'template': templateVersion,
    'fields': {for (final field in fields) field.id: field.value},
  });
  Set<String> changedFrom(DemoAgreement? previous) {
    if (previous == null) return {};
    final values = {for (final field in previous.fields) field.id: field.value};
    return {
      for (final field in fields)
        if (values[field.id] != field.value) field.id,
    };
  }

  String get text =>
      '$warning\n\nTrustKeyper demo rental agreement\nTemplate: $templateVersion\nDraft: $draftId · source revision $revision · may include unsaved edits\n\n${fields.map((field) => '${field.label}\n${field.value}').join('\n\n')}\n\nAdditional conditions\nLegal clauses, applicable charges, dispute handling and execution requirements must be separately approved before a real contract is generated.\n\nSignatures\nNot requested or recorded. This demo cannot be submitted for signing.';

  static String _date(DateTime date) => DateFormat('d MMM yyyy').format(date);
  static String _money(int paise) =>
      '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2).format(paise / 100)} (${rupeesInWords(paise)})';
  static String _people(List<AgreementParty> people, bool shares) => people
      .map(
        (party) =>
            '${party.name}\nMobile: ${party.phone}${party.email.isEmpty ? "" : "\nEmail: ${party.email}"}${shares ? "\nRent share: ${_money(party.rentSharePaise)}\nDeposit share: ${_money(party.depositSharePaise)}" : ""}',
      )
      .join('\n\n');
}
