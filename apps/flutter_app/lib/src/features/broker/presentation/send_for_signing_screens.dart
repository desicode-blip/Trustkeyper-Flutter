import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/property_onboarding.dart';
import 'onboarding_house_screens.dart';
import 'onboarding_widgets.dart';

// Send for signing: built from the v2 canvas, page 06 (RV3 confirm, RV4 send to
// each person, RV5 sent, RV6 who replied) and the home card HM1.
// Nothing is really sent yet: WhatsApp and email need the backend.

PropertyOnboardingStore get _store => PropertyOnboardingStore.instance;

const _green = Color(0xFF2FA866);

/// Toasts float above the bottom buttons so they never cover them.
const _toastMargin = EdgeInsets.fromLTRB(16, 0, 16, 150);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _ago(int at) {
  if (at == 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return '${d.inDays} days ago';
}

/// Round avatar with initials (owners blue, manager green).
class SignAvatar extends StatelessWidget {
  const SignAvatar(this.text, {this.manager = false, super.key});
  final String text;
  final bool manager;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: manager ? AppColors.successSoft : AppColors.primarySoft, shape: BoxShape.circle),
    child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: manager ? AppColors.success : AppColors.primaryDark)),
  );
}

/// Who signs as the manager: TrustKeyper, or the broker.
Future<void> pickWhoSigns(BuildContext context, PropertyOnboarding item) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) {
      Widget tile(String value, String title, String sub) {
        final on = item.signsAs == value || (value == 'trustkeyper' && item.trustkeyperSigns && item.signsAs != 'me');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: on ? AppColors.primarySoft : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(sheet, value),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? AppColors.primary : AppColors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
                          const SizedBox(height: 2),
                          Text(sub, style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Who signs as the manager?', style: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, color: AppColors.heading)),
              const SizedBox(height: 6),
              const Text('The owners sign first. The manager signs last.', style: TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted)),
              const SizedBox(height: 16),
              tile('trustkeyper', 'TrustKeyper signs', 'Our signatory signs for TrustKeyper (Paravent). Use this when TrustKeyper manages the house.'),
              tile('me', 'I sign', 'You sign as the broker, for your own business.'),
            ],
          ),
        ),
      );
    },
  );
  if (picked != null && picked != item.signsAs) await _store.setSignsAs(item.id, picked);
}

