import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../data/linkedin_profile.dart';

class LinkedInProfileFields extends StatefulWidget {
  const LinkedInProfileFields({
    required this.name,
    required this.onSave,
    this.initial = '',
    this.recipient = false,
    super.key,
  });
  final String name, initial;
  final bool recipient;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<LinkedInProfileFields> createState() => _LinkedInProfileFieldsState();
}

class _LinkedInProfileFieldsState extends State<LinkedInProfileFields> {
  late final controller = TextEditingController(text: widget.initial);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save(bool skip) async {
    final profile = normalizeLinkedInProfile(controller.text);
    if (!skip && profile == null) {
      setState(() => error = linkedInProfileError);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave({'url': skip ? '' : profile!, 'skipped': skip});
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save this profile. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        widget.recipient
            ? 'Add LinkedIn profile'
            : 'Add ${widget.name.split(' ').first}’s LinkedIn',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.heading,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.recipient
            ? 'Optional. It helps the owner know you.'
            : 'Optional. It helps the owner know ${widget.name.split(' ').first}. You can skip and ask them later.',
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.muted,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: controller,
        enabled: !busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Profile link',
          hintText: 'linkedin.com/in/name',
          errorText: error,
          errorMaxLines: 3,
        ),
        onChanged: (_) {
          if (error != null) setState(() => error = null);
        },
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: busy ? null : () => _save(false),
          child: const Text('Save'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: busy ? null : () => _save(true),
        child: const Text('Skip'),
      ),
    ],
  );
}
