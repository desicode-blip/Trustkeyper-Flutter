import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/primary_button.dart';
import '../features/auth/presentation/approved_auth_widgets.dart';
import '../features/broker/data/private_documents.dart';
import '../features/broker/presentation/onboarding_widgets.dart';
import '../tk2/tk2_cloud.dart';
import '../tk2/tk2_deal.dart';
import '../tk2/tk2_deal_page.dart';
import '../tk2/tk2_store.dart';
import 'tkweb_auth.dart';
import 'tkweb_owner.dart';
import 'tkweb_session.dart';
import 'tkweb_tenant.dart';

String tkwDocName(DocumentKind kind) => kind.label;

/// With the backend on the file is uploaded for the broker; in the demo build
/// it stays on this device and only "Received" is recorded.
Future<String> tkwUploadDoc(String dealId, DocumentFile file) async {
  if (!Tk2Cloud.on) return 'Received';
  file.validate();
  return Tk2Cloud.uploadDealBytes(dealId, file.bytes);
}

/// The deal page on the web, for the tenant or the owner. Documents use the
/// web app's own screens (the main app's document flow).
class TkwDeal extends StatelessWidget {
  const TkwDeal({required this.dealId, required this.role, super.key});
  final String dealId;
  final DealRole role;

  Future<void> _docs(BuildContext context, Tk2Deal d) async {
    final nav = Navigator.of(context);
    if (role == DealRole.tenant) {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => TkwStep(listingId: d.listingId, index: tkwTenantSteps.indexOf('docs')),
        ),
      );
      return;
    }
    // Owner: the same documents screen as when adding the house. Sending
    // there (now, or earlier when they added the house) completes this step.
    final a = TkwSession.instance.owner(d.listingId);
    final before = a['docsSentAt'];
    final early = a['docsSent'] == true && !d.docsSent(DealRole.owner);
    if (!early) {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => TkwOwnerDocs(houseId: d.listingId, brokerName: d.brokerName),
        ),
      );
    }
    if (!early && a['docsSentAt'] == before) return;
    d.o.addAll({
      'docsAt': DateTime.now().millisecondsSinceEpoch,
      'docs': {'Aadhaar card': 'Received', 'Bank details for the rent': 'Received', if (a['oldAgreement'] == true) 'Old rent agreement': 'Received'},
    });
    await Tk2Store.instance.saveDeal(d, DealRole.owner);
    if (early && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('We already have your documents. Sent to the broker.')));
    }
  }

  @override
  Widget build(BuildContext context) =>
      Tk2DealPage(store: Tk2Store.instance, dealId: dealId, role: role, showBack: Navigator.of(context).canPop(), onDocs: _docs);
}

/// A deal link was opened (#deal-… demo, #d-ID backend): say what it is, sign
/// in if needed, then show the deal.
class TkwDealStart extends StatefulWidget {
  const TkwDealStart({required this.dealId, this.role, super.key});
  final String dealId;

  /// Known from the demo link; with the backend it comes from who signs in.
  final DealRole? role;

  @override
  State<TkwDealStart> createState() => _TkwDealStartState();
}

class _TkwDealStartState extends State<TkwDealStart> {
  bool busy = false;
  String? error;

  Future<void> _open() async {
    final nav = Navigator.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    final store = Tk2Store.instance;
    var role = widget.role;
    if (store.sync != null) {
      final d = await store.sync!.openDeal(widget.dealId).catchError((Object _) => null);
      role = d == null ? null : store.sync!.roleIn(d);
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (role == null || store.deal(widget.dealId) == null) {
      nav.popUntil((r) => r.isFirst);
      return setState(() => error = 'Use the phone number or email your broker has for this deal.');
    }
    nav.popUntil((r) => r.isFirst);
    nav.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TkwDeal(dealId: widget.dealId, role: role!),
        settings: const RouteSettings(name: 'deal'),
      ),
    );
  }

  void _start() {
    if (TkwSession.instance.signedIn && error == null) {
      _open();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TkwSignUp(allowEmail: widget.role != DealRole.tenant, subtitle: 'Your name, and your phone. We send a code to check it is you.', onDone: _open),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = Tk2Store.instance.deal(widget.dealId);
    final owner = widget.role == DealRole.owner;
    return ApprovedAuthScaffold(
      showBack: false,
      header: const ApprovedLoginHero(),
      footer: PrimaryButton(label: 'Continue', icon: Icons.chevron_right, loading: busy, onPressed: busy ? null : _start),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(owner ? 'Your house is being rented' : 'Your move-in', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          Text(
            d == null
                ? 'Your broker sent you the next step. Sign in to see it.'
                : owner
                ? '${d.nameOf(DealRole.tenant)} has blocked ${d.title} with a token of ${Tk2Store.money(d.token)}. A few steps are yours: documents, the agreement, and signing.'
                : '${d.nameOf(DealRole.broker)} is taking you from the token to the keys for ${d.title}, one step at a time.',
            style: const TextStyle(fontSize: 16, height: 23 / 16, color: AppColors.muted),
          ),
          if (error != null) ...[const SizedBox(height: 16), OnbBanner(error!, kind: 'need', icon: Icons.error_outline)],
        ],
      ),
    );
  }
}