/// The manager row (TrustKeyper or You), used on every signing screen.
class ManagerSignRow extends StatelessWidget {
  const ManagerSignRow({required this.item, this.onChange, this.trailing, super.key});
  final PropertyOnboarding item;
  final VoidCallback? onChange;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tk = item.trustkeyperSigns;
    return Row(
      children: [
        SignAvatar(tk ? 'TK' : 'You', manager: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: tk ? 'TrustKeyper' : 'You'),
                  TextSpan(text: tk ? ' · Manager' : ' · Broker', style: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.muted, fontSize: 14)),
                ]),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
              const SizedBox(height: 2),
              Text(
                tk ? 'Signs last, for the company. No link needed.' : 'You sign last. No link needed.',
                style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (onChange != null) TextButton(onPressed: onChange, child: const Text('Change', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
        ?trailing,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Send for signing sheet (canvas SL1 "Send link?" style): WhatsApp or email
// ---------------------------------------------------------------------------

/// The way this owner gets it: the one picked, or the other one when we do
/// not have it for them ('' when we have neither).
String sendWayFor(PropertyOnboarding item, int o, String picked) {
  final wa = item.ownerPhoneAt(o).isNotEmpty;
  final em = item.ownerEmailAt(o).isNotEmpty;
  if (picked == 'whatsapp') return wa ? 'whatsapp' : (em ? 'email' : '');
  return em ? 'email' : (wa ? 'whatsapp' : '');
}

/// Returns 'whatsapp' or 'email', or null when the broker cancels.
Future<String?> pickSendWay(BuildContext context, PropertyOnboarding item) {
  final anyWa = [for (var o = 0; o < item.ownerCount; o++) item.ownerPhoneAt(o).isNotEmpty].contains(true);
  final anyEm = [for (var o = 0; o < item.ownerCount; o++) item.ownerEmailAt(o).isNotEmpty].contains(true);
  var picked = anyWa ? 'whatsapp' : 'email';
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => ListenableBuilder(
        listenable: _store,
        builder: (sheet, _) {
          final now = _store.byId(item.id) ?? item;
          final many = now.hasManyOwners;
          final first = now.ownerFirstAt(0);
          final to = many
              ? 'To ${now.ownersFirst}'
              : 'To $first · ${picked == 'whatsapp' ? now.ownerPhoneAt(0) : now.ownerEmailAt(0)}';
          // Owners who will get it the other way.
          final other = [
            for (var o = 0; o < now.ownerCount; o++)
              if (sendWayFor(now, o, picked).isNotEmpty && sendWayFor(now, o, picked) != picked) now.ownerFirstAt(o),
          ];
          Widget tile(String value, Widget icon, String title, String sub, bool enabled) {
            final on = picked == value && enabled;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: enabled ? 1 : 0.55,
                child: Material(
                  color: on ? AppColors.primarySoft : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 2 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: enabled ? () => setSheet(() => picked = value) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? AppColors.primary : AppColors.muted, size: 24),
                          const SizedBox(width: 12),
                          icon,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading)),
                                const SizedBox(height: 2),
                                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final emailSub = !anyEm
              ? 'No email added'
              : many
                  ? 'Each owner on their own email'
                  : now.ownerEmailAt(0);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
                        child: const Icon(Icons.send_outlined, size: 22, color: AppColors.success),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              many ? 'Send for signing?' : 'Send to $first for signing?',
                              style: const TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w700, color: AppColors.heading),
                            ),
                            const SizedBox(height: 2),
                            Text(to, style: const TextStyle(fontSize: 15, height: 20 / 15, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  tile('whatsapp', SvgPicture.asset('assets/design/whatsapp.svg', width: 22, height: 22), 'WhatsApp',
                      anyWa ? 'Best – most people use it' : 'No WhatsApp number', anyWa),
                  tile('email', const Icon(Icons.mail_outline, size: 22, color: AppColors.primaryDark), 'Email', emailSub, anyEm),
                  if (other.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${other.join(' and ')} ${other.length == 1 ? 'gets' : 'get'} it on ${picked == 'whatsapp' ? 'email' : 'WhatsApp'} (no ${picked == 'whatsapp' ? 'WhatsApp number' : 'email'}).',
                        style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.warning),
                      ),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.draw_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${many ? 'They read it and say yes.' : '$first reads it and says yes.'} ${now.trustkeyperSigns ? 'TrustKeyper signs' : 'You sign'} last.',
                          style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted),
                        ),
                      ),
                      TextButton(onPressed: () => pickWhoSigns(sheet, now), child: const Text('Change')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: (anyWa || anyEm) ? () => Navigator.pop(sheet, picked) : null,
                      icon: const Icon(Icons.send_outlined, size: 20),
                      label: const Text('Send for signing'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheet),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// RV5 · Agreement sent!
// ---------------------------------------------------------------------------

class AgreementSentScreen extends StatelessWidget {
  const AgreementSentScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: id,
    builder: (context, item) {
      final first = item.ownersFirst;
      final n = item.ownerCount;
      final signers = item.trustkeyperSigns ? '$first and TrustKeyper' : '$first and you';
      return OnbPage(
        title: 'Setting up',
        showBack: false,
        footer: [
          PrimaryButton(label: 'Go to home', onPressed: () => context.go('/broker')),
          const SizedBox(height: 10),
          OnbSecondaryButton(label: 'See who replied', onPressed: () => context.go('/broker/onboarding/${item.id}')),
        ],
        children: [
          const SizedBox(height: 8),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.7, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 104,
                height: 104,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 40, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Draft ${item.draftNo} sent!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w700, color: AppColors.heading),
          ),
          const SizedBox(height: 8),
          Text(
            n > 1 ? 'We will tell you when they reply.' : 'We will tell you when $first replies.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 24 / 17, color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          const Text('What happens next', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted)),
          const SizedBox(height: 14),
          SignTimeline(steps: [
            (Icons.send_outlined, 'Sent', n > 1 ? 'To all $n owners' : 'To $first', 'done'),
            (Icons.visibility_outlined, 'They read it', 'On WhatsApp or email', 'now'),
            (Icons.check, 'They say yes', n > 1 ? 'All $n must agree' : '$first must agree', 'later'),
            (Icons.draw_outlined, 'Everyone signs', '$signers. Then the agreement is ready', 'later'),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Test only: WhatsApp and email are not connected yet. On the house page, use the test buttons to pretend the owner replied.',
            style: TextStyle(fontSize: 13.5, height: 19 / 13.5, color: AppColors.muted),
          ),
        ],
      );
    },
  );
}

/// Vertical steps joined by a line (RV5 "What happens next").
/// Each step: icon, title, subtitle, state (done · now · later).
class SignTimeline extends StatelessWidget {
  const SignTimeline({required this.steps, super.key});
  final List<(IconData, String, String, String)> steps;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    _dot(steps[i]),
                    if (i < steps.length - 1)
                      Expanded(child: Container(width: 2, color: steps[i].$4 == 'done' ? _green : AppColors.primaryBorder)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              steps[i].$2,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: steps[i].$4 == 'later' ? AppColors.muted : AppColors.heading),
                            ),
                          ),
                          if (steps[i].$4 == 'now') ...[const SizedBox(width: 8), const OnbPill('Now', 'info')],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(steps[i].$3, style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _dot((IconData, String, String, String) s) {
    final (bg, fg, border) = switch (s.$4) {
      'done' => (_green, Colors.white, null),
      'now' => (AppColors.primary, Colors.white, null),
      _ => (Colors.white, AppColors.muted, Border.all(color: AppColors.border, width: 2)),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border),
      child: Icon(s.$1, size: 20, color: fg),
    );
  }
}

