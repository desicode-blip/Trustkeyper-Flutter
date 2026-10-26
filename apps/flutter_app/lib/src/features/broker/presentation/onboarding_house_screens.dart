import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/property_onboarding.dart';
import 'onboarding_widgets.dart';

/// Rebuilds when the request changes. Shows a plain message if it was removed.
class OnbItemView extends StatefulWidget {
  const OnbItemView({required this.id, required this.builder, super.key});
  final String id;
  final Widget Function(BuildContext context, PropertyOnboarding item) builder;

  @override
  State<OnbItemView> createState() => _OnbItemViewState();
}

class _OnbItemViewState extends State<OnbItemView> {
  final store = PropertyOnboardingStore.instance;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final item = store.byId(widget.id);
      if (item == null) {
        return OnbPage(
          title: 'Not found',
          showBack: false,
          footer: [PrimaryButton(label: 'Go to Home', onPressed: () => context.go('/broker'))],
          children: [
            OnbCentered(
              icon: Icons.info_outline,
              title: store.loaded ? 'This request is gone' : 'Opening…',
              message: store.loaded ? 'It was stopped or deleted.' : 'One moment.',
              loading: !store.loaded,
            ),
          ],
        );
      }
      return widget.builder(context, item);
    },
  );
}

String _ago(int millis) {
  final diff = DateTime.now().millisecondsSinceEpoch - millis;
  final minutes = diff ~/ 60000;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'} ago';
  final days = hours ~/ 24;
  return '$days day${days == 1 ? '' : 's'} ago';
}

String _firstName(PropertyOnboarding item) => item.ownerName.split(' ').first;

/// Minutes left before the broker may ask the owner again (2 hours apart).
int _cooldownMinutes(PropertyOnboarding item) {
  final left = const Duration(hours: 2).inMinutes -
      ((DateTime.now().millisecondsSinceEpoch - item.lastAskedAt) ~/ 60000);
  return left > 0 ? left : 0;
}

String _wait(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '$minutes min';

Future<void> _callOwner(PropertyOnboarding item) async {
  if (item.channel == 'whatsapp') {
    await launchUrl(Uri.parse('tel:+91${item.contact}'));
  }
}

/// The house page: four stages, and what to do now.
class PropertySetupScreen extends StatelessWidget {
  const PropertySetupScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) => _OnboardingBody(item: item),
  );
}

class _OnboardingBody extends StatelessWidget {
  const _OnboardingBody({required this.item});
  final PropertyOnboarding item;

