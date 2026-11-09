import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import 'tk2_send.dart';
import 'tk2_widgets.dart';

/// "Send link to owner": ask how, then open that app with the message written.
/// WhatsApp opens the normal WhatsApp app directly (no wa.me chooser),
/// Text message opens Messages, Copy link covers anything else.
Future<void> showTk2OwnerInvite(BuildContext context, {required String ownerName, required String phone, required String message}) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final full = digits.length == 10 ? '91$digits' : digits;
  final first = ownerName.trim().split(' ').first;
  final text = Uri.encodeComponent(message);
  final messenger = ScaffoldMessenger.of(context);

  Future<void> whatsapp() async {
    final app = Uri.parse('whatsapp://send?phone=$full&text=$text');
    final ok = await canLaunchUrl(app) && await launchUrl(app, mode: LaunchMode.externalApplication);
    if (!ok) await launchUrl(Uri.parse('https://wa.me/$full?text=$text'), mode: LaunchMode.externalApplication);
  }

  // iOS reads "sms:number&body=", Android "sms:number?body=".
  Future<void> sms() =>
      launchUrl(Uri.parse('sms:+$full${defaultTargetPlatform == TargetPlatform.iOS ? '&' : '?'}body=$text'), mode: LaunchMode.externalApplication);

  Future<void> copy() async {
    await Clipboard.setData(ClipboardData(text: message));
    messenger.showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Message and link copied')));
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheet) {
      Future<void> pick(Future<void> Function() send) async {
        Navigator.of(sheet).pop();
        await send();
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tk2SheetTitle(
                'Send the invite to ${first.isEmpty ? 'the owner' : first}',
                '+${full.length == 12 ? '${full.substring(0, 2)} ${full.substring(2, 7)} ${full.substring(7)}' : full}',
              ),
              tk2SheetRow(leading: tk2WhatsAppLogo(size: 28), title: 'WhatsApp', onTap: () => pick(whatsapp)),
              tk2SheetRow(
                leading: const Icon(Icons.sms_outlined, size: 28, color: AppColors.primaryDark),
                title: 'Text message',
                onTap: () => pick(sms),
              ),
              tk2SheetRow(
                leading: const Icon(Icons.copy_rounded, size: 28, color: AppColors.primaryDark),
                title: 'Copy link',
                sub: 'For WhatsApp Business, email or any app',
                onTap: () => pick(copy),
              ),
            ],
          ),
        ),
      );
    },
  );
}