// ---------------------------------------------------------------------------
// RV6 · Who replied (on the house page after sending)
// ---------------------------------------------------------------------------

String feeShort(AgreementAnswers a) {
  String n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  return switch (a.feeType) {
    'percent' => '${n(a.feeValue)}% a month',
    'daysMonthly' => '${n(a.feeValue)} days a month',
    'days' => '${n(a.feeValue)} days, once',
    'fixed' => '${onbMoney(a.feeValue)} a month',
    'once' => '${onbMoney(a.feeValue)} once',
    'none' => 'No fee',
    'later' => 'Each deal',
    _ => 'Not set',
  };
}

/// Can we remind this owner now? (not after yes or a change, and once an hour)
bool canRemind(PropertyOnboarding item, int o) {
  final r = item.replyAt(o);
  if (r.status == 'yes' || r.status == 'change') return false;
  return DateTime.now().millisecondsSinceEpoch - r.remindedAt > const Duration(hours: 1).inMilliseconds;
}

Future<void> remindOwners(BuildContext context, PropertyOnboarding item, List<int> owners) async {
  for (final o in owners) {
    await _store.remindOwner(item.id, o);
  }
  if (!context.mounted || owners.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(owners.length == 1 ? 'Reminder sent to ${item.ownerFirstAt(owners.first)}' : 'Reminded ${owners.length} owners'),
    behavior: SnackBarBehavior.floating,
    margin: _toastMargin,
  ));
}

class WhoReplied extends StatelessWidget {
  const WhoReplied({required this.item, super.key});
  final PropertyOnboarding item;

  @override
  Widget build(BuildContext context) {
    final n = item.ownerCount;
    final yes = item.yesCount;
    final a = item.answers;
    Widget fact(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.heading)),
        ],
      ),
    );
    final start = DateTime.tryParse(a.startDate);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              fact('Rent', onbMoney(item.rent)),
              fact('Starts', start == null ? 'Not set' : '${start.day} ${months[start.month - 1]} ${start.year}'),
              fact('Your fee', feeShort(a)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('Who said yes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted))),
            Text('$yes of $n', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: Container(height: 8, decoration: BoxDecoration(color: i < yes ? _green : AppColors.primaryBorder, borderRadius: BorderRadius.circular(4)))),
            ],
          ],
        ),
        const SizedBox(height: 14),
        OnbCard(
          child: Column(
            children: [
              for (var o = 0; o < n; o++) ...[
                _ownerRow(context, o),
                const Divider(height: 1, color: Color(0xFFEDF1F6)),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ManagerSignRow(item: item, trailing: const OnbPill('Signs last', 'mute')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ownerRow(BuildContext context, int o) {
    final r = item.replyAt(o);
    final (label, kind, icon) = switch (r.status) {
      'yes' => ('Said yes', 'ok', Icons.check),
      'change' => ('Asked a change', 'need', Icons.chat_bubble_outline),
      'seen' => ('Seen, no reply', 'wait', Icons.visibility_outlined),
      _ => r.sent || item.draftSent ? ('Not opened', 'mute', Icons.schedule) : ('Not sent', 'mute', Icons.schedule),
    };
    final reminded = r.remindedAt > 0 && !canRemind(item, o) && r.status != 'yes' && r.status != 'change';
    Widget? action;
    if (r.status == 'change') {
      action = _soft('See', Icons.chevron_right, () => context.push('/broker/onboarding/${item.id}/changes'));
    } else if (r.status != 'yes') {
      action = reminded
          ? Text('Reminded\n${_ago(r.remindedAt)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, height: 16 / 12.5, color: AppColors.muted))
          : _soft('Remind', Icons.notifications_none, () => remindOwners(context, item, [o]));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SignAvatar(_initials(item.ownerNameAt(o))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: item.ownerNameAt(o)),
                    TextSpan(text: item.hasManyOwners ? ' · Owner ${o + 1}' : ' · Owner', style: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.muted, fontSize: 14)),
                  ]),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                ),
                const SizedBox(height: 4),
                OnbPill(label, kind, icon: icon),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _soft(String label, IconData icon, VoidCallback onTap) => SizedBox(
    height: 40,
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        backgroundColor: AppColors.successSoft,
        foregroundColor: AppColors.success,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