  PropertyOnboardingStore get store => PropertyOnboardingStore.instance;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      OnbCard(
        color: AppColors.surfaceMuted,
        child: OnbRow(
          icon: Icons.home_outlined,
          title: item.houseName,
          subtitle: 'Owner · ${item.ownerName}',
          chevron: false,
        ),
      ),
      const SizedBox(height: 18),
      OnbStageBar(item.stage),
      const SizedBox(height: 18),
      ..._phaseContent(context),
      const SizedBox(height: 24),
      ..._testPanel(context),
    ];
    return OnbPage(
      title: item.phase == OnboardingPhase.ready ? 'House ready' : 'Setting up',
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/broker');
        }
      },
      footer: _footer(context),
      children: children,
    );
  }

  // ---- what the broker sees in each phase ----

  List<Widget> _phaseContent(BuildContext context) => switch (item.phase) {
    OnboardingPhase.papers => _papers(context),
    OnboardingPhase.questions => _questions(context),
    OnboardingPhase.preparing => _preparing(),
    OnboardingPhase.review => _review(context),
    OnboardingPhase.printing || OnboardingPhase.signing => _signing(context),
    _ => _ready(context),
  };

  List<Widget> _papers(BuildContext context) {
    final silentDays = (DateTime.now().millisecondsSinceEpoch - item.lastAskedAt) ~/ const Duration(days: 1).inMilliseconds;
    final allWaiting = item.papers.every((p) => p.status == PaperStatus.waiting);
    return [
      if (item.allPapersDone)
        const OnbBanner('All papers are checked and approved.', kind: 'ok', icon: Icons.check_circle_outline)
      else if (item.needYouCount > 0)
        OnbBanner(
          item.needYouCount == 1 ? '1 paper needs you.' : '${item.needYouCount} papers need you.',
          kind: 'need',
          icon: Icons.error_outline,
        )
      else if (allWaiting && silentDays >= 3)
        OnbBanner('${_firstName(item)} has not replied for $silentDays days.', kind: 'wait', icon: Icons.schedule)
      else
        OnbBanner('Asked ${_ago(item.lastAskedAt)}. Waiting for ${_firstName(item)}.', kind: 'wait', icon: Icons.schedule),
      const SizedBox(height: 14),
      OnbCard(
        child: Column(
          children: [
            for (final paper in item.papers)
              OnbRow(
                icon: paperIcon(paper.key),
                tone: paperStatusKind(paper.status),
                title: PaperKeys.title(paper.key),
                subtitle: paper.value.isNotEmpty ? paper.value : PaperKeys.hint(paper.key),
                trailing: OnbPill(paperStatusLabel(paper.status), paperStatusKind(paper.status)),
                onTap: () => context.push('/broker/onboarding/${item.id}/paper/${paper.key}'),
              ),
          ],
        ),
      ),
      if (!item.allPapersDone) ...[
        const SizedBox(height: 12),
        OnbRow(
          icon: Icons.help_outline,
          tone: 'mute',
          title: '${_firstName(item)} not replying?',
          subtitle: 'Remind, call or change the contact',
          onTap: () => _notReplying(context),
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            final stop = await onbConfirm(
              context,
              title: 'Stop asking for papers?',
              message: '${_firstName(item)} will not get more messages. Papers already received are deleted from this request.',
              yes: 'Stop and delete request',
              no: 'Keep going',
              danger: true,
            );
            if (!stop || !context.mounted) return;
            await store.remove(item.id);
            if (context.mounted) context.go('/broker');
          },
          child: const Text('Stop this request', style: TextStyle(color: AppColors.error, fontSize: 16)),
        ),
      ),
    ];
  }

  Future<void> _notReplying(BuildContext context) async {
    await showModalBottomSheet<void>(
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
              Text('${_firstName(item)} has not replied', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 6),
              const Text('Most owners reply the same day. Try one of these.', style: TextStyle(fontSize: 16, color: AppColors.muted)),
              const SizedBox(height: 12),
              OnbRow(
                icon: Icons.send_outlined,
                title: 'Send a reminder',
                subtitle: _cooldownMinutes(item) > 0 ? 'You can ask again in ${_wait(_cooldownMinutes(item))}' : null,
                onTap: _cooldownMinutes(item) > 0
                    ? null
                    : () async {
                        Navigator.pop(sheet);
                        await store.update(item.id, (i) => i.copyWith(lastAskedAt: DateTime.now().millisecondsSinceEpoch));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reminder sent to ${_firstName(item)}.')));
                        }
                      },
              ),
              OnbRow(
                icon: Icons.call_outlined,
                title: 'Call ${_firstName(item)}',
                subtitle: item.channel == 'whatsapp' ? '+91 ${item.contact}' : 'We only have the email',
                onTap: item.channel == 'whatsapp' ? () => _callOwner(item) : null,
              ),
              OnbRow(
                icon: Icons.edit_outlined,
                title: 'Change owner contact',
                subtitle: item.contactText,
                onTap: () async {
                  Navigator.pop(sheet);
                  await _changeContact(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeContact(BuildContext context) async {
    final controller = TextEditingController(text: item.contact);
    String? error;
    final saved = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text(item.channel == 'email' ? 'New email' : 'New phone number'),
          content: TextField(
            controller: controller,
            keyboardType: item.channel == 'email' ? TextInputType.emailAddress : TextInputType.phone,
            decoration: InputDecoration(errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                final ok = item.channel == 'email'
                    ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(value)
                    : value.replaceAll(RegExp(r'\D'), '').length == 10;
                if (!ok) {
                  setState(() => error = item.channel == 'email' ? 'This email looks wrong' : 'Type the 10 digit number');
                  return;
                }
                Navigator.pop(dialog, item.channel == 'email' ? value : value.replaceAll(RegExp(r'\D'), ''));
              },
              child: const Text('Send again'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await store.update(item.id, (i) => i.copyWith(contact: saved, lastAskedAt: DateTime.now().millisecondsSinceEpoch));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We sent the request to the new contact.')));
    }
  }

  List<Widget> _questions(BuildContext context) => [
    const OnbBanner('Papers are ready. Now tell us what you agreed with the owner.', kind: 'ok', icon: Icons.check_circle_outline),
    const SizedBox(height: 14),
    OnbCard(
      child: Column(
        children: [
          for (final paper in item.papers)
            OnbRow(
              icon: paperIcon(paper.key),
              tone: 'ok',
              title: PaperKeys.title(paper.key),
              subtitle: paper.value.isNotEmpty ? paper.value : 'Approved',
              chevron: false,
              trailing: const OnbPill('Approved', 'ok'),
            ),
        ],
      ),
    ),
  ];

  List<Widget> _preparing() => [
    const OnbCentered(
      icon: Icons.description_outlined,
      title: 'Making your agreement',
      message: 'We are writing it from the papers and what you told us. It will go to the owner soon.',
      loading: true,
    ),
    const SizedBox(height: 16),
    const OnbBanner('You can close the app. We will tell you when it is ready.', icon: Icons.notifications_none),
  ];

  List<Widget> _review(BuildContext context) {
    final changesWaiting = item.waitingChanges;
    final ownerFirst = _firstName(item);
    return [
      if (changesWaiting > 0)
        OnbBanner('$ownerFirst asked ${changesWaiting == 1 ? 'a change' : '$changesWaiting changes'}. Your turn.', kind: 'wait', icon: Icons.chat_bubble_outline)
      else if (!item.draftSent)
        OnbBanner('Draft ${item.draftNo} is ready. Read the key points, then send to $ownerFirst.', kind: 'info', icon: Icons.visibility_outlined)
      else if (item.ownerAgreedFinal)
        OnbBanner('$ownerFirst agrees with everything.', kind: 'ok', icon: Icons.check_circle_outline)
      else
        OnbBanner('Sent ${_ago(item.draftSentAt)}. Waiting for $ownerFirst.', kind: 'wait', icon: Icons.schedule),
      const SizedBox(height: 14),
      OnbCard(
        child: Column(
          children: [
            OnbRow(
              icon: Icons.description_outlined,
              title: 'Draft ${item.draftNo}',
              subtitle: 'Read key points in simple words',
              onTap: () => context.push('/broker/onboarding/${item.id}/draft'),
            ),
            OnbRow(
              icon: Icons.compare_arrows,
              tone: changesWaiting > 0 ? 'wait' : 'info',
              title: 'Changes',
              subtitle: item.changes.isEmpty ? 'None yet' : '${item.changes.length} asked',
              trailing: changesWaiting > 0 ? OnbPill('$changesWaiting for you', 'wait') : null,
              onTap: () => context.push('/broker/onboarding/${item.id}/changes'),
            ),
            OnbRow(
              icon: Icons.history,
              title: 'Versions',
              subtitle: '${item.versions.length} saved',
              onTap: () => context.push('/broker/onboarding/${item.id}/versions'),
            ),
          ],
        ),
      ),
      if (item.draftSent) ...[
        const SizedBox(height: 14),
        OnbCard(
          child: Column(
            children: [
              OnbRow(icon: Icons.send_outlined, tone: 'ok', title: 'Sent', subtitle: _ago(item.draftSentAt), chevron: false),
              OnbRow(icon: Icons.visibility_outlined, tone: item.changes.isNotEmpty || item.ownerAgreedFinal ? 'ok' : 'mute', title: 'Opened', subtitle: item.changes.isNotEmpty || item.ownerAgreedFinal ? 'Yes' : 'Not yet', chevron: false),
              OnbRow(icon: Icons.check, tone: item.ownerAgreedFinal ? 'ok' : 'mute', title: 'Answer', subtitle: item.ownerAgreedFinal ? '$ownerFirst agreed' : 'Waiting', chevron: false),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            final cancel = await onbConfirm(
              context,
              title: 'Cancel this agreement?',
              message: '${_firstName(item)} is told. The house stays in your app. You can make a new one.',
              yes: 'Yes, cancel',
              no: 'Keep it',
              danger: true,
            );
            if (!cancel) return;
            await store.update(item.id, (i) => PropertyOnboarding.fromJson({...i.toJson(), 'phase': OnboardingPhase.questions, 'draftNo': 0, 'draftSent': false, 'ownerAgreedFinal': false, 'changes': <Object>[], 'versions': <Object>[]}));
          },
          child: const Text('Cancel agreement', style: TextStyle(color: AppColors.error, fontSize: 16)),
        ),
      ),
    ];
  }

  List<Widget> _signing(BuildContext context) {
    final first = _firstName(item);
    String tone(int step) => item.printStep > step ? 'ok' : item.printStep == step ? 'info' : 'mute';
    String label(int step) => item.printStep > step ? 'Done' : item.printStep == step ? 'Now' : 'Later';
    return [
      if (item.phase == OnboardingPhase.printing)
        const OnbBanner('The final draft is locked. Our team is getting it ready for signing.', kind: 'info', icon: Icons.lock_outline)
      else if (!item.brokerSigned)
        OnbBanner('Everyone signs on their phone with a code. $first ${item.ownerSigned ? 'has signed.' : 'has not signed yet.'}', kind: 'wait', icon: Icons.draw_outlined)
      else
        OnbBanner('You signed. Waiting for $first.', kind: 'wait', icon: Icons.schedule),
      const SizedBox(height: 14),
      OnbCard(
        child: Column(
          children: [
            OnbRow(icon: Icons.approval_outlined, tone: tone(0), title: 'Stamp paper', subtitle: item.printStep > 0 ? 'Done' : 'Our team is buying it', chevron: false, trailing: OnbPill(label(0), tone(0))),
            OnbRow(icon: Icons.print_outlined, tone: tone(1), title: 'Printing', subtitle: item.printStep > 1 ? 'Done' : 'Printed on stamp paper', chevron: false, trailing: OnbPill(label(1), tone(1))),
            OnbRow(icon: Icons.draw_outlined, tone: item.phase == OnboardingPhase.signing ? 'info' : 'mute', title: 'Sign online', subtitle: 'You and $first', chevron: false, trailing: OnbPill(item.phase == OnboardingPhase.signing ? 'Now' : 'Later', item.phase == OnboardingPhase.signing ? 'info' : 'mute')),
          ],
        ),
      ),
      if (item.phase == OnboardingPhase.signing) ...[
        const SizedBox(height: 14),
        OnbCard(
          child: Column(
            children: [
              OnbRow(icon: Icons.check, tone: item.brokerSigned ? 'ok' : 'wait', title: 'You', subtitle: item.brokerSigned ? 'Signed' : 'Your turn', chevron: false, trailing: OnbPill(item.brokerSigned ? 'Signed' : 'Waiting', item.brokerSigned ? 'ok' : 'wait')),
              OnbRow(icon: Icons.check, tone: item.ownerSigned ? 'ok' : 'wait', title: item.ownerName, subtitle: item.ownerSigned ? 'Signed' : 'Owner', chevron: false, trailing: OnbPill(item.ownerSigned ? 'Signed' : 'Waiting', item.ownerSigned ? 'ok' : 'wait')),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _ready(BuildContext context) => [
    OnbCentered(
      icon: Icons.home_outlined,
      kind: 'ok',
      title: '${item.houseName} is ready',
      message: item.agreementSkipped
          ? 'You skipped the agreement. You can make it later.'
          : 'Papers are checked and the agreement is signed. Now find a tenant.',
    ),
    const SizedBox(height: 20),
    OnbCard(
      child: Column(
        children: [
          OnbKeyValue('Owner', item.ownerName),
          OnbKeyValue('Rent', onbMoney(item.rent)),
          OnbKeyValue('Deposit', onbMoney(item.deposit)),
          OnbKeyValue('Agreement', item.agreementSkipped ? 'Skipped' : 'Signed', last: true),
        ],
      ),
    ),
  ];

  // ---- main button at the bottom ----

  List<Widget> _footer(BuildContext context) {
    switch (item.phase) {
      case OnboardingPhase.papers:
        if (item.allPapersDone) {
          return [PrimaryButton(label: 'Continue', onPressed: () => store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.questions)))];
        }
        return const [];
      case OnboardingPhase.questions:
        return [
          PrimaryButton(label: 'Tell us what you agreed', onPressed: () => context.push('/broker/onboarding/${item.id}/questions')),
          const SizedBox(height: 10),
          OnbSecondaryButton(
            label: 'Skip agreement',
            onPressed: () async {
              final skip = await onbConfirm(
                context,
                title: 'Skip the agreement?',
                message: 'You can still use this house. The owner will not have a signed agreement with you. You can make it later. Only you can skip, the owner cannot.',
                yes: 'Skip for now',
                no: 'No, make it',
              );
              if (!skip) return;
              await store.update(item.id, (i) => i.copyWith(agreementSkipped: true, phase: OnboardingPhase.ready));
            },
          ),
        ];
      case OnboardingPhase.review:
        if (item.waitingChanges > 0) {
          return [PrimaryButton(label: 'Answer ${_firstName(item)}', onPressed: () => context.push('/broker/onboarding/${item.id}/changes'))];
        }
        if (!item.draftSent) {
          return [
            PrimaryButton(
              label: 'Send to ${_firstName(item)}',
              onPressed: () => store.update(item.id, (i) => i.copyWith(draftSent: true, draftSentAt: DateTime.now().millisecondsSinceEpoch)),
            ),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'Read key points', onPressed: () => context.push('/broker/onboarding/${item.id}/draft')),
          ];
        }
        if (item.ownerAgreedFinal) {
          return [
            PrimaryButton(
              label: 'Lock and continue',
              onPressed: () async {
                final lock = await onbConfirm(
                  context,
                  title: 'Lock the final draft?',
                  message: '${_firstName(item)} said yes. After you continue, nobody can change it.',
                  yes: 'Lock and continue',
                  no: 'Not yet',
                );
                if (!lock) return;
                await store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.printing, printStep: 0));
              },
            ),
          ];
        }
        return [
          OnbSecondaryButton(
            label: 'Call ${_firstName(item)}',
            onPressed: item.channel == 'whatsapp' ? () => _callOwner(item) : null,
          ),
        ];
      case OnboardingPhase.signing:
        if (!item.brokerSigned) {
          return [PrimaryButton(label: 'Sign now', onPressed: () => context.push('/broker/onboarding/${item.id}/sign'))];
        }
        return const [];
      case OnboardingPhase.ready:
        return [
          if (item.agreementSkipped) ...[
            PrimaryButton(
              label: 'Make the agreement now',
              onPressed: () => store.update(item.id, (i) => i.copyWith(agreementSkipped: false, phase: OnboardingPhase.questions)),
            ),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'Make rent agreement', onPressed: () => context.push('/broker/start')),
          ] else
            PrimaryButton(label: 'Make rent agreement', onPressed: () => context.push('/broker/start')),
        ];
      default:
        return const [];
    }
  }

  // ---- test panel: pretend the owner or our team did the next thing ----

  List<Widget> _testPanel(BuildContext context) {
    final buttons = <(String, Future<void> Function())>[];
    switch (item.phase) {
      case OnboardingPhase.papers:
        if (item.papers.every((p) => p.status == PaperStatus.waiting)) {
          buttons.add(('Owner sends some papers', () => store.testOwnerSendsPapers(item.id)));
        }
        if (!item.allPapersDone) buttons.add(('Fix everything, all approved', () => store.testFixAllPapers(item.id)));
      case OnboardingPhase.preparing:
        buttons.add(('Agreement is ready (Draft 1)', () => store.testDraftReady(item.id)));
      case OnboardingPhase.review:
        if (item.draftSent && !item.ownerAgreedFinal) {
          buttons.add(('Owner asks a change', () => store.testOwnerAsksChange(item.id)));
          if (item.waitingChanges == 0) buttons.add(('Owner says yes to everything', () => store.testOwnerAgrees(item.id)));
        }
      case OnboardingPhase.printing:
        buttons.add(('Our team: next step', () => store.testNextPrintStep(item.id)));
      case OnboardingPhase.signing:
        if (!item.ownerSigned) buttons.add(('Owner signs', () => store.testOwnerSigns(item.id)));
      default:
        break;
    }
    if (buttons.isEmpty) return const [];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TEST ONLY', style: TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 4),
            const Text('Email, WhatsApp, reading papers and e-sign are not connected yet. Use these to pretend the next step happened.', style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
            const SizedBox(height: 10),
            for (final (label, action) in buttons) ...[
              OnbSecondaryButton(label: label, onPressed: () => action()),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ];
  }
}

/// One paper: what we read, why it was not approved, and what the broker can do.
class PaperDetailScreen extends StatelessWidget {
  const PaperDetailScreen({required this.id, required this.paperKey, super.key});
  final String id;
  final String paperKey;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) {
      final paper = item.paper(paperKey);
      final store = PropertyOnboardingStore.instance;
      final first = _firstName(item);
      final footer = <Widget>[];
      final body = <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: OnbPill(
            switch (paper.status) {
              PaperStatus.approved => 'Approved by TrustKeyper',
              PaperStatus.notClear => 'Not approved',
              PaperStatus.needsYou => 'Please check',
              PaperStatus.checking => 'Checking now',
              PaperStatus.notNeeded => 'Not needed',
              PaperStatus.waiting => 'Waiting for $first',
            },
            paperStatusKind(paper.status),
            icon: paper.status == PaperStatus.approved ? Icons.verified_user_outlined : null,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(paperIcon(paperKey), size: 36, color: AppColors.muted),
              const SizedBox(height: 6),
              Text(
                paper.status == PaperStatus.waiting ? 'Nothing received yet' : 'Photo from $first',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ];
      switch (paper.status) {
        case PaperStatus.approved:
          body.addAll([
            OnbCard(child: Column(children: [OnbKeyValue(PaperKeys.title(paperKey), paper.value.isEmpty ? 'Received' : paper.value, last: true)])),
            const SizedBox(height: 14),
            const OnbBanner('Clear and checked. Nothing to do.', kind: 'ok', icon: Icons.check_circle_outline),
          ]);
          footer.add(PrimaryButton(label: 'Back to papers', onPressed: () => context.pop()));
        case PaperStatus.checking:
          body.add(const OnbBanner('We are reading it. Takes about 1 minute. You can leave this screen.', kind: 'info', icon: Icons.schedule));
          footer.add(PrimaryButton(label: 'Back to papers', onPressed: () => context.pop()));
        case PaperStatus.notNeeded:
          body.add(const OnbBanner('The owner says this is not needed.', icon: Icons.info_outline));
          footer.add(PrimaryButton(label: 'Back to papers', onPressed: () => context.pop()));
        case PaperStatus.needsYou:
          body.addAll([
            OnbCard(child: Text(paper.reason, style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body))),
            const SizedBox(height: 12),
            const OnbBanner('Is this the same person?', kind: 'wait', icon: Icons.help_outline),
          ]);
          footer.addAll([
            PrimaryButton(label: 'Yes, same person', onPressed: () async {
              await store.update(id, (i) => i.withPaper(paperKey, PaperStatus.approved, value: paper.value));
              if (context.mounted) context.pop();
            }),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'No, ask again', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey')),
          ]);
        case PaperStatus.notClear:
          body.addAll([
            OnbBanner('Why: ${paper.reason}', kind: 'need', icon: Icons.error_outline),
            const SizedBox(height: 14),
            const Text('What do you want to do?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.heading)),
          ]);
          footer.addAll([
            PrimaryButton(label: 'Ask $first again', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OnbSecondaryButton(label: 'I add it', onPressed: () => _addMyself(context, item, paper))),
                const SizedBox(width: 10),
                Expanded(child: OnbSecondaryButton(label: 'Call owner', onPressed: item.channel == 'whatsapp' ? () => _callOwner(item) : null)),
              ],
            ),
          ]);
        case PaperStatus.waiting:
          body.add(OnbBanner('Asked ${_ago(item.lastAskedAt)}. Waiting for $first.', kind: 'wait', icon: Icons.schedule));
          footer.addAll([
            PrimaryButton(label: 'Remind $first', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OnbSecondaryButton(label: 'I add it', onPressed: () => _addMyself(context, item, paper))),
                const SizedBox(width: 10),
                if (paperKey == PaperKeys.tenantAgreement)
                  Expanded(
                    child: OnbSecondaryButton(
                      label: 'No tenant',
                      onPressed: () async {
                        await store.update(id, (i) => i.withPaper(paperKey, PaperStatus.notNeeded));
                        if (context.mounted) context.pop();
                      },
                    ),
                  )
                else
                  Expanded(child: OnbSecondaryButton(label: 'Call owner', onPressed: item.channel == 'whatsapp' ? () => _callOwner(item) : null)),
              ],
            ),
          ]);
      }
      return OnbPage(
        title: PaperKeys.title(paperKey),
        subtitle: item.ownerName,
        footer: footer,
        children: body,
      );
    },
  );

  Future<void> _addMyself(BuildContext context, PropertyOnboarding item, OnboardingPaper paper) async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.of(sheet).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PaperKeys.title(paper.key), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
            const SizedBox(height: 6),
            Text('Type what is on the paper. ${PaperKeys.hint(paper.key)}.', style: const TextStyle(fontSize: 16, color: AppColors.muted)),
            const SizedBox(height: 14),
            OnbTextField(label: 'Details', controller: controller, maxLines: 2),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Save', onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(sheet, text);
            }),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    await PropertyOnboardingStore.instance.update(item.id, (i) => i.withPaper(paper.key, PaperStatus.approved, value: value));
    if (context.mounted) context.pop();
  }
}

