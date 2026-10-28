import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/property_onboarding.dart';
import 'onboarding_house_screens.dart';
import 'onboarding_widgets.dart';

PropertyOnboardingStore get _store => PropertyOnboardingStore.instance;
String _first(PropertyOnboarding item) => item.ownersFirst;

/// The clauses the broker and owner can change, in simple words.
List<(String, String)> keyPoints(PropertyOnboarding item) => [
  ('Rent', '${onbMoney(item.rent)} every month'),
  ('Deposit', onbMoney(item.deposit)),
  ('Your fee', item.answers.feeSummary(item.rent)),
  if (!item.answers.feeHasNoAmount) ('How owner pays your fee', item.answers.payWayText),
  ('Start date', item.answers.startDate.isEmpty ? 'Not set' : item.answers.startDate),
  ('How long', '${item.answers.months} months'),
  if (item.answers.notes.trim().isNotEmpty) ('Other notes', item.answers.notes),
];

// ---------------------------------------------------------------------------
// 4 questions
// ---------------------------------------------------------------------------

class AgreementQuestionsScreen extends StatelessWidget {
  const AgreementQuestionsScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => _QuestionsBody(item: item),
  );
}

class _QuestionsBody extends StatefulWidget {
  const _QuestionsBody({required this.item});
  final PropertyOnboarding item;

  @override
  State<_QuestionsBody> createState() => _QuestionsBodyState();
}

class _QuestionsBodyState extends State<_QuestionsBody> {
  int step = 0; // 0 fee · 1 pay way · 2 dates · 3 notes · 4 check
  late String feeType = widget.item.answers.feeType;
  late String payWay = widget.item.answers.payWay;
  late int months = widget.item.answers.months;
  late DateTime? start = DateTime.tryParse(widget.item.answers.startDate);
  late final fee = TextEditingController(
    text: widget.item.answers.feeValue == 0 ? '' : widget.item.answers.feeValue.toStringAsFixed(widget.item.answers.feeValue % 1 == 0 ? 0 : 1),
  );
  late final notes = TextEditingController(text: widget.item.answers.notes);
  String? feeError;
  String? dateError;
  bool understood20 = false;

  @override
  void dispose() {
    fee.dispose();
    notes.dispose();
    super.dispose();
  }

  double get feeValue => double.tryParse(fee.text.replaceAll(',', '').trim()) ?? 0;

  /// Three groups: paid once, paid every month, and no fee now.
  static const _feeGroups = [
    ('Paid one time', [
      ('days', 'Days of rent, one time', 'Example: 15 days of rent, once'),
      ('once', 'Fixed amount, one time', 'Pay once, then no more'),
    ]),
    ('Paid every month', [
      ('daysMonthly', 'Days of rent, every month', 'Example: 3 days of rent each month'),
      ('percent', 'Percent of rent', 'Every month. Example: 5%'),
      ('fixed', 'Fixed amount', 'Same rupees every month'),
    ]),
    ('No fee now', [
      ('none', 'No fee', 'We do not charge the owner'),
      ('later', 'Decide on every deal', 'Ask me later, deal by deal'),
    ]),
  ];
  /// A fee paid once.
  bool get _oneTime => feeType == 'days' || feeType == 'once';

  /// (key, label, hint, can pick). All money moves on our app, so for a one
  /// time fee only "we deduct it" can be picked now; for a monthly fee the
  /// owner can also pay the broker directly.
  List<(String, String, String, bool)> get _payWays => _oneTime
      ? const [
          ('cut', 'We deduct it from the first month\'s rent', 'Easy. Owner does nothing.', true),
          ('direct', 'Owner pays you directly', 'Not available now. Payments stay on our app, it is safer.', false),
          ('signing', 'Owner pays once, at signing', 'Not available now. Payments stay on our app, it is safer.', false),
        ]
      : const [
          ('cut', 'We deduct it from every month\'s rent', 'Easy. Owner does nothing.', true),
          ('direct', 'Owner pays you directly', 'Owner sends you the money.', true),
        ];

