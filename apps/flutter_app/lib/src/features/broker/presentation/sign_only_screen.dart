import 'package:flutter/material.dart';
import '../../../core/widgets/session_bound_screen.dart';
import '../../../core/widgets/approved_journey_widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../agreement_copies/agreement_copies.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../data/agreement_imports.dart';
import '../data/private_documents.dart';
import 'private_documents_screen.dart';
import 'signing_requests_screen.dart';

class SignOnlyScreen extends StatefulWidget {
  const SignOnlyScreen({
    this.gateway,
    this.picker,
    this.reviewer,
    this.offline = false,
    super.key,
  });
  final AgreementImportGateway? gateway;
  final Future<AgreementPageFile?> Function(bool camera)? picker;
  final Future<bool> Function(AgreementPageFile file)? reviewer;
  final bool offline;
  @override
  State<SignOnlyScreen> createState() => _SignOnlyScreenState();
}

class _SignerFields {
  _SignerFields(this.role);
  String role;
  final name = TextEditingController();
  final phone = TextEditingController();
  AgreementSigner get value => AgreementSigner(
    name: name.text.trim(),
    phone: phone.text.trim().startsWith('+')
        ? phone.text.replaceAll(RegExp(r'[\s()-]'), '')
        : '+91${phone.text.replaceAll(RegExp(r'\D'), '')}',
    role: role,
  );
  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _SignOnlyScreenState extends State<SignOnlyScreen> {
  late final gateway = widget.gateway ?? FirebaseAgreementImportGateway();
  final files = <AgreementPageFile>[];
  final reviewed = <String>{};
  final people = [_SignerFields('owner'), _SignerFields('tenant')];
  int step = 0;
  bool busy = false;
  bool locked = false;
  String? error;
  String? operationId;
  String? savedId;
  @override
  void dispose() {
    for (final person in people) {
      person.dispose();
    }
    super.dispose();
  }

  void _fail(Object failure) => setState(
    () => error = failure is DocumentFailure
        ? failure.message
        : 'This action was not confirmed. Keep your pages and retry.',
  );
  Future<void> _pick(bool camera, {int? replace}) async {
    if (busy || locked) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      AgreementPageFile? selected;
      if (widget.picker != null) {
        selected = await widget.picker!(camera);
      } else if (camera) {
        final file = await pickPrivateDocument(camera: true);
        if (file != null) {
          selected = AgreementPageFile(name: file.name, bytes: file.bytes);
        }
      } else {
        final file = await pickAgreementCopy();
        if (file != null) {
          selected = AgreementPageFile(name: file.name, bytes: file.bytes);
        }
      }
      if (selected == null || !mounted) return;
      selected.validate();
      if (camera && selected.contentType == 'application/pdf') {
        throw const DocumentFailure('Take one photo for each page.');
      }
      final next = [...files];
      if (replace != null) {
        next[replace] = selected;
      } else {
        next.add(selected);
      }
      if (next.length > 40 ||
          next.fold<int>(0, (sum, file) => sum + file.bytes.length) >
              AgreementCopyFile.maximumCopyBytes ||
          next.any((file) => file.contentType == 'application/pdf') &&
              next.length != 1) {
        throw const DocumentFailure(
          'Use one PDF or up to 40 page photos, within 20 MB in total.',
        );
      }
      if (next.map((file) => file.digest).toSet().length != next.length) {
        throw const DocumentFailure(
          'This page is already added. Choose the next page.',
        );
      }
      setState(() {
        files.clear();
        files.addAll(next);
        reviewed.remove(selected!.digest);
        step = 1;
      });
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _review(int index) async {
    if (busy || locked) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = files[index];
      final bool accepted;
      if (widget.reviewer != null) {
        accepted = await widget.reviewer!(file);
      } else {
        if (!context.mounted) return;
        accepted = await reviewPrivateDocument(
          context,
          file,
          upload: true,
          selectionOnly: true,
          reviewTitle: file.contentType == 'application/pdf'
              ? 'Check every page'
              : 'Check page ${index + 1}',
          instructions:
              'Read the full page. Check names, amounts and all signatures. If text is blurry or cut off, cancel and replace the page. No details are automatically extracted.',
        );
      }
      if (mounted) {
        setState(() {
          if (accepted) {
            reviewed.add(file.digest);
          } else {
            reviewed.remove(file.digest);
          }
        });
      }
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _next() {
    try {
      if (step == 1 &&
          (files.isEmpty ||
              files.any((file) => !reviewed.contains(file.digest)))) {
        throw const DocumentFailure(
          'Open and check every page before continuing. Replace anything blurry or cut off.',
        );
      }
      if (step == 2) {
        validateSigningRequest(
          files,
          people.map((person) => person.value).toList(),
        );
      }
      setState(() {
        step++;
        error = null;
      });
    } catch (failure) {
      _fail(failure);
    }
  }

  Future<void> _send() async {
    if (busy) return;
    setState(() {
      busy = true;
      locked = true;
      error = null;
    });
    operationId ??= importOperationId();
    try {
      final id = await gateway.send(
        files,
        people.map((person) => person.value).toList(),
        operationId!,
      );
      if (mounted) {
        setState(() {
          savedId = id;
          step = 4;
        });
      }
    } catch (failure) {
      if (mounted) _fail(failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _back() {
    if (busy) return;
    if (step > 0 && step < 4 && !locked) {
      setState(() {
        step--;
        error = null;
      });
    } else {
      Navigator.maybePop(context);
    }
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
  Widget _heading(String title, String subtitle) => ApprovedJourneyHeading(
    title: title,
    subtitle: subtitle,
    onBack: busy ? null : _back,
  );
  Widget _requests({String? highlight}) {
    final screen = SigningRequestsScreen(
      gateway: gateway,
      highlightId: highlight,
      offline: widget.offline,
    );
    return widget.gateway != null ? screen : SessionBoundScreen(child: screen);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ApprovedAuthScaffold(
          showBack: false,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.offline)
                  const Text(
                    'OFFLINE TEST · synthetic pages, no legal signing',
                  ),
                LinearProgressIndicator(
                  value: step >= 4 ? 1 : (step <= 1 ? 1 : step) / 3,
                  minHeight: 5,
                  color: AppColors.primary,
                  backgroundColor: AppColors.primarySoft,
                ),
                const SizedBox(height: 12),
                Text(
                  step >= 4
                      ? 'Done! We have your agreement'
                      : 'Step ${step <= 1 ? 1 : step} of 3 · ${step <= 1
                            ? 'Agreement'
                            : step == 2
                            ? 'People'
                            : 'Send'}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          footer: Row(
            children: [
              TextButton(
                onPressed: busy ? null : _back,
                child: const Text('‹ Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: busy
                      ? 'Please wait…'
                      : step == 3
                      ? (locked ? 'Retry same send' : 'Send for signing')
                      : step == 4
                      ? 'See progress'
                      : 'Next',
                  onPressed: busy || step == 0
                      ? null
                      : step == 3
                      ? _send
                      : step == 4
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _requests(highlight: savedId),
                          ),
                        )
                      : _next,
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (step == 0) ...[
                _heading(
                  'Add your agreement',
                  'Add all the pages. We will get it signed.',
                ),
                ApprovedJourneyAction(
                  title: 'Take photos',
                  subtitle: 'One photo for each page',
                  icon: Icons.camera_alt_outlined,
                  onTap: busy ? null : () => _pick(true),
                ),
                ApprovedJourneyAction(
                  title: 'Choose PDF file',
                  subtitle: 'From your phone or WhatsApp',
                  icon: Icons.description_outlined,
                  purple: true,
                  onTap: busy ? null : () => _pick(false),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How it works',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final item in [
                        (
                          1,
                          Icons.description_outlined,
                          'Add the agreement pages',
                        ),
                        (2, Icons.people_outline, 'Tell us who will sign'),
                        (
                          3,
                          Icons.approval_outlined,
                          'We get stamp paper and send it to everyone to sign',
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                child: Text('${item.$1}'),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  item.$2,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.$3,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => _requests()),
                        ),
                  child: const Text('See saved signing requests'),
                ),
              ],
              if (step == 1) ...[
                _heading(
                  'Check your pages',
                  'Every page must be easy to read.',
                ),
                for (var index = 0; index < files.length; index++)
                  _card(
                    Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            reviewed.contains(files[index].digest)
                                ? Icons.check_circle
                                : Icons.description_outlined,
                            color: reviewed.contains(files[index].digest)
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                          title: Text(
                            files[index].contentType == 'application/pdf'
                                ? files[index].name
                                : 'Page ${index + 1}',
                          ),
                          subtitle: Text(
                            reviewed.contains(files[index].digest)
                                ? 'You checked every page'
                                : 'Open and check · unread pages cannot be sent',
                          ),
                          onTap: busy ? null : () => _review(index),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _pick(
                                      files[index].contentType !=
                                          'application/pdf',
                                      replace: index,
                                    ),
                              child: const Text('Replace'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      reviewed.remove(files[index].digest);
                                      files.removeAt(index);
                                    }),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (files.isEmpty ||
                    files.every(
                      (file) => file.contentType != 'application/pdf',
                    ))
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _pick(true),
                    icon: const Icon(Icons.add),
                    label: const Text('Add page'),
                  ),
                if (files.isEmpty)
                  TextButton(
                    onPressed: busy ? null : () => _pick(false),
                    child: const Text('Choose PDF file'),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Tap a page to see it big or take it again. Keep the phone still and use good light.',
                ),
              ],
              if (step == 2) ...[
                _heading(
                  'Who will sign?',
                  'Add the names exactly as written in the agreement, and their mobile numbers.',
                ),
                for (var index = 0; index < people.length; index++)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Signer ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: people[index].name,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: people[index].role,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: const ['owner', 'tenant', 'witness']
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(role),
                                ),
                              )
                              .toList(),
                          onChanged: (role) {
                            if (role != null) people[index].role = role;
                          },
                        ),
                        const SizedBox(height: 12),
                        ApprovedPhoneField(controller: people[index].phone),
                        if (people.length > 2)
                          TextButton(
                            onPressed: () => setState(() {
                              people.removeAt(index).dispose();
                            }),
                            child: const Text('Remove signer'),
                          ),
                      ],
                    ),
                  ),
                if (people.length < 40)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      people.add(_SignerFields('witness'));
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Add another person'),
                  ),
              ],
              if (step == 3) ...[
                _heading('Check and send', 'We will do the rest for you.'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Your agreement',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        files.length == 1 &&
                                files.first.contentType == 'application/pdf'
                            ? '1 PDF · every page reviewed'
                            : '${files.length} pages · reviewed',
                      ),
                      TextButton(
                        onPressed: locked
                            ? null
                            : () => setState(() => step = 1),
                        child: const Text('See pages'),
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Will sign (${people.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      for (final person in people)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline),
                          title: Text('${person.value.name} · ${person.role}'),
                          subtitle: Text(person.value.phone),
                        ),
                      TextButton(
                        onPressed: locked
                            ? null
                            : () => setState(() => step = 2),
                        child: const Text('Change people'),
                      ),
                    ],
                  ),
                ),
                _card(
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What we will do',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Buy stamp paper\nPrint your agreement on it\nSend it to everyone to sign',
                      ),
                    ],
                  ),
                ),
                const Text(
                  'You can see progress on Home. Sending pages does not mean anyone has signed yet.',
                ),
                if (locked && !busy)
                  TextButton(
                    onPressed: () => setState(() {
                      locked = false;
                      operationId = null;
                      step = 1;
                      error = null;
                    }),
                    child: const Text(
                      'Change pages or people · start a new send',
                    ),
                  ),
              ],
              if (step == 4) ...[
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 68,
                ),
                const SizedBox(height: 20),
                _heading(
                  'Done! We have your agreement',
                  'Our team will get it ready and send it to everyone to sign.',
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Agreement received',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${people.length} people · receipt confirmed by the server',
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Buying stamp paper · next\nSent to everyone to sign · after preparation',
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/broker'),
                  child: const Text('Go to home'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
