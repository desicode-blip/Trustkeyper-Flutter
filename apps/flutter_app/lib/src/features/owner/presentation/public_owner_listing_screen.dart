import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../../broker/data/private_documents.dart';
import '../../participants/presentation/participant_workspace_screen.dart';
import '../data/owner_lifecycle.dart';

abstract interface class ListingPhoneProof {
  Future<void> send(String phone);
  Future<void> confirm(String code);
}

class FirebaseListingPhoneProof implements ListingPhoneProof {
  FirebaseListingPhoneProof({FirebaseAuth? auth})
    : auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth auth;
  String? verificationId;
  PhoneAuthCredential? automatic;
  String? phone;
  @override
  Future<void> send(String phone) async {
    if (!RegExp(r'^\+91\d{10}$').hasMatch(phone)) {
      throw const DocumentFailure('Enter a ten-digit Indian phone number.');
    }
    this.phone = phone;
    verificationId = null;
    automatic = null;
    try {
      if (kIsWeb) {
        verificationId = (await auth.signInWithPhoneNumber(
          phone,
        )).verificationId;
      } else {
        final sent = Completer<void>();
        await auth.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (value) {
            automatic = value;
            if (!sent.isCompleted) sent.complete();
          },
          verificationFailed: (error) {
            if (!sent.isCompleted) {
              sent.completeError(
                DocumentFailure(error.message ?? 'The code was not sent.'),
              );
            }
          },
          codeSent: (value, _) {
            verificationId = value;
            if (!sent.isCompleted) sent.complete();
          },
          codeAutoRetrievalTimeout: (value) {
            verificationId = value;
            if (!sent.isCompleted) sent.complete();
          },
        );
        await sent.future.timeout(const Duration(seconds: 50));
      }
    } on FirebaseAuthException catch (error) {
      throw DocumentFailure(error.message ?? 'The code was not sent.');
    } on TimeoutException {
      throw const DocumentFailure('The request timed out. Try again.');
    }
  }

  @override
  Future<void> confirm(String code) async {
    if (verificationId == null && automatic == null) {
      throw const DocumentFailure('Request a new code.');
    }
    if (automatic == null && !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const DocumentFailure('Enter the six-digit code.');
    }
    try {
      final result = await auth.signInWithCredential(
        automatic ??
            PhoneAuthProvider.credential(
              verificationId: verificationId!,
              smsCode: code,
            ),
      );
      if (result.user?.phoneNumber != phone) {
        throw const DocumentFailure('The verified phone did not match.');
      }
    } on FirebaseAuthException catch (error) {
      throw DocumentFailure(error.message ?? 'That code was not accepted.');
    }
  }
}

class PublicOwnerListingScreen extends StatefulWidget {
  const PublicOwnerListingScreen({
    required this.id,
    this.gateway,
    this.proof,
    super.key,
  });
  final String id;
  final OwnerLifecycleGateway? gateway;
  final ListingPhoneProof? proof;
  @override
  State<PublicOwnerListingScreen> createState() =>
      _PublicOwnerListingScreenState();
}

