import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../features/document_requests/presentation/document_request_widgets.dart';

class CurrentLanguageLabel extends StatelessWidget {
  const CurrentLanguageLabel({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Current language: English',
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DocumentGlyph('globe', size: 16, color: AppColors.heading),
          SizedBox(width: 8),
          Text(
            'English',
            style: TextStyle(fontSize: 14, color: AppColors.heading),
          ),
        ],
      ),
    ),
  );
}