  /// Over 11 months the law needs a registered agreement. We cannot make that yet.
  Future<void> _pickMonths(int m) async {
    if (m <= 11) {
      setState(() => months = m);
      return;
    }
    final use11 = await onbConfirm(
      context,
      title: 'Registered agreement needed',
      message: 'An agreement for more than 11 months must be registered. We cannot make that in this app yet. For now we can make it for up to 11 months.',
      yes: 'Use 11 months',
      no: 'Close',
    );
    if (use11 && mounted) setState(() => months = 11);
  }

  /// Any number of months, 1 to 120.
  Future<void> _askMonths() async {
    final c = TextEditingController(text: const [11, 12, 24, 36].contains(months) ? '' : '$months');
    String? err;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.of(sheet).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How many months?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 20),
              OnbTextField(
                label: 'Number of months',
                controller: c,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                error: err,
                onChanged: (_) => setSheet(() => err = null),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save',
                onPressed: () {
                  final n = int.tryParse(c.text.trim());
                  if (n == null || n < 1 || n > 120) {
                    setSheet(() => err = 'Type a number from 1 to 120');
                    return;
                  }
                  Navigator.pop(sheet, n);
                },
              ),
            ],
          ),
        ),
      ),
    );
    c.dispose();
    if (picked != null && mounted) await _pickMonths(picked);
  }

  void _next() {
    if (step == 0) {
      if (feeType.isEmpty) {
        setState(() => feeError = 'Pick one');
        return;
      }
      if (feeType == 'none' || feeType == 'later') {
        // No amount to check, and no "how does the owner pay" question.
        setState(() {
          feeError = null;
          payWay = '';
          step = 2;
        });
        return;
      }
      // Keep the pay choice valid for this kind of fee.
      if (_oneTime && payWay != 'cut') payWay = 'cut';
      if (!_oneTime && payWay == 'signing') payWay = '';
      final v = feeValue;
      if (v <= 0) {
        setState(() => feeError = 'Type a number');
        return;
      }
      if (feeType == 'percent' && v > 100) {
        setState(() => feeError = 'This cannot be more than 100');
        return;
      }
      if (feeType == 'percent' && v > 20 && !understood20) {
        setState(() {
          feeError = '$v% is a lot. Tap Next again if it is right.';
          understood20 = true;
        });
        return;
      }
      if (feeType == 'days' && v > 365) {
        setState(() => feeError = 'Please check the number of days');
        return;
      }
      if (feeType == 'daysMonthly' && v > 30) {
        setState(() => feeError = 'A month has only 30 days. Please check.');
        return;
      }
      if (feeType != 'percent' && feeType != 'days' && feeType != 'daysMonthly' && v > widget.item.rent * 12) {
        setState(() => feeError = 'This is more than a year of rent. Please check.');
        return;
      }
    }
    if (step == 1 && payWay.isEmpty) {
      setState(() => feeError = 'Pick one');
      return;
    }
    if (step == 2) {
      if (start == null) {
        setState(() => dateError = 'Pick a start date');
        return;
      }
      final today = DateTime.now();
      if (start!.isBefore(DateTime(today.year, today.month, today.day).subtract(const Duration(days: 30)))) {
        setState(() => dateError = 'This date is long past. Pick a new one.');
        return;
      }
    }
    setState(() {
      feeError = null;
      dateError = null;
      step++;
    });
  }

  Future<void> _send() async {
    final item = widget.item;
    final answers = AgreementAnswers(
      feeType: feeType,
      feeValue: feeValue,
      payWay: payWay,
      startDate: start == null ? '' : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}',
      months: months,
      notes: notes.text.trim(),
    );
    await _store.update(item.id, (i) => i.copyWith(answers: answers, phase: OnboardingPhase.preparing));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final titles = ['What is your fee?', 'How does the owner pay you?', 'When does it start?', 'Anything else?', 'Check once'];
    Widget body;
    switch (step) {
      case 0:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (group, options) in _feeGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6, left: 4),
                child: Text(group, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppColors.muted)),
              ),
            for (final (key, label, hint) in options) ...[
              OnbRow(
                icon: feeType == key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                tone: feeType == key ? 'info' : 'mute',
                title: label,
                subtitle: hint,
                chevron: false,
                onTap: () => setState(() {
                  feeType = key;
                  feeError = null;
                  understood20 = false;
                }),
              ),
              // The number box opens right under the option that was picked.
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: feeType == key && key != 'none' && key != 'later'
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OnbTextField(
                              label: switch (key) {
                                'days' || 'daysMonthly' => 'How many days of rent?',
                                'percent' => 'How many percent?',
                                _ => 'How many rupees?',
                              },
                              controller: fee,
                              keyboard: TextInputType.number,
                              prefix: key == 'fixed' || key == 'once' ? '₹ ' : null,
                              error: feeError,
                              onChanged: (_) => setState(() {
                                feeError = null;
                                understood20 = false;
                              }),
                            ),
                            if (feeValue > 0 && feeError == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Fee: ${AgreementAnswers(feeType: feeType, feeValue: feeValue).feeSummary(item.rent)}',
                                  style: const TextStyle(fontSize: 16, color: AppColors.muted),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
            ],
            if ((feeType.isEmpty || feeType == 'none' || feeType == 'later') && feeError != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(feeError!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
          ],
        );
      case 1:
        body = Column(
          children: [
            for (final (key, label, hint, canPick) in _payWays)
              Opacity(
                opacity: canPick ? 1 : 0.5,
                child: OnbRow(
                  icon: !canPick
                      ? Icons.block
                      : payWay == key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  tone: payWay == key && canPick ? 'info' : 'mute',
                  title: label,
                  subtitle: hint,
                  chevron: false,
                  onTap: canPick
                      ? () => setState(() {
                          payWay = key;
                          feeError = null;
                        })
                      : null,
                ),
              ),
            if (feeError != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(feeError!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
          ],
        );
      case 2:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnbRow(
              icon: Icons.calendar_today_outlined,
              tone: 'info',
              title: 'Start date',
              subtitle: start == null ? 'Tap to pick' : '${start!.day}/${start!.month}/${start!.year}',
              onTap: () async {
                final today = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: start ?? today,
                  firstDate: today.subtract(const Duration(days: 60)),
                  lastDate: today.add(const Duration(days: 730)),
                );
                if (picked != null) {
                  setState(() {
                    start = picked;
                    dateError = null;
                  });
                }
              },
            ),
            if (dateError != null)
              Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(dateError!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
            const SizedBox(height: 18),
            const Text('For how many months?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.heading)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [11, 12, 24, 36])
                  ChoiceChip(
                    label: Text('$m months'),
                    selected: months == m,
                    onSelected: (_) => _pickMonths(m),
                    showCheckmark: false,
                    selectedColor: AppColors.primarySoft,
                    labelStyle: TextStyle(fontSize: 15, color: months == m ? AppColors.primaryDark : AppColors.body),
                    side: BorderSide(color: months == m ? AppColors.primary : AppColors.border),
                    shape: const StadiumBorder(),
                  ),
                ChoiceChip(
                  label: Text(const [11, 12, 24, 36].contains(months) ? 'Other' : '$months months'),
                  avatar: const [11, 12, 24, 36].contains(months) ? const Icon(Icons.edit_outlined, size: 18) : null,
                  selected: !const [11, 12, 24, 36].contains(months),
                  onSelected: (_) => _askMonths(),
                  showCheckmark: false,
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(fontSize: 15, color: !const [11, 12, 24, 36].contains(months) ? AppColors.primaryDark : AppColors.body),
                  side: BorderSide(color: !const [11, 12, 24, 36].contains(months) ? AppColors.primary : AppColors.border),
                  shape: const StadiumBorder(),
                ),
              ],
            ),
          ],
        );
      case 3:
        body = OnbTextField(
          label: 'Other things you agreed (optional)',
          hint: 'Example: no pets, owner pays maintenance',
          controller: notes,
          maxLines: 4,
        );
      default:
        body = OnbCard(
          child: Column(
            children: [
              OnbKeyValue('Fee', AgreementAnswers(feeType: feeType, feeValue: feeValue).feeSummary(item.rent)),
              if (feeType != 'none' && feeType != 'later') OnbKeyValue('How we get it', AgreementAnswers(feeType: feeType, payWay: payWay).payWayText),
              OnbKeyValue('Starts', start == null ? '-' : '${start!.day}/${start!.month}/${start!.year}'),
              OnbKeyValue('For', '$months months'),
              OnbKeyValue('Notes', notes.text.trim().isEmpty ? 'None' : notes.text.trim(), last: true),
            ],
          ),
        );
    }
    return OnbPage(
      title: titles[step],
      progress: step + 1,
      progressTotal: 5,
      stepLabel: 'Step ${step + 1} of 5',
      showCall: true,
      onBack: () {
        if (step == 0) {
          context.pop();
        } else {
          setState(() {
            feeError = null;
            dateError = null;
            // No fee, or decided later: there was no "how does the owner pay" step.
            step = (step == 2 && (feeType == 'none' || feeType == 'later')) ? 0 : step - 1;
          });
        }
      },
      footer: [
        PrimaryButton(
          label: step == 4 ? 'Make the agreement' : 'Next',
          onPressed: step == 4 ? _send : _next,
        ),
      ],
      children: [body],
    );
  }
}

