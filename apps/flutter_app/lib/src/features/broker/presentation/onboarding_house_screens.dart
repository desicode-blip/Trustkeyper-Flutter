import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/property_onboarding.dart';
import 'onboarding_agreement_screens.dart' show sendDraftWithConfirm;
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

/// First names of all owners, for lines about the whole house.
String _firstName(PropertyOnboarding item) => item.ownersFirst;

/// Minutes left before the broker may ask the owner again (2 hours apart).
int _cooldownMinutes(PropertyOnboarding item, [int owner = 0]) {
  final left = const Duration(hours: 2).inMinutes -
      ((DateTime.now().millisecondsSinceEpoch - item.ownerAskedAt(owner)) ~/ 60000);
  return left > 0 ? left : 0;
}

String _wait(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '$minutes min';

Future<void> _callOwner(PropertyOnboarding item, [int owner = 0]) async {
  if (item.ownerChannelAt(owner) == 'whatsapp') {
    await launchUrl(Uri.parse('tel:+91${item.ownerContactAt(owner)}'));
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
          subtitle: item.hasManyOwners ? 'Owners · ${item.ownersFull}' : 'Owner · ${item.ownerName}',
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
    if (item.hasManyOwners) {
      return [
        _ManyOwnersPapers(
          item: item,
          onNotReplying: (owner) => _notReplying(context, owner),
          onAddOwner: () => _addOwner(context),
          onRemoveOwner: (owner) => _removeOwner(context, owner),
        ),
        ..._stopButton(context),
      ];
    }
    final silentDays = (DateTime.now().millisecondsSinceEpoch - item.lastAskedAt) ~/ const Duration(days: 1).inMilliseconds;
    final allWaiting = item.papers.every((p) => p.status == PaperStatus.waiting || p.status == PaperStatus.approved);
    return [
      if (item.allPapersDone)
        const OnbBanner('All documents are checked and approved.', kind: 'ok', icon: Icons.check_circle_outline)
      else if (item.needYouCount > 0)
        OnbBanner(
          item.needYouCount == 1 ? '1 document needs you.' : '${item.needYouCount} documents need you.',
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
      const SizedBox(height: 4),
      TextButton.icon(
        onPressed: () => _addOwner(context),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
        label: const Text('Add another owner', style: TextStyle(fontSize: 16)),
      ),
      ..._stopButton(context),
    ];
  }

  List<Widget> _stopButton(BuildContext context) => [
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            final stop = await onbConfirm(
              context,
              title: 'Stop asking for documents?',
              message: '${_firstName(item)} will not get more messages. Documents already received are deleted from this request.',
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

  Future<void> _addOwner(BuildContext context) async {
    final owner = await showModalBottomSheet<CoOwner>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => _AddOwnerSheet(item: item),
    );
    if (owner == null) return;
    await store.addOwner(item.id, owner);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('We asked ${owner.firstName} for the documents.')));
    }
  }

  Future<void> _removeOwner(BuildContext context, int owner) async {
    final name = item.ownerFirstAt(owner);
    final remove = await onbConfirm(
      context,
      title: 'Remove $name?',
      message: '$name is not an owner of this house any more. Documents $name sent are deleted from this request. $name will not get more messages.',
      yes: 'Remove $name',
      no: 'Keep $name',
      danger: true,
    );
    if (!remove) return;
    await store.removeOwner(item.id, owner);
  }

  Future<void> _notReplying(BuildContext context, [int owner = 0]) async {
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
              Text('${item.ownerFirstAt(owner)} has not replied', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 6),
              const Text('Most owners reply the same day. Try one of these.', style: TextStyle(fontSize: 16, color: AppColors.muted)),
              const SizedBox(height: 12),
              OnbRow(
                icon: Icons.send_outlined,
                title: 'Send a reminder',
                subtitle: _cooldownMinutes(item, owner) > 0 ? 'You can ask again in ${_wait(_cooldownMinutes(item, owner))}' : null,
                onTap: _cooldownMinutes(item, owner) > 0
                    ? null
                    : () async {
                        Navigator.pop(sheet);
                        await store.update(item.id, (i) => i.withOwnerAsked(owner, DateTime.now().millisecondsSinceEpoch));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reminder sent to ${item.ownerFirstAt(owner)}.')));
                        }
                      },
              ),
              OnbRow(
                icon: Icons.call_outlined,
                title: 'Call ${item.ownerFirstAt(owner)}',
                subtitle: item.ownerChannelAt(owner) == 'whatsapp' ? '+91 ${item.ownerContactAt(owner)}' : 'We only have the email',
                onTap: item.ownerChannelAt(owner) == 'whatsapp' ? () => _callOwner(item, owner) : null,
              ),
              OnbRow(
                icon: Icons.edit_outlined,
                title: 'Change owner contact',
                subtitle: item.ownerContactTextAt(owner),
                onTap: () async {
                  Navigator.pop(sheet);
                  await _changeContact(context, owner);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeContact(BuildContext context, [int owner = 0]) async {
    final controller = TextEditingController(text: item.ownerContactAt(owner));
    String? error;
    final saved = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text(item.ownerChannelAt(owner) == 'email' ? 'New email' : 'New phone number'),
          content: TextField(
            controller: controller,
            keyboardType: item.ownerChannelAt(owner) == 'email' ? TextInputType.emailAddress : TextInputType.phone,
            decoration: InputDecoration(errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                final ok = item.ownerChannelAt(owner) == 'email'
                    ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(value)
                    : value.replaceAll(RegExp(r'\D'), '').length == 10;
                final clash = [
                  for (var i = 0; i < item.ownerCount; i++)
                    if (i != owner && item.ownerChannelAt(i) == item.ownerChannelAt(owner)) item.ownerContactAt(i).toLowerCase(),
                ].contains((item.ownerChannelAt(owner) == 'email' ? value : value.replaceAll(RegExp(r'\D'), '')).toLowerCase());
                if (ok && clash) {
                  setState(() => error = 'Another owner already has this');
                  return;
                }
                if (!ok) {
                  setState(() => error = item.ownerChannelAt(owner) == 'email' ? 'This email looks wrong' : 'Type the 10 digit number');
                  return;
                }
                Navigator.pop(dialog, item.ownerChannelAt(owner) == 'email' ? value : value.replaceAll(RegExp(r'\D'), ''));
              },
              child: const Text('Send again'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.update(
      item.id,
      (i) => owner == 0
          ? i.copyWith(contact: saved, lastAskedAt: now)
          : i.copyWith(coOwners: [
              for (var n = 0; n < i.coOwners.length; n++)
                if (n == owner - 1) i.coOwners[n].copyWith(contact: saved, lastAskedAt: now) else i.coOwners[n],
            ]),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We sent the request to the new contact.')));
    }
  }

  List<Widget> _questions(BuildContext context) => [
    const OnbBanner('Documents are ready. Now tell us what you agreed with the owner.', kind: 'ok', icon: Icons.check_circle_outline),
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
          for (var o = 1; o < item.ownerCount; o++)
            OnbRow(
              icon: Icons.person_outline,
              tone: 'ok',
              title: item.ownerNameAt(o),
              subtitle: 'Aadhaar, phone and email',
              chevron: false,
              trailing: const OnbPill('Approved', 'ok'),
            ),
        ],
      ),
    ),
    const SizedBox(height: 8),
    Align(alignment: Alignment.centerLeft, child: _callTeamButton()),
  ];

  List<Widget> _preparing() => [
    const OnbCentered(
      icon: Icons.description_outlined,
      title: 'Making your agreement',
      message: 'We are writing it using the documents from the owner and what you told us. It will go to the owner soon.',
      loading: true,
    ),
    const SizedBox(height: 16),
    const OnbBanner('You can close the app. We will tell you when it is ready.', icon: Icons.notifications_none),
    const SizedBox(height: 8),
    Align(alignment: Alignment.centerLeft, child: _callTeamButton()),
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
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        children: [
          TextButton(
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
          _callTeamButton(),
        ],
      ),
    ];
  }

  /// Call the team that writes the agreements.
  Widget _callTeamButton() => TextButton.icon(
    onPressed: () => launchUrl(Uri.parse('tel:+918088516875')),
    icon: const Icon(Icons.call_outlined, size: 20),
    label: const Text('Call our agreement team', style: TextStyle(fontSize: 16)),
  );

  List<Widget> _signing(BuildContext context) {
    final first = _firstName(item);
    String tone(int step) => item.printStep > step ? 'ok' : item.printStep == step ? 'info' : 'mute';
    String label(int step) => item.printStep > step ? 'Done' : item.printStep == step ? 'Now' : 'Later';
    return [
      if (item.phase == OnboardingPhase.printing)
        const OnbBanner('The final draft is locked. Our team is getting it ready for signing.', kind: 'info', icon: Icons.lock_outline)
      else if (!item.brokerSigned)
        OnbBanner(
          item.hasManyOwners
              ? 'Everyone signs on their phone with a code. ${item.signedOwners} of ${item.ownerCount} owners have signed.'
              : 'Everyone signs on their phone with a code. $first ${item.ownerSigned ? 'has signed.' : 'has not signed yet.'}',
          kind: 'wait',
          icon: Icons.draw_outlined,
        )
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
              for (var o = 0; o < item.ownerCount; o++)
                OnbRow(
                  icon: Icons.check,
                  tone: item.ownerSignedAt(o) ? 'ok' : 'wait',
                  title: item.ownerNameAt(o),
                  subtitle: item.ownerSignedAt(o) ? 'Signed' : (item.hasManyOwners ? 'Owner ${o + 1}' : 'Owner'),
                  chevron: false,
                  trailing: OnbPill(item.ownerSignedAt(o) ? 'Signed' : 'Waiting', item.ownerSignedAt(o) ? 'ok' : 'wait'),
                ),
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
          : 'Documents are checked and the agreement is signed. Now find a tenant.',
    ),
    const SizedBox(height: 20),
    OnbCard(
      child: Column(
        children: [
          OnbKeyValue(item.hasManyOwners ? 'Owners' : 'Owner', item.ownersFull),
          OnbKeyValue('Rent', onbMoney(item.rent)),
          OnbKeyValue('Deposit', onbMoney(item.deposit)),
          OnbKeyValue('Agreement', item.agreementSkipped ? 'Skipped' : 'Signed', last: true),
        ],
      ),
    ),
  ];

  // ---- main button at the bottom ----

  /// In the agreement stage, "Read the full agreement" is the second button.
  List<Widget> _footer(BuildContext context) {
    final core = _footerCore(context);
    final read = OnbReadFullButton(
      label: 'Read the full agreement',
      onPressed: () => context.push('/broker/onboarding/${item.id}/agreement'),
    );
    switch (item.phase) {
      case OnboardingPhase.preparing:
      case OnboardingPhase.review:
        if (core.isEmpty) return [read];
        return [core.first, const SizedBox(height: 10), read, ...core.skip(1)];
      default:
        return core;
    }
  }

  List<Widget> _footerCore(BuildContext context) {
    switch (item.phase) {
      case OnboardingPhase.papers:
        if (item.allPapersDone) {
          return [PrimaryButton(label: 'Continue', onPressed: () => store.update(item.id, (i) => i.copyWith(phase: OnboardingPhase.questions)))];
        }
        return const [];
      case OnboardingPhase.questions:
        // One button only.
        return [
          PrimaryButton(
            label: 'Next: collaboration details',
            onPressed: () => context.push('/broker/onboarding/${item.id}/questions'),
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
              onPressed: () => sendDraftWithConfirm(context, item),
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
        for (var o = 0; o < item.ownerCount; o++) {
          final mine = o == 0 ? item.papers : item.personalPapersAt(o);
          if (mine.every((p) => p.status == PaperStatus.waiting || p.status == PaperStatus.approved) && !item.ownerPapersDone(o)) {
            buttons.add((
              item.hasManyOwners ? '${item.ownerFirstAt(o)} sends documents' : 'Owner sends some documents',
              () => store.testOwnerSendsPapers(item.id, owner: o),
            ));
          }
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
        for (var o = 0; o < item.ownerCount; o++) {
          if (!item.ownerSignedAt(o)) {
            final who = o;
            buttons.add((item.hasManyOwners ? '${item.ownerFirstAt(o)} signs' : 'Owner signs', () => store.testOwnerSigns(item.id, owner: who)));
          }
        }
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
            const Text('Email, WhatsApp, reading documents and e-sign are not connected yet. Use these to pretend the next step happened.', style: TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
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
  const PaperDetailScreen({required this.id, required this.paperKey, this.owner = 0, super.key});
  final String id;
  final String paperKey;

  /// 0 is the main owner, 1.. are the other owners.
  final int owner;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) {
      if (owner >= item.ownerCount) {
        return OnbPage(
          title: PaperKeys.title(paperKey),
          footer: [PrimaryButton(label: 'Back to documents', onPressed: () => context.pop())],
          children: const [OnbBanner('This owner was removed from the house.', icon: Icons.info_outline)],
        );
      }
      final paper = item.paperAt(owner, paperKey);
      final store = PropertyOnboardingStore.instance;
      final first = item.ownerFirstAt(owner);
      final q = owner == 0 ? '' : '?o=$owner';
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
          footer.add(PrimaryButton(label: 'Back to documents', onPressed: () => context.pop()));
        case PaperStatus.checking:
          body.add(const OnbBanner('We are reading it. Takes about 1 minute. You can leave this screen.', kind: 'info', icon: Icons.schedule));
          footer.add(PrimaryButton(label: 'Back to documents', onPressed: () => context.pop()));
        case PaperStatus.notNeeded:
          body.add(const OnbBanner('The owner says this is not needed.', icon: Icons.info_outline));
          footer.add(PrimaryButton(label: 'Back to documents', onPressed: () => context.pop()));
        case PaperStatus.needsYou:
          body.addAll([
            OnbCard(child: Text(paper.reason, style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.body))),
            const SizedBox(height: 12),
            const OnbBanner('Is this the same person?', kind: 'wait', icon: Icons.help_outline),
          ]);
          footer.addAll([
            PrimaryButton(label: 'Yes, same person', onPressed: () async {
              await store.update(id, (i) => i.withOwnerPaper(owner, paperKey, PaperStatus.approved, value: paper.value));
              if (context.mounted) context.pop();
            }),
            const SizedBox(height: 10),
            OnbSecondaryButton(label: 'No, ask again', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey$q')),
          ]);
        case PaperStatus.notClear:
          body.addAll([
            OnbBanner('Why: ${paper.reason}', kind: 'need', icon: Icons.error_outline),
            const SizedBox(height: 14),
            const Text('What do you want to do?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.heading)),
          ]);
          footer.addAll([
            PrimaryButton(label: 'Ask $first again', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey$q')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OnbSecondaryButton(label: 'I add it', onPressed: () => _addMyself(context, item, paper, owner))),
                const SizedBox(width: 10),
                Expanded(child: OnbSecondaryButton(label: 'Call owner', onPressed: item.ownerChannelAt(owner) == 'whatsapp' ? () => _callOwner(item, owner) : null)),
              ],
            ),
          ]);
        case PaperStatus.waiting:
          body.add(OnbBanner('Asked ${_ago(item.ownerAskedAt(owner))}. Waiting for $first.', kind: 'wait', icon: Icons.schedule));
          footer.addAll([
            PrimaryButton(label: 'Remind $first', onPressed: () => context.push('/broker/onboarding/$id/ask/$paperKey$q')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OnbSecondaryButton(label: 'I add it', onPressed: () => _addMyself(context, item, paper, owner))),
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
                  Expanded(child: OnbSecondaryButton(label: 'Call owner', onPressed: item.ownerChannelAt(owner) == 'whatsapp' ? () => _callOwner(item, owner) : null)),
              ],
            ),
          ]);
      }
      return OnbPage(
        title: PaperKeys.title(paperKey),
        subtitle: item.ownerNameAt(owner),
        footer: footer,
        children: body,
      );
    },
  );

  Future<void> _addMyself(BuildContext context, PropertyOnboarding item, OnboardingPaper paper, int owner) async {
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
            Text('Type what is on the document. ${PaperKeys.hint(paper.key)}.', style: const TextStyle(fontSize: 16, color: AppColors.muted)),
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
    await PropertyOnboardingStore.instance.update(item.id, (i) => i.withOwnerPaper(owner, paper.key, PaperStatus.approved, value: value));
    if (context.mounted) context.pop();
  }
}

/// Ask the owner again, with the reason in simple words.
class AskAgainScreen extends StatefulWidget {
  const AskAgainScreen({required this.id, required this.paperKey, this.owner = 0, super.key});
  final String id;
  final String paperKey;
  final int owner;

  @override
  State<AskAgainScreen> createState() => _AskAgainScreenState();
}

class _AskAgainScreenState extends State<AskAgainScreen> {
  static const _reasons = {
    'Photo is blurry': 'the photo is blurry. Please send a clear photo. Keep all 4 corners inside.',
    'Wrong document': 'this is not the document we need. Please send the right one.',
    'Pages missing': 'some pages are missing. Please send all pages.',
    'Name is different': 'the name is different from the other documents. Please send the right document.',
  };
  String _reason = 'Photo is blurry';

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      if (widget.owner >= item.ownerCount) {
        return OnbPage(
          title: 'Ask again',
          footer: [PrimaryButton(label: 'Back', onPressed: () => context.pop())],
          children: const [OnbBanner('This owner was removed from the house.', icon: Icons.info_outline)],
        );
      }
      final minutes = _cooldownMinutes(item, widget.owner);
      final first = item.ownerFirstAt(widget.owner);
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
                      (i) => i
                          .withOwnerPaper(widget.owner, widget.paperKey, PaperStatus.waiting)
                          .withOwnerAsked(widget.owner, DateTime.now().millisecondsSinceEpoch),
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

/// More than one owner: one tab for each owner, with that owner's own papers
/// and status. House papers (address, rent, bank, keys) come from Owner 1, so
/// they sit in Owner 1's tab.
class _ManyOwnersPapers extends StatefulWidget {
  const _ManyOwnersPapers({
    required this.item,
    required this.onNotReplying,
    required this.onAddOwner,
    required this.onRemoveOwner,
  });
  final PropertyOnboarding item;
  final void Function(int owner) onNotReplying;
  final VoidCallback onAddOwner;
  final void Function(int owner) onRemoveOwner;

  @override
  State<_ManyOwnersPapers> createState() => _ManyOwnersPapersState();
}

class _ManyOwnersPapersState extends State<_ManyOwnersPapers> {
  int _owner = 0;

  PropertyOnboarding get item => widget.item;

  bool _done(int o) => item.ownerPapersDone(o) && (o != 0 || item.sharedPapersDone);
  int _need(int o) => item.ownerNeedYouAt(o) + (o == 0 ? item.sharedNeedYou : 0);

  /// A browser-style tab: the open tab joins the page below it.
  Widget _tab(int o, bool selected) {
    final done = _done(o);
    final need = _need(o);
    final (icon, color) = done
        ? (Icons.check_circle, AppColors.success)
        : need > 0
            ? (Icons.error, AppColors.warning)
            : (Icons.schedule, AppColors.muted);
    return GestureDetector(
      onTap: () => setState(() => _owner = o),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 190),
        height: selected ? 50 : 44,
        margin: const EdgeInsets.only(right: 4),
        // The outer box is the outline; the inner box is the tab itself.
        padding: EdgeInsets.fromLTRB(1, selected ? 2.5 : 1, 1, selected ? 0 : 1),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.border,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? Colors.white : AppColors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Owner ${o + 1} · ${item.ownerFirstAt(o)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.primaryDark : AppColors.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _owner >= item.ownerCount ? 0 : _owner;
    final first = item.ownerFirstAt(o);
    final query = o == 0 ? '' : '?o=$o';
    final papers = o == 0 ? item.papers : item.personalPapersAt(o);
    final silentDays = (DateTime.now().millisecondsSinceEpoch - item.ownerAskedAt(o)) ~/ const Duration(days: 1).inMilliseconds;
    final allWaiting = papers.every((p) => p.status == PaperStatus.waiting || p.status == PaperStatus.approved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tabs, like the tabs of a desktop browser.
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < item.ownerCount; i++) _tab(i, i == o),
                if (item.ownerCount < 10)
                  GestureDetector(
                    onTap: widget.onAddOwner,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Icon(Icons.add, size: 22, color: AppColors.primaryDark),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_done(o))
          OnbBanner(o == 0 ? '$first\'s documents and the house documents are approved.' : '$first\'s documents are approved.', kind: 'ok', icon: Icons.check_circle_outline)
        else if (_need(o) > 0)
          OnbBanner(_need(o) == 1 ? '1 document needs you.' : '${_need(o)} documents need you.', kind: 'need', icon: Icons.error_outline)
        else if (allWaiting && silentDays >= 3)
          OnbBanner('$first has not replied for $silentDays days.', kind: 'wait', icon: Icons.schedule)
        else
          OnbBanner('Asked ${_ago(item.ownerAskedAt(o))}. Waiting for $first.', kind: 'wait', icon: Icons.schedule),
        const SizedBox(height: 14),
        OnbCard(
          child: Column(
            children: [
              for (final paper in papers)
                OnbRow(
                  icon: paperIcon(paper.key),
                  tone: paperStatusKind(paper.status),
                  title: PaperKeys.title(paper.key),
                  subtitle: paper.value.isNotEmpty ? paper.value : PaperKeys.hint(paper.key),
                  trailing: OnbPill(paperStatusLabel(paper.status), paperStatusKind(paper.status)),
                  onTap: () => context.push('/broker/onboarding/${item.id}/paper/${paper.key}$query'),
                ),
            ],
          ),
        ),
        if (o > 0) ...[
          const SizedBox(height: 12),
          OnbRow(
            icon: Icons.home_outlined,
            tone: item.sharedPapersDone ? 'ok' : 'mute',
            title: 'House documents come from ${item.ownerFirstAt(0)}',
            subtitle: 'Address, rent, bank, keys. See Owner 1',
            onTap: () => setState(() => _owner = 0),
          ),
        ],
        if (!_done(o)) ...[
          const SizedBox(height: 12),
          OnbRow(
            icon: Icons.help_outline,
            tone: 'mute',
            title: '$first not replying?',
            subtitle: 'Remind, call or change the contact',
            onTap: () => widget.onNotReplying(o),
          ),
        ],
        if (o > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onRemoveOwner(o),
              icon: const Icon(Icons.person_remove_outlined, size: 20, color: AppColors.error),
              label: Text('Remove $first from this house', style: const TextStyle(color: AppColors.error, fontSize: 16)),
            ),
          ),
      ],
    );
  }
}

