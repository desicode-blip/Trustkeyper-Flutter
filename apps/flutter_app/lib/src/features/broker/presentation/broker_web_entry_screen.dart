import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/current_language_label.dart';
import '../../document_requests/presentation/document_request_widgets.dart';

const brokerPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.trustkeyper.mobile';

class BrokerWebEntryScreen extends StatelessWidget {
  const BrokerWebEntryScreen({this.phone = '', this.openLink, super.key});
  final String phone;
  final Future<bool> Function(Uri)? openLink;
  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final opened =
          await (openLink?.call(uri) ??
              launchUrl(uri, webOnlyWindowName: '_self'));
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The link could not be opened. Try again.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The link could not be opened. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _send(BuildContext context) async {
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isEmpty) {
      await Clipboard.setData(const ClipboardData(text: brokerPlayStoreUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App link copied. Send it to your phone.'),
          ),
        );
      }
      return;
    }
    await _open(
      context,
      Uri.https('wa.me', '/$phoneDigits', {
        'text': 'TrustKeyper app: $brokerPlayStoreUrl',
      }),
    );
  }

  Widget _storeButton(BuildContext context) => PrimaryButton(
    label: 'Get it on Google Play',
    icon: Icons.play_arrow_outlined,
    iconBeforeLabel: true,
    onPressed: () => _open(context, Uri.parse(brokerPlayStoreUrl)),
  );
  Widget _item(String icon, String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primarySoft,
          child: DocumentGlyph(icon, color: AppColors.primaryDark, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _mobile(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Row(
              children: [
                const AppBrand(height: 34),
                const Spacer(),
                const CurrentLanguageLabel(),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    alignment: Alignment.center,
                    child: const DocumentGlyph(
                      'mobile',
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Brokers use the TrustKeyper app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Make agreements, send links, take move-in photos and get paid — all in the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        _item(
                          'check',
                          'Same phone number',
                          phone.isEmpty
                              ? 'Log in with your verified phone number'
                              : 'Log in with $phone',
                        ),
                        const Divider(height: 1),
                        _item(
                          'shield',
                          'Your work is saved',
                          'Agreements you started show in the app',
                        ),
                        const Divider(height: 1),
                        _item(
                          'globe',
                          'Android phones',
                          'From Google Play · free',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _storeButton(context),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _open(
                    context,
                    Uri.parse(
                      'intent://open/broker#Intent;scheme=trustkeyper;package=com.trustkeyper.mobile;S.browser_fallback_url=${Uri.encodeComponent(brokerPlayStoreUrl)};end',
                    ),
                  ),
                  child: const Text(
                    'I have the app · Open it',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _desktop(BuildContext context) => Column(
    children: [
      Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const AppBrand(height: 34),
            const Spacer(),
            Text(
              phone.isEmpty ? 'For brokers' : 'Logged in as $phone',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 890),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'For brokers',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Brokers use the\nTrustKeyper app on their\nphone',
                          style: TextStyle(
                            fontSize: 42,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: AppColors.heading,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Make agreements in 10 minutes, send document links, take stamped move-in photos and see your brokerage — all from your phone.',
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.5,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(width: 245, child: _storeButton(context)),
                            SizedBox(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: () => _send(context),
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Send link to my phone'),
                                style: OutlinedButton.styleFrom(
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Owners and tenants can use TrustKeyper here on the web.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 70),
                  Container(
                    width: 298,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        Semantics(
                          label: 'Scan to open TrustKeyper on Google Play',
                          child: QrImageView(
                            data: brokerPlayStoreUrl,
                            semanticsLabel: brokerPlayStoreUrl,
                            size: 220,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Scan with your phone camera',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Opens the app on Google Play',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MediaQuery.sizeOf(context).width >= 1000
        ? AppColors.surfaceMuted
        : Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 1000 ? _desktop(context) : _mobile(context),
      ),
    ),
  );
}
