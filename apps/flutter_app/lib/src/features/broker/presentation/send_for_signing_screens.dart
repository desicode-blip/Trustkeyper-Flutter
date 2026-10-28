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

String _viaText(String via) => switch (via) {
  'both' => 'WhatsApp and email',
  'email' => 'email',
  _ => 'WhatsApp',
};

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
// RV4 · Send to each owner
// ---------------------------------------------------------------------------

class SendToEachScreen extends StatefulWidget {
  const SendToEachScreen({required this.id, super.key});
  final String id;

  @override
  State<SendToEachScreen> createState() => _SendToEachScreenState();
}

class _SendToEachScreenState extends State<SendToEachScreen> {
  bool _wa = true;
  bool _email = true;

  /// How we can reach this owner with the ticks picked ('' = we cannot).
  String _via(PropertyOnboarding item, int o) {
    final wa = _wa && item.ownerPhoneAt(o).isNotEmpty;
    final em = _email && item.ownerEmailAt(o).isNotEmpty;
    if (wa && em) return 'both';
    if (wa) return 'whatsapp';
    if (em) return 'email';
    return '';
  }

  String? _cannot(PropertyOnboarding item, int o) {
    if (!_wa && !_email) return 'Pick WhatsApp or email above.';
    if (_via(item, o).isNotEmpty) return null;
    final first = item.ownerFirstAt(o);
    return _wa ? 'No WhatsApp number for $first. Tick Email too.' : 'No email for $first. Tick WhatsApp too.';
  }

  Future<void> _send(PropertyOnboarding item, int o) async {
    final via = _via(item, o);
    if (via.isEmpty) return;
    await _store.sendDraftTo(item.id, o, via);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Sent to ${item.ownerFirstAt(o)} on ${_viaText(via)}'),
      behavior: SnackBarBehavior.floating,
      margin: _toastMargin,
    ));
  }

  Future<void> _sendAll(PropertyOnboarding item) async {
    var sent = 0;
    final missed = <String>[];
    for (var o = 0; o < item.ownerCount; o++) {
      if (item.replyAt(o).sent) continue;
      final via = _via(item, o);
      if (via.isEmpty) {
        missed.add(item.ownerFirstAt(o));
        continue;
      }
      await _store.sendDraftTo(item.id, o, via);
      sent++;
    }
    if (!mounted) return;
    final text = missed.isEmpty
        ? (sent == 1 ? 'Sent to ${item.ownerFirstAt(0)}' : 'Sent to all $sent owners')
        : 'Sent to $sent. Not sent to ${missed.join(', ')}: see the note on the card.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, margin: _toastMargin));
  }

  Future<void> _done(PropertyOnboarding item) async {
    await _store.finishSending(item.id);
    if (mounted) context.pushReplacement('/broker/onboarding/${item.id}/sent');
  }

  @override
  Widget build(BuildContext context) => OnbItemView(
    id: widget.id,
    builder: (context, item) {
      final notSent = item.ownerCount - item.sentCount;
      return PopScope(
        canPop: item.sentCount == 0,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final finish = await onbConfirm(
            context,
            title: 'Leave this page?',
            message: '${item.sentCount == 1 ? 'One owner has' : '${item.sentCount} owners have'} the agreement already. We will mark it as sent.',
            yes: 'Mark as sent and leave',
            no: 'Stay here',
          );
          if (finish && context.mounted) await _done(item);
        },
        child: OnbPage(
          title: item.hasManyOwners ? 'Send to each owner' : 'Send to ${item.ownerFirstAt(0)}',
          subtitle: 'Each owner gets their own link. They read it, then say yes or ask a change.',
          footer: [
            if (item.sentCount > 0 && notSent > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Text(notSent == 1 ? '1 owner not sent yet' : '$notSent owners not sent yet', style: const TextStyle(fontSize: 15, color: AppColors.warning)),
                  ],
                ),
              ),
            if (item.sentCount == 0)
              PrimaryButton(
                label: item.hasManyOwners ? 'Send to everyone' : 'Send to ${item.ownerFirstAt(0)}',
                onPressed: (!_wa && !_email) ? null : () => _sendAll(item),
              )
            else
              PrimaryButton(label: 'Done', onPressed: () => _done(item)),
          ],
          children: [
            Row(
              children: const [
                Icon(Icons.send_outlined, size: 16, color: AppColors.muted),
                SizedBox(width: 6),
                Flexible(child: Text('Send on (you can pick both)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _Tick(on: _wa, label: 'WhatsApp', icon: SvgPicture.asset('assets/design/whatsapp.svg', width: 20, height: 20), onTap: () => setState(() => _wa = !_wa))),
                const SizedBox(width: 8),
                Expanded(child: _Tick(on: _email, label: 'Email', icon: const Icon(Icons.mail_outline, size: 20, color: AppColors.primaryDark), onTap: () => setState(() => _email = !_email))),
              ],
            ),
            const SizedBox(height: 16),
            for (var o = 0; o < item.ownerCount; o++) ...[
              _OwnerSendCard(
                item: item,
                owner: o,
                cannot: _cannot(item, o),
                onSend: () => _send(item, o),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            const Text('Signs at the end', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted)),
            const SizedBox(height: 8),
            OnbCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ManagerSignRow(item: item, onChange: () => pickWhoSigns(context, item)))),
            const SizedBox(height: 14),
            const Text(
              'Test only: WhatsApp and email are not connected yet, so nothing really reaches the owner.',
              style: TextStyle(fontSize: 13.5, height: 19 / 13.5, color: AppColors.muted),
            ),
          ],
        ),
      );
    },
  );
}