// ---------------------------------------------------------------------------
// Draft: key points
// ---------------------------------------------------------------------------

class DraftScreen extends StatelessWidget {
  const DraftScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => OnbPage(
      title: 'Draft ${item.draftNo}',
      subtitle: 'Key points in simple words. Tap one to ask a change.',
      footer: [PrimaryButton(label: 'Back', onPressed: () => context.pop())],
      children: [
        OnbBanner(item.draftSent ? 'The owner sees the same points.' : 'Check these. Then send to ${_first(item)}.', icon: Icons.visibility_outlined, kind: 'info'),
        const SizedBox(height: 14),
        OnbCard(
          child: Column(
            children: [
              for (final (label, value) in keyPoints(item))
                OnbRow(
                  icon: Icons.notes_outlined,
                  title: label,
                  subtitle: value,
                  onTap: item.ownerAgreedFinal ? null : () => context.push('/broker/onboarding/${item.id}/change?clause=${Uri.encodeComponent(label)}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text('Our team keeps the legal words correct. You only say what you want in simple words.', style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Read the full agreement (owner and broker)
// Same format as "Read full agreement" in the rent agreement review: a notice,
// the people who sign, the details in coloured cards (yellow = captured,
// green = changed since the first draft), then the clauses.
// ---------------------------------------------------------------------------

/// The broker who signs. It is whoever is registered and logged in: our own
/// team or an outside broker.
String _brokerName() {
  try {
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {
    // Not signed in (or not available): use a plain word instead.
  }
  return 'You (the broker)';
}

class OwnerAgreementScreen extends StatelessWidget {
  const OwnerAgreementScreen({required this.id, super.key});
  final String id;

  static const _yellow = Color(0xFFFFF4CE);
  static const _green = Color(0xFFE5F8F0);

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) {
      final broker = _brokerName();
      final answers = item.answers;
      final decided = answers.feeType.isNotEmpty;
      final changedLabels = {for (final c in item.changes) c.clause};
      final started = answers.startDate.isEmpty ? 'Not decided yet' : answers.startDate;
      final terms = <(String, String, bool)>[
        ('Property', item.address.trim().isEmpty ? 'Address comes from the owner\'s documents' : item.address, true),
        (item.hasManyOwners ? 'Owners' : 'Owner', item.ownersFull, true),
        ('Broker', broker, true),
        ('Rent the owner wants', '${onbMoney(item.rent)} every month', true),
        ('Deposit', onbMoney(item.deposit), true),
        ('Broker fee', decided ? answers.feeSummary(item.rent) : 'Not decided yet', decided),
        ('How the fee is paid', (decided ? answers.payWayText : 'Not decided yet'), decided),
        ('Start date', started, answers.startDate.isNotEmpty),
        ('How long', '${answers.months} months', true),
        if (answers.notes.trim().isNotEmpty) ('Other notes', answers.notes, true),
      ];
      // Names the owner and broker use for the same thing in the key points.
      const alias = {
        'Broker fee': 'Your fee',
        'How the fee is paid': 'How owner pays your fee',
        'Rent the owner wants': 'Rent',
      };
      final clauses = <(String, String)>[
        ('1. What the broker does', '$broker finds and checks tenants, takes tenant calls and complaints, and coordinates small repairs and the move-in and move-out checks. The owner picks the tenant and signs the tenant\'s agreement in their own name.'),
        ('2. What the owner does', 'The owner gives true documents, answers approval requests on time, pays the broker fee and the costs that are valid, and is responsible for any dispute about who owns the house.'),
        ('3. The fee', !decided
            ? 'The fee is not decided yet. It will be written here once you tell us.'
            : answers.feeType == 'none'
                ? 'The broker does not charge the owner any fee under this agreement.'
                : answers.feeType == 'later'
                    ? 'The fee is not fixed now. The broker and the owner agree it for every deal, in writing, before that deal starts.'
                    : '${answers.feeSummary(item.rent)}. ${answers.payWayText}. The fee includes all taxes.'),
        ('4. Rent and deposit', 'The tenant\'s rent and deposit are for the owner. The broker does not keep them unless the owner agrees in writing.'),
        ('5. How long', '${answers.months} months${answers.startDate.isEmpty ? '' : ' from ${answers.startDate}'}. After that it ends, unless both sides renew in writing.'),
        ('6. Keeping things private', 'Both sides keep names, numbers, money and tenant details private. This continues for 3 years after the agreement ends.'),
        ('7. If something goes wrong', 'Each side is responsible for its own mistakes. The broker\'s total responsibility is limited to the fees paid in the last 12 months. Neither side pays for indirect loss.'),
        ('8. Ending the agreement', 'Either side can end it by telling the other in writing. The notice time is set in the final draft.'),
      ];
      return OnbPage(
        title: 'Full agreement',
        subtitle: 'Between the owner and the broker.',
        footer: [PrimaryButton(label: 'Back', onPressed: () => context.pop())],
        children: [
          OnbBanner(
            item.phase == OnboardingPhase.papers || item.phase == OnboardingPhase.questions || item.phase == OnboardingPhase.preparing
                ? 'This is how the agreement will read. The final draft is still being made. Yellow means we have it from you.'
                : 'This is the full agreement for ${item.ownersFirst} and $broker. Yellow means captured. Green means changed since the first draft.',
            icon: Icons.description_outlined,
            kind: 'info',
          ),
          const SizedBox(height: 14),
          const Text('Who signs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(height: 8),
          OnbCard(
            child: Column(
              children: [
                for (var o = 0; o < item.ownerCount; o++)
                  OnbRow(
                    icon: Icons.person_outline,
                    title: item.ownerNameAt(o),
                    subtitle: item.hasManyOwners ? 'Owner ${o + 1}' : 'Owner',
                    chevron: false,
                  ),
                OnbRow(icon: Icons.badge_outlined, title: broker, subtitle: 'Broker', chevron: false),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('The details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(height: 8),
          for (final (label, value, known) in terms) ...[
            Builder(
              builder: (context) {
                final changed = changedLabels.contains(label) || changedLabels.contains(alias[label]);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: changed ? _green : (known ? _yellow : AppColors.surfaceMuted),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$label${changed ? ' · Changed' : ''}', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      SelectableText(value, style: const TextStyle(fontSize: 17, height: 24 / 17, color: AppColors.heading)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const Text('The words', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(height: 8),
          for (final (title, text) in clauses) ...[
            OnbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
                  const SizedBox(height: 6),
                  SelectableText(text, style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            'Plain words for reading. Our team keeps the legal words correct in the final draft. Signing, stamp paper and payment come in the next stages.',
            style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Ask a change (broker to owner)
// ---------------------------------------------------------------------------

class AskChangeScreen extends StatefulWidget {
  const AskChangeScreen({required this.id, this.clause, super.key});
  final String id;
  final String? clause;

  @override
  State<AskChangeScreen> createState() => _AskChangeScreenState();
}

class _AskChangeScreenState extends State<AskChangeScreen> {
  final text = TextEditingController();
  String? clause;
  String? error;

  @override
  void initState() {
    super.initState();
    clause = widget.clause;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      final points = keyPoints(item);
      final before = clause == null ? '' : points.firstWhere((p) => p.$1 == clause, orElse: () => ('', '')).$2;
      final existing = item.changes.where((c) => c.clause == clause).toList();
      final blocked = existing.any((c) => c.round >= 3 && c.status != 'agreed');
      return OnbPage(
        title: 'Ask a change',
        subtitle: 'Tell ${_first(item)} what you want.',
        footer: [
          PrimaryButton(
            label: 'Send to ${_first(item)}',
            onPressed: blocked
                ? null
                : () async {
                    if (clause == null) {
                      setState(() => error = 'Pick what to change');
                      return;
                    }
                    if (text.text.trim().isEmpty) {
                      setState(() => error = 'Type what you want');
                      return;
                    }
                    await _store.update(item.id, (i) => i.copyWith(
                      changes: [
                        ...i.changes,
                        DraftChange(
                          id: 'c${i.changes.length + 1}',
                          clause: clause!,
                          before: before,
                          asked: text.text.trim(),
                          askedBy: 'broker',
                          status: 'waitingOwner',
                          round: existing.length + 1,
                        ),
                      ],
                      draftSent: true,
                      draftSentAt: DateTime.now().millisecondsSinceEpoch,
                    ));
                    if (context.mounted) context.pop();
                  },
          ),
        ],
        children: [
          if (blocked)
            const OnbBanner('You both asked 3 times. Please call each other to finish this point.', kind: 'need', icon: Icons.phone_outlined),
          const Text('What do you want to change?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.heading)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in points)
                ChoiceChip(
                  label: Text(p.$1),
                  selected: clause == p.$1,
                  onSelected: (_) => setState(() {
                    clause = p.$1;
                    error = null;
                  }),
                  showCheckmark: false,
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(fontSize: 15, color: clause == p.$1 ? AppColors.primaryDark : AppColors.body),
                  side: BorderSide(color: clause == p.$1 ? AppColors.primary : AppColors.border),
                  shape: const StadiumBorder(),
                ),
            ],
          ),
          if (clause != null) ...[
            const SizedBox(height: 14),
            OnbCard(child: OnbKeyValue('Now', before, last: true)),
            const SizedBox(height: 14),
            OnbTextField(label: 'What do you want instead?', controller: text, maxLines: 3, error: error, onChanged: (_) => setState(() => error = null)),
          ] else if (error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// All changes
// ---------------------------------------------------------------------------

String _changeLabel(DraftChange c) => switch (c.status) {
  'waitingYou' => 'Your turn',
  'waitingOwner' => 'Waiting owner',
  'agreed' => 'Agreed',
  _ => 'Not agreed',
};
String _changeKind(DraftChange c) => switch (c.status) {
  'waitingYou' => 'wait',
  'waitingOwner' => 'info',
  'agreed' => 'ok',
  _ => 'need',
};

class ChangesScreen extends StatelessWidget {
  const ChangesScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => OnbPage(
      title: 'Changes',
      subtitle: 'Each point can go back and forth 3 times.',
      footer: [
        if (!item.ownerAgreedFinal) PrimaryButton(label: 'Ask a change', onPressed: () => context.push('/broker/onboarding/${item.id}/change')),
        if (!item.ownerAgreedFinal) const SizedBox(height: 10),
        OnbSecondaryButton(label: 'Back', onPressed: () => context.pop()),
      ],
      children: [
        if (item.changes.isEmpty)
          const OnbCentered(icon: Icons.compare_arrows, kind: 'mute', title: 'No changes yet', message: 'When you or the owner ask a change, it shows here.')
        else
          OnbCard(
            child: Column(
              children: [
                for (final c in item.changes.reversed)
                  OnbRow(
                    icon: c.askedBy == 'owner' ? Icons.person_outline : Icons.badge_outlined,
                    tone: _changeKind(c),
                    title: c.clause,
                    subtitle: '${c.askedBy == 'owner' ? _first(item) : 'You'} asked: ${c.asked}',
                    trailing: OnbPill(_changeLabel(c), _changeKind(c)),
                    onTap: c.status == 'waitingYou' ? () => context.push('/broker/onboarding/${item.id}/change/${c.id}') : null,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class ChangeDecisionScreen extends StatefulWidget {
  const ChangeDecisionScreen({required this.id, required this.changeId, super.key});
  final String id;
  final String changeId;

  @override
  State<ChangeDecisionScreen> createState() => _ChangeDecisionScreenState();
}

class _ChangeDecisionScreenState extends State<ChangeDecisionScreen> {
  bool suggesting = false;
  final other = TextEditingController();
  String? error;

  @override
  void dispose() {
    other.dispose();
    super.dispose();
  }

  Future<void> _save(PropertyOnboarding item, DraftChange c, DraftChange updated, String versionNote) async {
    await _store.update(item.id, (i) {
      final changes = [for (final x in i.changes) x.id == c.id ? updated : x];
      final agreed = updated.status == 'agreed';
      final n = agreed ? i.draftNo + 1 : i.draftNo;
      return i.copyWith(
        changes: changes,
        draftNo: n,
        versions: agreed ? [...i.versions, DraftVersion(number: n, summary: versionNote, at: DateTime.now().millisecondsSinceEpoch)] : i.versions,
        ownerAgreedFinal: false,
        draftSent: true,
        draftSentAt: DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      final matches = item.changes.where((c) => c.id == widget.changeId);
      if (matches.isEmpty) {
        return OnbPage(title: 'Change', footer: [PrimaryButton(label: 'Back', onPressed: () => context.pop())], children: const [OnbBanner('This change is not here anymore.')]);
      }
      final c = matches.first;
      final first = _first(item);
      final canSuggest = c.round < 3;
      return OnbPage(
        title: '$first asked a change',
        subtitle: c.clause,
        footer: [
          if (!suggesting) ...[
            PrimaryButton(
              label: 'Yes, agree',
              onPressed: () async {
                await _save(item, c, c.copyWith(status: 'agreed'), '${c.clause}: ${c.asked}');
                if (context.mounted) context.pop();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OnbSecondaryButton(
                    label: 'No',
                    onPressed: () async {
                      final no = await onbConfirm(
                        context,
                        title: 'Say no?',
                        message: '$first is told you do not agree. You can call $first to talk.',
                        yes: 'Say no',
                        no: 'Go back',
                        danger: true,
                      );
                      if (!no) return;
                      await _save(item, c, c.copyWith(status: 'notAgreed'), '');
                      if (context.mounted) context.pop();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OnbSecondaryButton(
                    label: 'Suggest other',
                    onPressed: canSuggest ? () => setState(() => suggesting = true) : null,
                  ),
                ),
              ],
            ),
            if (!canSuggest)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('You both asked 3 times. Please call to finish this point.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              ),
          ] else ...[
            PrimaryButton(
              label: 'Send my answer',
              onPressed: () async {
                if (other.text.trim().isEmpty) {
                  setState(() => error = 'Type your answer');
                  return;
                }
                await _save(
                  item,
                  c,
                  c.copyWith(asked: other.text.trim(), askedBy: 'broker', status: 'waitingOwner', round: c.round + 1),
                  '',
                );
                if (context.mounted) context.pop();
              },
            ),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'Back', onPressed: () => setState(() => suggesting = false)),
          ],
        ],
        children: [
          OnbCard(
            child: Column(
              children: [
                OnbKeyValue('Before', c.before.isEmpty ? '-' : c.before),
                OnbKeyValue('$first asks', c.asked, last: c.note.isEmpty),
                if (c.note.isNotEmpty) OnbKeyValue('Note', c.note, last: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Round ${c.round} of 3', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          if (suggesting) ...[
            const SizedBox(height: 14),
            OnbTextField(label: 'What do you suggest?', controller: other, maxLines: 3, error: error, onChanged: (_) => setState(() => error = null)),
          ],
        ],
      );
    },
  );
}

class VersionsScreen extends StatelessWidget {
  const VersionsScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => OnbPage(
      title: 'Versions',
      subtitle: 'Every saved draft. Nothing is lost.',
      footer: [PrimaryButton(label: 'Back', onPressed: () => context.pop())],
      children: [
        OnbCard(
          child: Column(
            children: [
              for (final v in item.versions.reversed)
                OnbRow(
                  icon: Icons.description_outlined,
                  tone: v.number == item.draftNo ? 'info' : 'mute',
                  title: 'Draft ${v.number}',
                  subtitle: v.summary.isEmpty ? 'Changed' : v.summary,
                  chevron: false,
                  trailing: v.number == item.draftNo ? const OnbPill('Latest', 'info') : null,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Sign with a code
// ---------------------------------------------------------------------------

class SignScreen extends StatefulWidget {
  const SignScreen({required this.id, super.key});
  final String id;

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  bool codeSent = false;
  int tries = 0;
  final code = TextEditingController();
  String? error;

  /// Test code. A real SMS code needs the e-sign provider.
  static const testCode = '123456';

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      final locked = tries >= 3;
      return OnbPage(
        title: codeSent ? 'Type the code' : 'Sign the agreement',
        subtitle: codeSent ? 'We sent a 6 digit code to your phone.' : 'You sign on your phone. No paper, no pen.',
        footer: [
          if (!codeSent)
            PrimaryButton(label: 'Send me a code', onPressed: () => setState(() => codeSent = true))
          else ...[
            PrimaryButton(
              label: 'Sign now',
              onPressed: locked
                  ? null
                  : () async {
                      if (code.text.trim() != testCode) {
                        setState(() {
                          tries++;
                          error = tries >= 3 ? 'Too many wrong codes. Ask for a new code.' : 'This code is wrong. Try again.';
                        });
                        return;
                      }
                      await _store.update(item.id, (i) => i.copyWith(
                        brokerSigned: true,
                        phase: i.allOwnersSigned ? OnboardingPhase.ready : i.phase,
                      ));
                      if (context.mounted) context.pop();
                    },
            ),
            const SizedBox(height: 10),
            OnbSecondaryButton(
              label: 'Send a new code',
              onPressed: () => setState(() {
                tries = 0;
                error = null;
                code.clear();
              }),
            ),
          ],
        ],
        children: [
          OnbCard(
            child: Column(
              children: [
                OnbKeyValue('House', item.houseName),
                OnbKeyValue(item.hasManyOwners ? 'Owners' : 'Owner', item.ownersFull),
                OnbKeyValue('Your fee', item.answers.feeSummary(item.rent), last: true),
              ],
            ),
          ),
          if (codeSent) ...[
            const SizedBox(height: 16),
            OnbTextField(label: 'Code', controller: code, keyboard: TextInputType.number, error: error, onChanged: (_) => setState(() => error = null)),
            const SizedBox(height: 8),
            const Text('Test only: the code is 123456.', style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ],
      );
    },
  );
}
