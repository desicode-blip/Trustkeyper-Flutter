import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';

class AccountDetailField extends StatefulWidget {
  const AccountDetailField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.enabled,
    required this.limit,
    this.validator,
    this.keyboard,
    this.changed,
    this.hint,
    super.key,
  });
  final String label;
  final Widget icon;
  final TextEditingController controller;
  final bool enabled;
  final int limit;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final ValueChanged<String>? changed;
  final String? hint;
  @override
  State<AccountDetailField> createState() => _AccountDetailFieldState();
}

class _AccountDetailFieldState extends State<AccountDetailField> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: widget.controller.text,
    validator: (_) => widget.validator?.call(widget.controller.text),
    builder: (field) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            onFocusChange: (value) => setState(() => focused = value),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: field.hasError
                      ? AppColors.error
                      : focused
                      ? AppColors.primary
                      : AppColors.border,
                  width: focused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  widget.icon,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: AppColors.muted,
                          ),
                        ),
                        TextField(
                          key: ValueKey('account-field:${widget.label}'),
                          controller: widget.controller,
                          enabled: widget.enabled,
                          keyboardType: widget.keyboard,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(widget.limit),
                          ],
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.3,
                            color: AppColors.heading,
                          ),
                          onChanged: (value) {
                            field.didChange(value);
                            widget.changed?.call(value);
                          },
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: widget.hint,
                            hintStyle: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 17,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 14),
              child: Text(
                field.errorText!,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
            ),
        ],
      ),
    ),
  );
}
