import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/trustkeyper_ui.dart';
import '../../../core/widgets/workflow_unavailable.dart';

class JourneyStep {
  const JourneyStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.items = const [],
    this.amount,
    this.amountLabel,
    this.amountWords,
    this.note,
    this.action = 'Continue',
    this.tone = JourneyTone.normal,
    this.fields = const [],
    this.choices = const [],
    this.attachment = JourneyAttachment.none,
    this.confirmationLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> items;
  final String? amount;
  final String? amountLabel;
  final String? amountWords;
  final String? note;
  final String action;
  final JourneyTone tone;
  final List<JourneyField> fields;
  final List<String> choices;
  final JourneyAttachment attachment;
  final String? confirmationLabel;
}

enum JourneyTone { normal, success, warning, danger }

enum JourneyFieldType { text, phone, number, date, multiline }

enum JourneyAttachment { none, document, photo, both }

class JourneyField {
  const JourneyField({
    required this.label,
    this.hint,
    this.initialValue = '',
    this.type = JourneyFieldType.text,
    this.required = true,
  });

  final String label;
  final String? hint;
  final String initialValue;
  final JourneyFieldType type;
  final bool required;
}

class GuidedJourneyScreen extends StatefulWidget {
  const GuidedJourneyScreen({
    required this.journeyTitle,
    required this.steps,
    this.completionRoute,
    this.previewOnly = false,
    super.key,
  });

  final String journeyTitle;
  final List<JourneyStep> steps;
  final String? completionRoute;
  final bool previewOnly;

  @override
  State<GuidedJourneyScreen> createState() => _GuidedJourneyScreenState();
}

class _GuidedJourneyScreenState extends State<GuidedJourneyScreen> {
  int index = 0;
  final Map<String, TextEditingController> controllers = {};
  final Map<int, String> selectedChoices = {};
  final Map<int, String> selectedAttachments = {};
  final Set<int> confirmedSteps = {};

  JourneyStep get step => widget.steps[index];

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void next() {
    final missingField = step.fields.any((field) {
      if (!field.required) return false;
      return _controllerFor(field).text.trim().isEmpty;
    });
    if (missingField) {
      _message('Complete the required details to continue.');
      return;
    }
    if (step.choices.isNotEmpty && selectedChoices[index] == null) {
      _message('Choose one option to continue.');
      return;
    }
    if (step.attachment != JourneyAttachment.none &&
        selectedAttachments[index] == null) {
      _message('Add the requested file or photo to continue.');
      return;
    }
    if (step.confirmationLabel != null && !confirmedSteps.contains(index)) {
      _message('Confirm the checkbox to continue.');
      return;
    }
    if (index < widget.steps.length - 1) {
      setState(() => index += 1);
      return;
    }
    if (widget.completionRoute != null) {
      context.go(widget.completionRoute!);
    } else if (context.canPop()) {
      context.pop();
    }
  }

  TextEditingController _controllerFor(JourneyField field) {
    final key = '$index:${field.label}';
    return controllers.putIfAbsent(
      key,
      () => TextEditingController(text: field.initialValue),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDocument() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null || !mounted) return;
    setState(() => selectedAttachments[index] = file.name);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;
    setState(() => selectedAttachments[index] = image.name);
  }

  Future<void> _pickDate(JourneyField field) async {
    final chosen = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (chosen == null) return;
    _controllerFor(field).text =
        '${chosen.day.toString().padLeft(2, '0')}/${chosen.month.toString().padLeft(2, '0')}/${chosen.year}';
    setState(() {});
  }

  void back() {
    if (index > 0) {
      setState(() => index -= 1);
    } else if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.previewOnly) {
      return WorkflowUnavailable(
        title: widget.journeyTitle,
        returnRoute: widget.completionRoute ?? '/roles',
      );
    }
    final tone = switch (step.tone) {
      JourneyTone.normal => AppColors.primary,
      JourneyTone.success => AppColors.success,
      JourneyTone.warning => AppColors.warning,
      JourneyTone.danger => AppColors.error,
    };
    final toneSoft = switch (step.tone) {
      JourneyTone.normal => AppColors.primarySoft,
      JourneyTone.success => AppColors.successSoft,
      JourneyTone.warning => AppColors.warningSoft,
      JourneyTone.danger => AppColors.errorSoft,
    };

    return TkPage(
      step: 'DESIGN PREVIEW ONLY · ${index + 1} of ${widget.steps.length}',
      onBack: back,
      showHelp: true,
      title: step.title,
      subtitle: step.subtitle,
      bottom: TkPrimaryButton(label: step.action, onPressed: next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TkProgress(value: (index + 1) / widget.steps.length),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: toneSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, color: tone, size: 44),
            ),
          ),
          if (step.amount != null) ...[
            const SizedBox(height: 24),
            TkAmount(
              label: step.amountLabel ?? 'Amount',
              amount: step.amount!,
              words: step.amountWords ?? '',
            ),
          ],
          if (step.fields.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final field in step.fields) ...[
              TextField(
                controller: _controllerFor(field),
                readOnly: field.type == JourneyFieldType.date,
                onTap: field.type == JourneyFieldType.date
                    ? () => _pickDate(field)
                    : null,
                keyboardType: switch (field.type) {
                  JourneyFieldType.phone => TextInputType.phone,
                  JourneyFieldType.number => TextInputType.number,
                  JourneyFieldType.multiline => TextInputType.multiline,
                  _ => TextInputType.text,
                },
                minLines: field.type == JourneyFieldType.multiline ? 3 : 1,
                maxLines: field.type == JourneyFieldType.multiline ? 5 : 1,
                decoration: InputDecoration(
                  labelText: '${field.label}${field.required ? ' *' : ''}',
                  hintText: field.hint,
                  suffixIcon: field.type == JourneyFieldType.date
                      ? const Icon(Icons.calendar_month_outlined)
                      : null,
                ),
              ),
              const SizedBox(height: 14),
            ],
          ],
          if (step.choices.isNotEmpty) ...[
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final choice in step.choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: selectedChoices[index] == choice,
                    onSelected: (_) =>
                        setState(() => selectedChoices[index] = choice),
                  ),
              ],
            ),
          ],
          if (step.items.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < step.items.length;
                    itemIndex++
                  ) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          step.tone == JourneyTone.success
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_checked_rounded,
                          color: tone,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(step.items[itemIndex])),
                      ],
                    ),
                    if (itemIndex != step.items.length - 1)
                      const Divider(height: 26),
                  ],
                ],
              ),
            ),
          ],
          if (step.attachment != JourneyAttachment.none) ...[
            const SizedBox(height: 22),
            if (selectedAttachments[index] case final attachment?)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text(attachment)),
                    IconButton(
                      onPressed: () =>
                          setState(() => selectedAttachments.remove(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                if (step.attachment != JourneyAttachment.photo)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDocument,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Choose file'),
                    ),
                  ),
                if (step.attachment == JourneyAttachment.both)
                  const SizedBox(width: 10),
                if (step.attachment != JourneyAttachment.document)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take photo'),
                    ),
                  ),
              ],
            ),
          ],
          if (step.confirmationLabel != null) ...[
            const SizedBox(height: 22),
            CheckboxListTile(
              value: confirmedSteps.contains(index),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(step.confirmationLabel!),
              onChanged: (value) => setState(() {
                if (value == true) {
                  confirmedSteps.add(index);
                } else {
                  confirmedSteps.remove(index);
                }
              }),
            ),
          ],
          if (step.note != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: toneSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: tone),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step.note!)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
