import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../document_requests/presentation/document_request_widgets.dart';

class PartyDocumentHeader extends StatelessWidget {
  const PartyDocumentHeader({
    required this.name,
    required this.contact,
    required this.complete,
    required this.onEdit,
    super.key,
  });
  final String name, contact;
  final bool complete;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primarySoft,
          child: Text(
            name
                .trim()
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)
                .take(2)
                .map((word) => word[0])
                .join()
                .toUpperCase(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 20 / 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.heading,
                      ),
                    ),
                  ),
                  if (complete) ...[
                    const SizedBox(width: 10),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.successSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DocumentGlyph(
                            'check',
                            size: 14,
                            color: AppColors.success,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'All done',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: onEdit,
                    tooltip: 'Edit person',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      fixedSize: const Size(34, 34),
                      padding: const EdgeInsets.all(8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const DocumentGlyph(
                      'pencil',
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                contact,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 18 / 14,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
