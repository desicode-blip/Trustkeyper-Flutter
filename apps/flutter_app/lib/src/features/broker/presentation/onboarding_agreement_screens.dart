import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
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

/// Change one part (fee, dates or notes) of an agreement that is already made.
class AgreementEditScreen extends StatelessWidget {
  const AgreementEditScreen({required this.id, required this.part, super.key});
  final String id;
  final String part;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => _QuestionsBody(
      item: item,
      part: AgreementAnswers.groups.contains(part) ? part : 'fee',
    ),
  );
}

class _QuestionsBody extends StatefulWidget {
  const _QuestionsBody({required this.item, this.part});
  final PropertyOnboarding item;

  /// Null: the first time through all the questions. Otherwise the broker is
  /// changing one part of a finished agreement: fee · dates · notes.
  final String? part;

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
  String? payError;
  bool understood20 = false;
  bool _discard = false;

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

  // ---- changing one part of a finished agreement ----

  bool get _editing => widget.part != null;

  /// Keeps "how the owner pays" valid for the fee that is picked.
  void _fixPay() {
    if (feeType == 'none' || feeType == 'later') {
      payWay = '';
    } else if (_oneTime) {
      payWay = 'cut';
    } else if (payWay == 'signing') {
      payWay = '';
    }
  }

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  AgreementAnswers get _now => widget.item.answers.copyWith(
    feeType: feeType,
    feeValue: (feeType == 'none' || feeType == 'later') ? 0 : feeValue,
    payWay: payWay,
    startDate: start == null ? '' : _iso(start!),
    months: months,
    notes: notes.text.trim(),
  );

  bool get _changedNow => _editing && !widget.item.answers.sameGroup(widget.part!, _now);

  void _resetFee() {
    final a = widget.item.answers;
    feeType = a.feeType;
    payWay = a.payWay;
    fee.text = a.feeValue == 0 ? '' : a.feeValue.toStringAsFixed(a.feeValue % 1 == 0 ? 0 : 1);
    feeError = null;
    payError = null;
    understood20 = false;
  }

  /// Why the fee cannot be saved yet, or null.
  String? _feeProblem() {
    if (feeType.isEmpty) return 'Pick one';
    if (feeType == 'none' || feeType == 'later') return null;
    final v = feeValue;
    if (v <= 0) return 'Type a number';
    if (feeType == 'percent' && v > 100) return 'This cannot be more than 100';
    if (feeType == 'percent' && v > 20 && !understood20) {
      understood20 = true;
      return '$v% is a lot. Tap Save again if it is right.';
    }
    if (feeType == 'days' && v > 365) return 'Please check the number of days';
    if (feeType == 'daysMonthly' && v > 30) return 'A month has only 30 days. Please check.';
    if (feeType != 'percent' && feeType != 'days' && feeType != 'daysMonthly' && v > widget.item.rent * 12) {
      return 'This is more than a year of rent. Please check.';
    }
    return null;
  }

  /// "Leave without saving?" Returns true when it is fine to go.
  Future<bool> _okToLeave() async {
    if (!_changedNow) return true;
    final keep = await onbConfirm(
      context,
      title: 'Leave without saving?',
      message: 'You changed ${AgreementAnswers.groupLabel(widget.part!).toLowerCase()}. If you go back now, it will not be saved.',
      yes: 'Keep editing',
      no: 'Leave, don\'t save',
    );
    return !keep;
  }

  Future<void> _leaveEdit() async {
    if (!await _okToLeave() || !mounted) return;
    setState(() => _discard = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<void> _saveEdit() async {
    final item = widget.item;
    final part = widget.part!;
    if (!_changedNow) {
      context.pop();
      return;
    }
    if (part == 'fee') {
      final problem = _feeProblem();
      if (problem != null) {
        setState(() => feeError = problem);
        return;
      }
      if (feeType != 'none' && feeType != 'later' && payWay.isEmpty) {
        setState(() => payError = 'Pick one');
        return;
      }
      // A one time fee cannot be paid directly any more: ask before changing it too.
      if (item.answers.payWay == 'direct' && _oneTime) {
        final change = await onbConfirm(
          context,
          title: 'Change how the owner pays too?',
          message: 'A one time fee is deducted from the first month\'s rent. The owner cannot pay it directly.',
          yes: 'Yes, deduct it',
          no: 'No, keep my fee as before',
        );
        if (!mounted) return;
        if (!change) {
          setState(_resetFee);
          return;
        }
      }
    }
    if (part == 'dates' && start == null) {
      setState(() => dateError = 'Pick a start date');
      return;
    }
    if (item.phase == OnboardingPhase.review && item.draftSent) {
      if (!await confirmNewDraft(context, item, yes: 'Yes, change and resend') || !mounted) return;
    }
    await _store.changeAgreementPart(item.id, part, _now);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(switch (part) {
          'fee' => 'Fee changed',
          'dates' => 'Start date and length changed',
          _ => 'Notes changed',
        }),
        behavior: SnackBarBehavior.floating,
      ));
    context.pop();
  }