class _PublicOwnerListingScreenState extends State<PublicOwnerListingScreen> {
  late final gateway = widget.gateway ?? FirebaseOwnerLifecycleGateway();
  late final proof = widget.proof ?? FirebaseListingPhoneProof();
  final form = GlobalKey<FormState>();
  final phone = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  final household = TextEditingController(text: '1');
  final work = TextEditingController();
  final photos = <int, Future<Image>>{};
  Map<String, dynamic>? listing;
  Map<String, dynamic>? receipt;
  DateTime moveIn = DateTime.now().add(const Duration(days: 7));
  DateTime? resendAt;
  String page = 'listing';
  bool consent = false;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final value in [phone, code, name, household, work]) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DocumentFailure
              ? failure.message
              : 'This request was not confirmed. Retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _load() => _run(() async {
    final data = await gateway.readPublic(widget.id);
    if (mounted) {
      setState(() {
        listing = data;
        photos.clear();
      });
    }
  });
  Future<Image> _image(int index) => photos.putIfAbsent(index, () async {
    final file = await gateway.readPublicPhoto(widget.id, index);
    return Image.memory(file.bytes, fit: BoxFit.cover);
  });
  Future<void> _send() => _run(() async {
    if (!consent) {
      throw const DocumentFailure(
        'Confirm use of your tenant phone before requesting a code.',
      );
    }
    if (resendAt != null && DateTime.now().isBefore(resendAt!)) {
      throw const DocumentFailure(
        'Wait 60 seconds before requesting another code.',
      );
    }
    final number = phone.text.replaceAll(RegExp(r'\D'), '');
    if (number.length != 10) {
      throw const DocumentFailure('Enter your ten-digit phone number.');
    }
    await proof.send('+91$number');
    if (mounted) {
      setState(() {
        page = 'code';
        code.clear();
        resendAt = DateTime.now().add(const Duration(seconds: 60));
      });
    }
  });
  Future<void> _confirm() => _run(() async {
    await proof.confirm(code.text);
    final existing = await gateway.receipt(widget.id);
    if (existing['received'] == true) {
      if (mounted) {
        setState(() {
          receipt = existing;
          page = 'received';
        });
      }
      return;
    }
    await gateway.enquire(widget.id, {'action': 'view'});
    if (mounted) {
      setState(() => page = 'details');
    }
  });
  Future<void> _enquire() => _run(() async {
    if (!form.currentState!.validate()) {
      return;
    }
    await gateway.enquire(widget.id, {
      'action': 'interest',
      'name': name.text.trim(),
      'household': int.parse(household.text),
      'work': work.text.trim(),
      'moveIn': DateFormat('yyyy-MM-dd').format(moveIn),
    });
    if (mounted) {
      setState(() => page = 'received');
    }
  });
  Future<void> _receipt() => _run(() async {
    final current = await gateway.receipt(widget.id);
    if (mounted) setState(() => receipt = current);
  });
  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: AppBrand(height: 28)),
    ),
    footer: listing == null && page == 'listing'
        ? null
        : switch (page) {
            'listing' => PrimaryButton(
              label: 'I am interested',
              onPressed: busy ? null : () => setState(() => page = 'phone'),
            ),
            'phone' => PrimaryButton(
              label: 'Send OTP',
              onPressed: busy ? null : _send,
            ),
            'code' => PrimaryButton(
              label: 'Verify phone',
              onPressed: busy ? null : _confirm,
            ),
            'details' => PrimaryButton(
              label: 'Send to TrustKeyper',
              onPressed: busy ? null : _enquire,
            ),
            _ => null,
          },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: AppColors.error)),
        if (listing == null)
          TextButton(
            onPressed: busy ? null : _load,
            child: const Text('Refresh listing'),
          ),
        if (page == 'listing')
          TextButton(
            onPressed: busy ? null : () => setState(() => page = 'phone'),
            child: const Text('Check my existing enquiry'),
          ),
        if (listing != null && page == 'listing') ...[
          Text(
            listing!['title'] as String,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          Text(
            listing!['locality'] as String,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < (listing!['photoCount'] as int); index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 190,
                  child: FutureBuilder<Image>(
                    future: _image(index),
                    builder: (context, snapshot) => snapshot.hasData
                        ? snapshot.data!
                        : Center(
                            child: snapshot.hasError
                                ? TextButton(
                                    onPressed: () =>
                                        setState(() => photos.remove(index)),
                                    child: const Text('Retry photo'),
                                  )
                                : const CircularProgressIndicator(),
                          ),
                  ),
                ),
              ),
            ),
          Text(
            '${workspaceMoney(listing!['rentPaise'] as int)} / month',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '${listing!['rooms']} · ${listing!['furnishing']} furnished\n${listing!['whoCanStay']} · From ${listing!['availableFrom']}',
          ),
          Text(
            'Deposit ${workspaceMoney(listing!['depositPaise'] as int)}\nMaintenance ${workspaceMoney(listing!['maintenancePaise'] as int)}',
          ),
          const SizedBox(height: 20),
          const Text(
            'Your details go privately to TrustKeyper and the owner. No app installation is needed. Identity verification happens separately.',
          ),
        ],
        if (page == 'phone') ...[
          const Text(
            'Your phone',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              prefixText: '+91 ',
              labelText: 'Tenant phone',
            ),
          ),
          CheckboxListTile(
            value: consent,
            onChanged: busy
                ? null
                : (value) => setState(() => consent = value == true),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'This is my tenant phone. Verifying it may switch the account in this browser. I agree that TrustKeyper and the owner can contact me about this enquiry.',
            ),
          ),
        ],
        if (page == 'code') ...[
          const Text(
            'Verify your phone',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          ApprovedOtpInput(controller: code, enabled: !busy),
          TextButton(
            onPressed: busy ? null : _send,
            child: const Text('Send again · after 60 seconds'),
          ),
        ],
        if (page == 'details')
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tell us about you',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                TextFormField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name'
                      : null,
                ),
                TextFormField(
                  controller: household,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'People who will stay',
                  ),
                  validator: (value) =>
                      (int.tryParse(value ?? '') ?? 0) < 1 ||
                          (int.tryParse(value ?? '') ?? 21) > 20
                      ? 'Enter 1–20 people'
                      : null,
                ),
                TextFormField(
                  controller: work,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Work / household description',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter a description'
                      : null,
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final day = await showDatePicker(
                            context: context,
                            initialDate: moveIn,
                            firstDate: DateUtils.dateOnly(DateTime.now()),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (day != null && mounted) {
                            setState(() => moveIn = day);
                          }
                        },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    'Move in · ${DateFormat('d MMM yyyy').format(moveIn)}',
                  ),
                ),
              ],
            ),
          ),
        if (page == 'received') ...[
          const Icon(Icons.check_circle, size: 88, color: AppColors.success),
          const SizedBox(height: 20),
          const Text(
            'Your interest is received',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          Text(
            receipt?['status'] == 'chosen'
                ? 'You have been selected. The listing is paused; tenancy starts only after the actual agreement and move-in steps.'
                : receipt?['status'] == 'declined'
                ? 'The owner did not select this enquiry. Contact the manager if you need help finding another home.'
                : 'TrustKeyper will contact you to arrange a visit and check your identity. You are not yet selected; this enquiry does not create an agreement or payment.',
          ),
          if (receipt?['received'] == true) ...[
            Text(
              'Current status · ${receipt!['status'].toString().replaceAll('_', ' ')}',
            ),
            Text(
              receipt!['identityChecked'] == true
                  ? 'Identity check completed'
                  : 'Identity check pending',
            ),
            if (receipt!['visit'] != null)
              Text(
                'Confirmed visit · ${receipt!['visit']['day']} · ${receipt!['visit']['slot']}',
              ),
            if (receipt!['managerName'] != null)
              Text('Manager · ${receipt!['managerName']}'),
            if (receipt!['managerPhone'] != null)
              SelectableText(receipt!['managerPhone'] as String),
            if (receipt!['agreementReady'] == true)
              const Text(
                'Your agreement is prepared. Ask the manager for your private agreement-review link.',
              ),
          ],
          TextButton(
            onPressed: busy ? null : _receipt,
            child: const Text('Check current enquiry status'),
          ),
        ],
      ],
    ),
  );
}
