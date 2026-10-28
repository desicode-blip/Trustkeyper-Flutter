import 'property_onboarding.dart';

/// One legal template (owner and manager agreement) kept as a Google Doc.
/// The app never keeps a copy of the words: the text is fetched from Drive
/// every time an agreement is made, so an edit in the doc reaches every new
/// agreement. (The fetch needs the backend. See docs/AGREEMENT-TEMPLATES.md.)
class AgreementTemplate {
  const AgreementTemplate({
    required this.id,
    required this.name,
    required this.when,
    this.driveDocId,
    this.rentThroughPlatform = false,
  });

  final String id;
  final String name;

  /// When it is used, in simple words.
  final String when;

  /// Google Docs file id. Null until the link is shared.
  final String? driveDocId;

  /// The tenant must pay the rent through the TrustKeyper app.
  final bool rentThroughPlatform;

  Uri? get exportUrl => driveDocId == null
      ? null
      : Uri.https('docs.google.com', '/document/d/$driveDocId/export', {'format': 'txt'});
}

/// Which template, and anything the broker should fix first.
class TemplateChoice {
  const TemplateChoice(this.template, {this.warning});
  final AgreementTemplate? template;
  final String? warning;
}

abstract final class AgreementTemplates {
  static const monthlyPercent = AgreementTemplate(
    id: 'monthly_percent',
    name: 'Every month: percent of rent',
    when: 'Fee is a percent of the rent, every month. The owner pays directly or we deduct it.',
  );

  static const monthlyDays = AgreementTemplate(
    id: 'monthly_days',
    name: 'Every month: days of rent',
    when: 'Fee is a few days of rent, every month (3 days is 10% of the rent). The tenant pays the rent on our app and we deduct the fee.',
    rentThroughPlatform: true,
  );

  static const yearlyDays = AgreementTemplate(
    id: 'yearly_days',
    name: 'Once a year: 15 days of rent',
    when: 'Fee is days of rent, paid one time for each year. Paid directly or taken from the first month of the year.',
    driveDocId: '12Duaqq-_kU3H_915GM3mLh0mIp2dbcYgniTnHQCjNZ0',
  );

  static const nri = AgreementTemplate(
    id: 'nri_hybrid',
    name: 'Owner lives outside India (NRI)',
    when: 'The owner is an NRI. TrustKeyper is the broker, collects the rent and pays the owner.',
    driveDocId: '13cdao3RgQ5r8VaH5Tepk6S4Ri28qr-P6fKV5XcBX0EQ',
    rentThroughPlatform: true,
  );

  static const all = [monthlyPercent, monthlyDays, yearlyDays, nri];

  /// Picks the template from what we know. Only our own templates exist so
  /// far; for another broker, or a fee with no template yet, the team picks.
  static TemplateChoice pick(
    AgreementAnswers answers, {
    required bool isNri,
    required bool brokerIsTrustkeyper,
  }) {
    if (!brokerIsTrustkeyper) {
      return const TemplateChoice(null, warning: 'Templates for other brokers are not added yet. Our team will pick one.');
    }
    if (answers.feeType.isEmpty) return const TemplateChoice(null);
    if (answers.feeHasNoAmount) {
      return const TemplateChoice(null, warning: 'No template for an agreement without a fee yet. Our team will pick one.');
    }
    if (isNri) {
      return const TemplateChoice(nri, warning: null);
    }
    switch (answers.feeType) {
      case 'percent':
        return const TemplateChoice(monthlyPercent);
      case 'daysMonthly':
        return TemplateChoice(
          monthlyDays,
          warning: answers.payWay == 'direct' ? 'This agreement needs the rent to be paid on our app. Choose "We deduct it".' : null,
        );
      case 'days':
        return const TemplateChoice(yearlyDays);
      default:
        return const TemplateChoice(null, warning: 'No template for this kind of fee yet. Our team will pick one.');
    }
  }
}