  Widget _editBar() => Container(
    width: double.infinity,
    color: const Color(0xFFFFF6D6),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      children: [
        const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF8A6A00)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Editing agreement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B5200)))),
        TextButton(
          onPressed: _leaveEdit,
          child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
        ),
      ],
    ),
  );

  Widget _buildEdit(BuildContext context) {
    final item = widget.item;
    final part = widget.part!;
    final changed = _changedNow;
    final hasError = feeError != null || payError != null || dateError != null;
    final hasAmount = feeType.isNotEmpty && feeType != 'none' && feeType != 'later';
    final body = switch (part) {
      'fee' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _feeBody(item),
          if (hasAmount) ...[
            const SizedBox(height: 12),
            const Text('How does the owner pay you?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.heading)),
            const SizedBox(height: 10),
            _payBody(),
          ],
        ],
      ),
      'dates' => _datesBody(),
      _ => _notesBody(),
    };
    return PopScope(
      canPop: !changed || _discard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveEdit();
      },
      child: OnbPage(
        title: 'Agreement details',
        subtitle: switch (part) {
          'fee' => 'What is your fee?',
          'dates' => 'When does it start?',
          _ => 'Anything else?',
        },
        topBanner: _editBar(),
        onBack: _leaveEdit,
        footer: [
          if (hasError)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Fix the red box to save', style: TextStyle(fontSize: 15, color: AppColors.error)),
            )
          else if (!changed)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Nothing changed yet', style: TextStyle(fontSize: 15, color: AppColors.muted)),
            ),
          PrimaryButton(label: changed ? 'Save and see agreement' : 'Back to agreement', onPressed: _saveEdit),
        ],
        children: [body],
      ),
    );
  }

  Widget _feeBody(PropertyOnboarding item) =>
        Column(
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
                  payError = null;
                  understood20 = false;
                  _fixPay();
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

  Widget _payBody() =>
        Column(
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
                          payError = null;
                        })
                      : null,
                ),
              ),
            if ((widget.part != null ? payError : feeError) != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text((widget.part != null ? payError : feeError)!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
          ],
        );

  Widget _datesBody() =>
        Column(
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

  Widget _notesBody() =>
        OnbTextField(
          label: 'Other things you agreed (optional)',
          hint: 'Example: no pets, owner pays maintenance',
          controller: notes,
          maxLines: 4,
        );

  Widget _checkBody(PropertyOnboarding item) =>
        OnbCard(
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

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEdit(context);
    final item = widget.item;
    final titles = ['What is your fee?', 'How does the owner pay you?', 'When does it start?', 'Anything else?', 'Check once'];
    final Widget body = switch (step) {
      0 => _feeBody(item),
      1 => _payBody(),
      2 => _datesBody(),
      3 => _notesBody(),
      _ => _checkBody(item),
    };
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

// ---------------------------------------------------------------------------
// Full agreement: the owner and the broker. Same look and steps as the rent
// agreement review: read it, edit it, send it for approval.
// ---------------------------------------------------------------------------

const _hlYellow = Color(0xFFFFE27A);
const _hlGreen = Color(0xFFBFEAD2);

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) { 1 => '${day}st', 2 => '${day}nd', 3 => '${day}rd', _ => '${day}th' };
}

String _prettyDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${_ordinal(d.day)} ${months[d.month - 1]} ${d.year}';
}

/// Which parts of the agreement changed since the first draft (green).
Set<String> _changedGroups(PropertyOnboarding item) {
  final groups = {for (final e in item.edits) e.group};
  for (final c in item.changes) {
    switch (c.clause) {
      case 'Your fee' || 'How owner pays your fee':
        groups.add('fee');
      case 'Start date' || 'How long':
        groups.add('dates');
      case 'Other notes':
        groups.add('notes');
    }
  }
  return groups;
}