/// Add one more owner to a house that is still collecting papers.
class _AddOwnerSheet extends StatefulWidget {
  const _AddOwnerSheet({required this.item});
  final PropertyOnboarding item;

  @override
  State<_AddOwnerSheet> createState() => _AddOwnerSheetState();
}

class _AddOwnerSheetState extends State<_AddOwnerSheet> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  String _channel = 'email';
  String? _nameError;
  String? _contactError;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _save() {
    final item = widget.item;
    final name = _name.text.trim();
    final value = _contact.text.trim();
    String? nameError = name.length < 2 ? 'Type the owner name' : null;
    String? contactError;
    if (_channel == 'email') {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(value)) contactError = 'This email looks wrong. Check the @ and the dot.';
    } else if (value.length != 10) {
      contactError = 'Type the 10 digit phone number';
    }
    for (var i = 0; i < item.ownerCount; i++) {
      if (nameError == null && item.ownerNameAt(i).trim().toLowerCase() == name.toLowerCase()) {
        nameError = '${item.ownerFirstAt(i)} is already an owner. Add the full name.';
      }
      if (contactError == null && item.ownerChannelAt(i) == _channel && item.ownerContactAt(i).toLowerCase() == value.toLowerCase()) {
        contactError = 'Already added as Owner ${i + 1}. Use a different ${_channel == 'email' ? 'email' : 'number'}.';
      }
    }
    setState(() {
      _nameError = nameError;
      _contactError = contactError;
    });
    if (nameError != null || contactError != null) return;
    Navigator.pop(context, CoOwner(name: name, channel: _channel, contact: value));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add another owner', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
        const SizedBox(height: 4),
        Text('We will ask for their Aadhaar, phone and email. House documents still come from ${widget.item.ownerFirstAt(0)}.', style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted)),
        const SizedBox(height: 24),
        OnbTextField(label: 'Full name', controller: _name, error: _nameError, capitalization: TextCapitalization.words),
        const SizedBox(height: 26),
        Wrap(
          spacing: 8,
          children: [
            for (final (value, label) in const [('email', 'Email · best'), ('whatsapp', 'WhatsApp')])
              ChoiceChip(
                label: Text(label),
                selected: _channel == value,
                onSelected: (_) => setState(() {
                  _channel = value;
                  _contact.clear();
                  _contactError = null;
                }),
                showCheckmark: false,
                selectedColor: AppColors.primarySoft,
                labelStyle: TextStyle(fontSize: 15, color: _channel == value ? AppColors.primaryDark : AppColors.body),
                side: BorderSide(color: _channel == value ? AppColors.primary : AppColors.border),
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: 26),
        OnbTextField(
          label: _channel == 'email' ? 'Email' : 'WhatsApp number',
          controller: _contact,
          error: _contactError,
          keyboard: _channel == 'email' ? TextInputType.emailAddress : TextInputType.number,
          prefix: _channel == 'email' ? null : '+91 ',
          formatters: _channel == 'email' ? null : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        ),
        const SizedBox(height: 24),
        PrimaryButton(label: 'Add and ask for documents', onPressed: _save),
      ],
    ),
  );
}