/// Ask the owner again, with the reason in simple words.
class AskAgainScreen extends StatefulWidget {
  const AskAgainScreen({required this.id, required this.paperKey, super.key});
  final String id;
  final String paperKey;

  @override
  State<AskAgainScreen> createState() => _AskAgainScreenState();
}

class _AskAgainScreenState extends State<AskAgainScreen> {
  static const _reasons = {
    'Photo is blurry': 'the photo is blurry. Please send a clear photo. Keep all 4 corners inside.',
    'Wrong paper': 'this is not the paper we need. Please send the right one.',
    'Pages missing': 'some pages are missing. Please send all pages.',
    'Name is different': 'the name is different from the other papers. Please send the right paper.',
  };
  String _reason = 'Photo is blurry';

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      final minutes = _cooldownMinutes(item);
      final first = _firstName(item);
      final title = PaperKeys.title(widget.paperKey);
      return OnbPage(
        title: 'Ask $first again',
        subtitle: 'We will message $first.',
        footer: [
          if (minutes > 0) ...[
            OnbBanner('We asked a little while ago. You can ask again in ${_wait(minutes)}.', kind: 'wait', icon: Icons.schedule),
            const SizedBox(height: 10),
          ],
          PrimaryButton(
            label: minutes > 0 ? 'Ask again in ${_wait(minutes)}' : 'Send message',
            onPressed: minutes > 0
                ? null
                : () async {
                    final reason = _reason;
                    await PropertyOnboardingStore.instance.update(
                      item.id,
                      (i) => i.withPaper(widget.paperKey, PaperStatus.waiting).copyWith(lastAskedAt: DateTime.now().millisecondsSinceEpoch),
                    );
                    if (!context.mounted) return;
                    context.pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message sent to $first ($reason).')));
                  },
          ),
        ],
        children: [
          const Text('Why are we asking again?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.heading)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in _reasons.keys)
                ChoiceChip(
                  label: Text(reason),
                  selected: _reason == reason,
                  onSelected: (_) => setState(() => _reason = reason),
                  showCheckmark: false,
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(fontSize: 15, color: _reason == reason ? AppColors.primaryDark : AppColors.body),
                  side: BorderSide(color: _reason == reason ? AppColors.primary : AppColors.border),
                  shape: const StadiumBorder(),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Message $first will get', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                const SizedBox(height: 6),
                Text('The $title: ${_reasons[_reason]}', style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body)),
              ],
            ),
          ),
        ],
      );
    },
  );
}