/// "Send to these people?" Returns true when the broker says send.
Future<bool> confirmSendDraft(BuildContext context, PropertyOnboarding item) async {
  final many = item.hasManyOwners;
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              many ? 'Send to these ${item.ownerCount} people?' : 'Send to ${item.ownerFirstAt(0)}?',
              style: const TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading),
            ),
            const SizedBox(height: 6),
            const Text(
              'Each gets a link on WhatsApp or email. They can say yes, or ask for a change.',
              style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                for (var o = 0; o < item.ownerCount; o++)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          item.ownerNameAt(o).trim().isEmpty ? '?' : item.ownerNameAt(o).trim()[0].toUpperCase(),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(item.ownerFirstAt(o), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.heading)),
                      const Text('Owner', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Yes, send', onPressed: () => Navigator.pop(sheet, true)),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'No, go back', onPressed: () => Navigator.pop(sheet, false)),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Confirms, marks the draft as sent and shows "Agreement sent!".
Future<void> sendDraftWithConfirm(BuildContext context, PropertyOnboarding item) async {
  if (!await confirmSendDraft(context, item) || !context.mounted) return;
  await _store.update(item.id, (i) => i.copyWith(draftSent: true, draftSentAt: DateTime.now().millisecondsSinceEpoch));
  if (context.mounted) context.push('/broker/onboarding/${item.id}/sent');
}

/// The owner already has the draft. A change makes a new draft that they must
/// approve again. Returns true when the broker goes ahead.
Future<bool> confirmNewDraft(BuildContext context, PropertyOnboarding item, {required String yes}) {
  final who = item.hasManyOwners ? 'all ${item.ownerCount} owners' : item.ownerFirstAt(0);
  return onbConfirm(
    context,
    title: 'Everyone must say yes again',
    message: '${item.ownerAgreedFinal ? '${item.hasManyOwners ? 'The owners' : item.ownerFirstAt(0)} already said yes. ' : '$who already have the draft. '}'
        'If you change the agreement, $who get the new draft to approve.',
    yes: yes,
    no: 'Don\'t change',
  );
}

class OwnerAgreementScreen extends StatelessWidget {
  const OwnerAgreementScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => _AgreementReader(item: item),
  );
}

class _AgreementReader extends StatelessWidget {
  const _AgreementReader({required this.item});
  final PropertyOnboarding item;

  bool get _canEdit => item.phase == OnboardingPhase.preparing || item.phase == OnboardingPhase.review;