class _Tick extends StatelessWidget {
  const _Tick({required this.on, required this.label, required this.icon, required this.onTap});
  final bool on;
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: on,
    child: Material(
      color: on ? AppColors.primarySoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: on ? null : Border.all(color: const Color(0xFF9AA8BA), width: 2),
                  ),
                  child: on ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                ),
                const SizedBox(width: 10),
                icon,
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.heading))),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _OwnerSendCard extends StatelessWidget {
  const _OwnerSendCard({required this.item, required this.owner, required this.cannot, required this.onSend});
  final PropertyOnboarding item;
  final int owner;
  final String? cannot;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final reply = item.replyAt(owner);
    final hasPhone = item.ownerPhoneAt(owner).isNotEmpty;
    final hasEmail = item.ownerEmailAt(owner).isNotEmpty;
    Widget reach(bool ok, Widget icon, String yes, String no) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ok ? icon : const Icon(Icons.error_outline, size: 14, color: Color(0xFFE08A00)),
        const SizedBox(width: 4),
        Flexible(child: Text(ok ? yes : no, style: TextStyle(fontSize: 13.5, color: ok ? AppColors.muted : const Color(0xFFB36A00)))),
      ],
    );
    return OnbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SignAvatar(_initials(item.ownerNameAt(owner))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: item.ownerNameAt(owner)),
                        TextSpan(text: item.hasManyOwners ? ' · Owner ${owner + 1}' : ' · Owner', style: const TextStyle(fontWeight: FontWeight.w400, color: AppColors.muted, fontSize: 14)),
                      ]),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.heading),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        reach(hasPhone, SvgPicture.asset('assets/design/whatsapp.svg', width: 14, height: 14), 'WhatsApp', 'No WhatsApp number'),
                        reach(hasEmail, const Icon(Icons.mail_outline, size: 14, color: AppColors.primaryDark), 'Email', 'No email'),
                      ],
                    ),
                  ],
                ),
              ),
              if (reply.sent) const OnbPill('Sent', 'ok', icon: Icons.check),
            ],
          ),
          if (reply.sent)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 60),
              child: Text('On ${_viaText(reply.via)} · ${_ago(reply.sentAt)}', style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
            )
          else ...[
            if (cannot != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(cannot!, style: const TextStyle(fontSize: 14, height: 19 / 14, color: AppColors.warning)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: cannot == null ? onSend : null,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text('Send to ${item.ownerFirstAt(owner)}'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
