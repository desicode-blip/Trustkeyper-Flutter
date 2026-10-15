import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'document_request_widgets.dart';

Future<bool> confirmBrokerDocument(
  BuildContext context, {
  required String glyph,
  required String title,
  required String message,
  required String confirm,
  required String cancel,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x80172231),
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: destructive
                      ? AppColors.errorSoft
                      : AppColors.primarySoft,
                  child: DocumentGlyph(
                    glyph,
                    size: 28,
                    color: destructive
                        ? AppColors.error
                        : AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 24 / 17,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: destructive
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(
                      confirm,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(
                      cancel,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ) ??
    false;