  @override
  Widget build(BuildContext context) {
    final changed = _changedGroups(item);
    final sendable = item.phase == OnboardingPhase.review && !item.draftSent && item.waitingChanges == 0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  ApprovedBackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/broker/onboarding/${item.id}')),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Your agreement', style: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
                  ),
                  if (item.draftNo > 0)
                    Text('Draft ${item.draftNo}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _legend(_hlYellow, 'Yellow = details you added'),
                  if (changed.isNotEmpty) _legend(_hlGreen, 'Green = just changed'),
                ],
              ),
            ),
            if (item.edits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showChanges(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${item.edits.length} ${item.edits.length == 1 ? 'change' : 'changes'}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.success),
                          ),
                        ),
                        const Text('See all', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                        const Icon(Icons.chevron_right, size: 20, color: AppColors.primaryDark),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Color(0x0F172231), blurRadius: 10, offset: Offset(0, 2))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                    child: _paper(changed),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  if (_canEdit) ...[
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => _showWhatToChange(context),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryDark,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: sendable
                        ? PrimaryButton(label: 'Send to ${item.ownersFirst}', onPressed: () => sendDraftWithConfirm(context, item))
                        : PrimaryButton(label: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go('/broker/onboarding/${item.id}')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
    ],
  );

  // ---- the paper ----

  Widget _paper(Set<String> changed) {
    const base = TextStyle(fontSize: 14.5, height: 24 / 14.5, color: Color(0xFF3A4658));
    const head = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.heading, letterSpacing: 0.4);
    final a = item.answers;
    final decided = a.feeType.isNotEmpty;
    final broker = _brokerName();
    // A value we have (yellow), a value that changed (green), or a gap.
    InlineSpan v(String text, {String? group, bool known = true}) {
      if (!known) {
        return const TextSpan(text: ' ........ ', style: TextStyle(backgroundColor: Color(0xFFEEF1F5), color: AppColors.muted));
      }
      final isChanged = group != null && changed.contains(group);
      return TextSpan(
        text: text,
        style: TextStyle(backgroundColor: isChanged ? _hlGreen : _hlYellow, color: AppColors.heading, fontWeight: FontWeight.w600),
      );
    }

    Widget para(List<InlineSpan> spans) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(style: base, children: spans)),
    );
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: head),
    );

    final feeClause = !decided
        ? <InlineSpan>[const TextSpan(text: '3. The fee: '), v('', known: false), const TextSpan(text: ' It will be written here once you tell us.')]
        : a.feeType == 'none'
            ? <InlineSpan>[const TextSpan(text: '3. '), v('The broker does not charge the owner any fee', group: 'fee'), const TextSpan(text: ' under this agreement.')]
            : a.feeType == 'later'
                ? <InlineSpan>[
                    const TextSpan(text: '3. '),
                    v('The fee is not fixed now', group: 'fee'),
                    const TextSpan(text: '. The broker and the owner agree it for every deal, in writing, before that deal starts.'),
                  ]
                : <InlineSpan>[
                    const TextSpan(text: '3. The owner will pay the broker a fee of '),
                    v(a.feeSummary(item.rent), group: 'fee'),
                    const TextSpan(text: '. '),
                    v(a.payWayText, group: 'fee'),
                    const TextSpan(text: '. The fee includes all taxes.'),
                  ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('PROPERTY MANAGEMENT AGREEMENT', textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.heading, letterSpacing: 0.6)),
          ),
        ),
        para([
          const TextSpan(text: 'This agreement is made on '),
          v(_prettyDate(DateTime.now().toIso8601String().substring(0, 10))),
          const TextSpan(text: '.'),
        ]),
        heading('BETWEEN'),
        para([
          v(item.ownersFull),
          const TextSpan(text: ', hereafter called the '),
          const TextSpan(text: '“OWNER”', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: item.hasManyOwners ? ' (all the owners together).' : '.'),
        ]),
        heading('AND'),
        para([
          v(broker),
          const TextSpan(text: ', hereafter called the '),
          const TextSpan(text: '“BROKER”', style: TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: '.'),
        ]),
        heading('THE PROPERTY'),
        para([
          v(item.address.trim().isEmpty ? '' : item.address, known: item.address.trim().isNotEmpty),
          if (item.address.trim().isEmpty) const TextSpan(text: ' (the address comes from the owner\'s documents)'),
          const TextSpan(text: '.'),
        ]),
        heading('NOW IT IS AGREED AS FOLLOWS'),
        para([
          const TextSpan(text: '1. The broker ('),
          v(broker),
          const TextSpan(text: ') finds and checks tenants, takes tenant calls and complaints, and coordinates small repairs and the move-in and move-out checks. The owner picks the tenant and signs the tenant\'s agreement in their own name.'),
        ]),
        para([const TextSpan(text: '2. The owner gives true documents, answers approval requests on time, pays the broker fee and the costs that are valid, and is responsible for any dispute about who owns the house.')]),
        para(feeClause),
        para([
          const TextSpan(text: '4. The tenant\'s rent of '),
          v('${onbMoney(item.rent)} every month'),
          const TextSpan(text: ' and deposit of '),
          v(onbMoney(item.deposit)),
          const TextSpan(text: ' are for the owner. The broker does not keep them unless the owner agrees in writing.'),
        ]),
        para([
          const TextSpan(text: '5. This agreement is for '),
          v('${a.months} months', group: 'dates'),
          if (a.startDate.isEmpty) ...[const TextSpan(text: ' from '), v('', known: false)] else ...[const TextSpan(text: ', from '), v(_prettyDate(a.startDate), group: 'dates')],
          const TextSpan(text: '. After that it ends, unless both sides renew in writing.'),
        ]),
        para([const TextSpan(text: '6. Both sides keep names, numbers, money and tenant details private. This continues for 3 years after the agreement ends.')]),
        para([const TextSpan(text: '7. Each side is responsible for its own mistakes. The broker\'s total responsibility is limited to the fees paid in the last 12 months. Neither side pays for indirect loss.')]),
        para([const TextSpan(text: '8. Either side can end the agreement by telling the other in writing. The notice time is set in the final draft.')]),
        if (a.notes.trim().isNotEmpty)
          para([const TextSpan(text: '9. Other things agreed: '), v(a.notes.trim(), group: 'notes')]),
        const SizedBox(height: 6),
        const Text(
          'Plain words for reading. Our team keeps the legal words correct in the final draft. Signing, stamp paper and payment come in the next stages.',
          style: TextStyle(fontSize: 13.5, height: 19 / 13.5, color: AppColors.muted),
        ),
      ],
    );
  }

  // ---- Edit: what to change? ----

  Future<void> _showWhatToChange(BuildContext context) async {
    final part = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What to change?', style: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 12),
              for (final (key, icon) in const [('fee', Icons.payments_outlined), ('dates', Icons.calendar_today_outlined), ('notes', Icons.edit_note_outlined)])
                OnbRow(
                  icon: icon,
                  tone: 'info',
                  title: AgreementAnswers.groupLabel(key),
                  subtitle: item.answers.feeType.isEmpty && key == 'fee' ? 'Not decided yet' : item.answers.groupText(key, item.rent),
                  onTap: () => Navigator.pop(sheet, key),
                ),
              const SizedBox(height: 4),
              const Text(
                'Rent, deposit and owners come from the owner\'s documents. To change them, go back to the house page.',
                style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
    if (part != null && context.mounted) context.push('/broker/onboarding/${item.id}/edit?part=$part');
  }

  // ---- all the changes, with Undo ----

  Future<void> _showChanges(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheet) => ListenableBuilder(
        listenable: _store,
        builder: (sheet, _) {
          final now = _store.byId(item.id) ?? item;
          if (now.edits.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheet.mounted && Navigator.canPop(sheet)) Navigator.pop(sheet);
            });
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${now.edits.length} ${now.edits.length == 1 ? 'change' : 'changes'}', style: const TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
                  const SizedBox(height: 12),
                  for (final e in now.edits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OnbCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(AgreementAnswers.groupLabel(e.group), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
                                  const SizedBox(height: 4),
                                  Text(e.before.groupText(e.group, now.rent), style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                                  const SizedBox(height: 2),
                                  Text(now.answers.groupText(e.group, now.rent), style: const TextStyle(fontSize: 15, height: 20 / 15, color: AppColors.body)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                if (now.phase == OnboardingPhase.review && now.draftSent && !await confirmNewDraft(sheet, now, yes: 'Yes, undo and resend')) return;
                                await _store.undoAgreementPart(now.id, e.group);
                              },
                              child: const Text('Undo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Agreement sent!" and what happens next.
class AgreementSentScreen extends StatelessWidget {
  const AgreementSentScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) {
      final first = item.ownersFirst;
      final steps = <(String, String, String)>[
        ('Sent', item.hasManyOwners ? 'To all ${item.ownerCount} owners' : 'To $first', 'ok'),
        ('They read it', 'On WhatsApp or email', 'info'),
        ('They say yes', item.hasManyOwners ? 'All ${item.ownerCount} must agree' : '$first must agree', 'mute'),
        ('Everyone signs', 'Then the agreement is ready', 'mute'),
      ];
      return OnbPage(
        title: 'Agreement sent!',
        subtitle: 'We will tell you when $first replies.',
        showBack: false,
        footer: [
          PrimaryButton(label: 'Go to this house', onPressed: () => context.go('/broker/onboarding/${item.id}')),
          const SizedBox(height: 10),
          OnbSecondaryButton(label: 'See the agreement', onPressed: () => context.pop()),
        ],
        children: [
          const Center(child: Icon(Icons.check_circle, size: 72, color: AppColors.success)),
          const SizedBox(height: 24),
          const Text('What happens next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(height: 8),
          OnbCard(
            child: Column(
              children: [
                for (final (title, sub, kind) in steps)
                  OnbRow(
                    icon: kind == 'ok' ? Icons.check_circle : Icons.radio_button_unchecked,
                    tone: kind,
                    title: title,
                    subtitle: sub,
                    chevron: false,
                    trailing: kind == 'info' ? const OnbPill('Now', 'info') : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sending on WhatsApp or email is not connected yet. On the house page, use the test buttons to pretend the owner replied.',
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
