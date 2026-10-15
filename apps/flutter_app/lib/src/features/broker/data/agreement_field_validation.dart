import 'agreement_draft.dart';

class AgreementFieldIssue {
  const AgreementFieldIssue(
    this.field,
    this.label,
    this.message,
    this.stage, {
    this.person = 0,
  });
  final String field;
  final String label;
  final String message;
  final String stage;
  final int person;
}

List<AgreementFieldIssue> agreementFieldIssues(
  AgreementDraft draft, {
  Map<String, String> inputs = const {},
  String? payer,
}) {
  final issues = <AgreementFieldIssue>[];
  for (final role in ['owner', 'tenant']) {
    final parties = role == 'owner' ? draft.owners : draft.tenants;
    final title = role == 'owner' ? 'Owner' : 'Tenant';
    for (var index = 0; index < parties.length; index++) {
      final party = parties[index];
      final prefix = '$role/$index';
      void add(String field, String label, String message, [String? stage]) {
        issues.add(
          AgreementFieldIssue(
            '$prefix/$field',
            '$title ${index + 1} · $label',
            message,
            stage ?? role,
            person: index,
          ),
        );
      }

      if (party.name.trim().length < 2) {
        add(
          'name',
          'Full name',
          party.name.trim().isEmpty
              ? 'Enter the full name.'
              : 'Use at least 2 characters.',
        );
      }
      if (!RegExp(r'^\+91[1-9]\d{9}$').hasMatch(party.phone)) {
        add(
          'phone',
          'Mobile number',
          'Enter a valid 10-digit Indian mobile number.',
        );
      } else if (parties.where((other) => other.phone == party.phone).length >
          1) {
        add(
          'phone',
          'Mobile number',
          'Use a different mobile number for each $role.',
        );
      }
      if (party.email.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(party.email)) {
        add(
          'email',
          'Email address',
          'Enter a valid email address, or leave it empty.',
        );
      }
      if (role == 'tenant') {
        if (party.rentSharePaise < 0) {
          add(
            'rentShare',
            'Rent share',
            'Enter a valid amount, including 0 if needed.',
            'money',
          );
        }
        if (party.depositSharePaise < 0) {
          add(
            'depositShare',
            'Deposit share',
            'Enter a valid amount, including 0 if needed.',
            'money',
          );
        }
      }
    }
  }
  void amount(
    String field,
    String label,
    int value,
    String stage, {
    bool zeroAllowed = false,
  }) {
    if (value < (zeroAllowed ? 0 : 1) || value > 10000000000) {
      final empty = inputs[field]?.trim().isEmpty == true;
      issues.add(
        AgreementFieldIssue(
          field,
          label,
          empty
              ? 'Enter ${label.toLowerCase()}.'
              : 'Enter ${zeroAllowed ? 'a non-negative' : 'a positive'} amount up to ₹10 crore.',
          stage,
        ),
      );
    }
  }

  amount('rent', 'Monthly rent', draft.monthlyRentPaise, 'money');
  amount(
    'maintenance',
    'Monthly maintenance',
    draft.maintenancePaise,
    'money',
    zeroAllowed: true,
  );
  amount('deposit', 'Security deposit', draft.depositPaise, 'money');
  if (draft.monthlyRentPaise > 0 &&
      draft.tenants.every((party) => party.rentSharePaise >= 0) &&
      draft.tenants.fold(0, (total, party) => total + party.rentSharePaise) !=
          draft.monthlyRentPaise) {
    issues.add(
      const AgreementFieldIssue(
        'rentShares',
        'Tenant rent shares',
        'The total must match the monthly rent. Edit the shares or split equally.',
        'money',
      ),
    );
  }
  if (draft.depositPaise > 0 &&
      draft.tenants.every((party) => party.depositSharePaise >= 0) &&
      draft.tenants.fold(
            0,
            (total, party) => total + party.depositSharePaise,
          ) !=
          draft.depositPaise) {
    issues.add(
      const AgreementFieldIssue(
        'depositShares',
        'Tenant deposit shares',
        'The total must match the security deposit. Edit the shares or split equally.',
        'money',
      ),
    );
  }
  if (draft.startDate == null) {
    issues.add(
      const AgreementFieldIssue(
        'startDate',
        'Start date',
        'Choose the agreement start date.',
        'dates',
      ),
    );
  }
  if (draft.endDate == null ||
      draft.startDate != null && !draft.endDate!.isAfter(draft.startDate!)) {
    issues.add(
      const AgreementFieldIssue(
        'endDate',
        'Agreement length',
        'Choose a length that ends after the start date.',
        'dates',
      ),
    );
  }
  if (![1, 5, 10].contains(draft.rentDueDay)) {
    issues.add(
      const AgreementFieldIssue(
        'dueDay',
        'Rent day',
        'Choose day 1, 5 or 10.',
        'dates',
      ),
    );
  }
  final boundary = draft.endDate?.add(const Duration(days: 1));
  if (draft.lockInMonths < 0 ||
      draft.lockInMonths > 60 ||
      boundary != null &&
          draft.startDate != null &&
          addCalendarMonths(
            draft.startDate!,
            draft.lockInMonths,
          ).isAfter(boundary)) {
    issues.add(
      const AgreementFieldIssue(
        'lockIn',
        'Lock-in period',
        'Choose a lock-in within the agreement length.',
        'periods',
      ),
    );
  }
  if (draft.noticeMonths < 1 ||
      draft.noticeMonths > 12 ||
      boundary != null &&
          draft.startDate != null &&
          addCalendarMonths(
            draft.startDate!,
            draft.noticeMonths,
          ).isAfter(boundary)) {
    issues.add(
      const AgreementFieldIssue(
        'notice',
        'Notice period',
        'Choose a notice period within the agreement length.',
        'periods',
      ),
    );
  }
  amount(
    'ownerBrokerage',
    'Owner brokerage',
    draft.ownerBrokeragePaise,
    'brokerage',
    zeroAllowed: true,
  );
  amount(
    'tenantBrokerage',
    'Tenant brokerage',
    draft.tenantBrokeragePaise,
    'brokerage',
    zeroAllowed: true,
  );
  if (payer == 'Both') {
    for (final entry in [
      ('ownerBrokerage', 'Owner brokerage', draft.ownerBrokeragePaise),
      ('tenantBrokerage', 'Tenant brokerage', draft.tenantBrokeragePaise),
    ]) {
      if (entry.$3 == 0) {
        issues.add(
          AgreementFieldIssue(
            entry.$1,
            entry.$2,
            'Enter a positive amount, or change who pays the brokerage.',
            'brokerage',
          ),
        );
      }
    }
  }
  if (draft.brokeragePaise > 10000000000) {
    issues.add(
      const AgreementFieldIssue(
        'brokerageTotal',
        'Total brokerage',
        'Keep the combined brokerage at or below ₹10 crore.',
        'brokerage',
      ),
    );
  }
  return issues;
}
