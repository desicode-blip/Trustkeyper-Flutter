import 'package:flutter/services.dart' show rootBundle;

import '../features/broker/data/agreement_filler.dart' show AgreementFiller;
import 'tk2_deal.dart';
import 'tk2_store.dart';

/// The rent agreement text for a deal: TrustKeyper's leave & licence template
/// (`assets/agreements/rent_leave_licence.md`) with the broker's terms filled
/// in. Anything not known yet shows as a blank line to fill.
class Tk2Agreement {
  static const asset = 'assets/agreements/rent_leave_licence.md';
  static const gap = '__________';

  static Future<String> load() => rootBundle.loadString(asset);

  static String fill(String template, Tk2Deal d, {DateTime? today}) {
    final t = d.defaultTerms(today ?? DateTime.now());
    String text(String k) => (t[k] as String? ?? '').trim().isEmpty ? gap : (t[k] as String).trim();
    int n(String k) => (t[k] as num?)?.toInt() ?? 0;
    final start = DateTime.tryParse(t['start'] as String? ?? '') ?? (today ?? DateTime.now());
    final end = DateTime(start.year, start.month + n('months'), start.day);
    final tenantDetails = Map<String, dynamic>.from(d.t['details'] as Map? ?? const {});
    final values = {
      'today': AgreementFiller.prettyDate(today ?? DateTime.now()),
      'start': AgreementFiller.prettyDate(start),
      'end': AgreementFiller.prettyDate(end),
      'owner': d.ownerName.isEmpty ? gap : d.ownerName,
      'owner_address': text('ownerAddress'),
      'tenant': d.tenantName.isEmpty ? gap : d.tenantName,
      'tenant_address': (tenantDetails['address'] as String? ?? '').trim().isEmpty ? gap : (tenantDetails['address'] as String).trim(),
      'premises': text('address'),
      'months': '${n('months')}',
      'lock_in': '${n('lockIn')}',
      'notice': '${n('notice')}',
      'deposit': 'Rs. ${Tk2Store.money(n('deposit')).replaceFirst('₹', '')}/-',
      'rent': 'Rs. ${Tk2Store.money(n('rent')).replaceFirst('₹', '')}/-',
      'due_day': _ordinal(n('dueDay')),
      'late_fee': n('lateFee') > 0 ? ' A late fee of Rs. ${n('lateFee')}/- per day applies after the due date.' : '',
      'maintenance': d.maintenance > 0
          ? ' The LICENSEES shall also pay the society maintenance of ${Tk2Store.money(d.maintenance)} per month.'
          : ' Society maintenance is included in the licence charges.',
      'painting': t['paint'] == true
          ? 'The cost of painting/repainting at the time of vacating shall be deducted from the security deposit.'
          : 'Normal wear and tear, and the cost of painting/repainting will not be the reason for deductions from the security deposit.',
      'refund_days': '${n('refundDays')}',
      'cleaning': t['clean'] == true
          ? 'The house needs to be cleaned by the LICENSEES at his cost at the time of vacating the apartment.'
          : 'The LICENSEES shall hand over the house in a reasonably clean condition at the time of vacating.',
      'people': '${n('people')}',
      'pets': t['pets'] == true ? 'Pets are allowed, subject to the society rules.' : 'Pets are not allowed in the said premises.',
      'annexure': d.items.isEmpty ? gap : [for (final (i, item) in d.items.indexed) '${i + 1}. ${item.count} - ${item.name}.'].join('\n\n'),
    };
    return template.replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) => values[m[1]] ?? gap);
  }

  static String _ordinal(int d) => d >= 11 && d <= 13 ? '${d}th' : '$d${const {1: 'st', 2: 'nd', 3: 'rd'}[d % 10] ?? 'th'}';

  /// Blank lines still in the text (what the broker must still fill).
  static int gaps(String filled) => gap.allMatches(filled).length;
}
