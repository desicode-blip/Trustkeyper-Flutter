import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_brand.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../../broker/data/agreement_imports.dart';
import '../../broker/data/private_documents.dart';
import '../../broker/data/agreement_draft.dart';
import '../../broker/presentation/private_documents_screen.dart';
import '../../participants/presentation/participant_workspace_screen.dart';
import '../data/owner_properties.dart';
import '../data/owner_lifecycle.dart';

class OwnerLifecycleScreen extends StatefulWidget {
  const OwnerLifecycleScreen({
    required this.property,
    this.gateway,
    this.properties,
    this.proof,
    this.documentReviewer,
    this.photoReader,
    this.onHelp,
    this.offline = false,
    super.key,
  });
  final OwnerPropertyRecord property;
  final OwnerLifecycleGateway? gateway;
  final OwnerPropertyGateway? properties;
  final OwnerContractPhoneProof? proof;
  final Future<bool> Function(AgreementPageFile)? documentReviewer;
  final Future<AgreementPageFile> Function(int)? photoReader;
  final VoidCallback? onHelp;
  final bool offline;
  @override
  State<OwnerLifecycleScreen> createState() => _OwnerLifecycleScreenState();
}

class _OwnerLifecycleScreenState extends State<OwnerLifecycleScreen> {
  late OwnerPropertyRecord property = widget.property;
  late final gateway = widget.gateway ?? FirebaseOwnerLifecycleGateway();
  late final properties = widget.properties ?? FirebaseOwnerPropertyGateway();
  late final proof = widget.proof ?? FirebaseOwnerContractPhoneProof();
  final code = TextEditingController();
  final title = TextEditingController();
  final locality = TextEditingController();
  String page = 'fee';
  String filter = 'liked';
  String? candidateId;
  String? challengeId;
  String? error;
  bool busy = false;
  bool readTerms = false;
  bool acceptTerms = false;
  bool publicApproved = false;
  DateTime? resendAt;
  Map<String, dynamic> get details => property.details;
  Map<String, dynamic> get contract =>
      Map<String, dynamic>.from(property.data['contract'] as Map? ?? {});
  Map<String, dynamic> get listing =>
      Map<String, dynamic>.from(property.data['listing'] as Map? ?? {});
  Map<String, dynamic> get candidates =>
      Map<String, dynamic>.from(property.data['candidates'] as Map? ?? {});
  Map<String, dynamic> get candidate =>
      Map<String, dynamic>.from(candidates[candidateId] as Map? ?? {});
  String get publicLink =>
      'https://trustkeyper.web.app/#/listing/${property.id}';
  String get planName => property.data['plan'] == 'full_service'
      ? 'We do it all'
      : 'Do it yourself';
  int get feeBps => (property.data['feeOffer'] as Map?)?['feeBps'] as int? ?? 0;
  String get fee => '${NumberFormat('0.##').format(feeBps / 100)}%';
  String get monthlyFee =>
      workspaceMoney(((details['rentPaise'] as int) * feeBps + 5000) ~/ 10000);
  List<MapEntry<String, dynamic>> get interested => candidates.entries
      .where(
        (entry) => [
          'interested',
          'visit_confirmed',
          'chosen',
        ].contains((entry.value as Map)['status']),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _restore() {
    page = property.status == 'tenant_chosen'
        ? 'chosen'
        : property.status == 'listing_live'
        ? 'live'
        : ['plan_active', 'listing_paused'].contains(property.status)
        ? 'active'
        : 'fee';
    candidateId = property.data['chosenTenantId'] as String?;
    title.text =
        listing['title'] as String? ??
        '${details['rooms']} · ${details['homeType']}';
    locality.text = listing['locality'] as String? ?? '';
  }

  @override
  void dispose() {
    code.dispose();
    title.dispose();
    locality.dispose();
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
              : 'This action was not confirmed. Refresh and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void _help() {
    if (widget.onHelp != null) {
      widget.onHelp!();
    } else {
      context.push('/owner/support');
    }
  }

  Future<void> _refresh() => _run(() async {
    final records = await properties.list();
    final latest = records
        .where((value) => value.id == property.id)
        .firstOrNull;
    if (latest == null) {
      throw const DocumentFailure('This property is no longer available.');
    }
    if (mounted) {
      setState(() {
        property = latest;
        challengeId = null;
        code.clear();
        readTerms = false;
        acceptTerms = false;
        _restore();
      });
    }
  });
  Future<void> _change(
    String action, [
    Map<String, dynamic> input = const {},
  ]) => _run(() async {
    final value = await gateway.change(property, action, input);
    if (mounted) {
      setState(() {
        property = OwnerPropertyRecord(value);
        if (action == 'choose_tenant') page = 'chosen';
      });
    }
  });
  Future<void> _readContract({bool signed = false}) => _run(() async {
    final previewContext = context;
    final file = await gateway.readContract(property, signed: signed);
    if (!previewContext.mounted) {
      return;
    }
    bool reviewed;
    if (widget.documentReviewer != null) {
      reviewed = await widget.documentReviewer!(file);
    } else {
      reviewed = await reviewPrivateDocument(
        previewContext,
        file,
        upload: !signed,
        selectionOnly: true,
        reviewTitle: signed
            ? 'Your signed owner contract'
            : 'Read your owner contract',
        confirmationLabel: 'I read every page',
        instructions:
            'Read every page and confirm the property, plan, fee and effective date. This review does not sign or upload anything.',
      );
    }
    if (mounted && reviewed && !signed) {
      setState(() => readTerms = true);
    }
  });
  Future<void> _sendCode() => _run(() async {
    if (!readTerms || !acceptTerms) {
      throw const DocumentFailure(
        'Read every page and agree to the current terms first.',
      );
    }
    if (resendAt != null && DateTime.now().isBefore(resendAt!)) {
      throw const DocumentFailure(
        'Wait 60 seconds before requesting another code.',
      );
    }
    final challenge = await gateway.change(property, 'begin_consent', {
      'operationId': importOperationId(),
    });
    challengeId = challenge['challengeId'] as String;
    await proof.sendCode();
    if (mounted) {
      setState(() {
        page = 'otp';
        code.clear();
        resendAt = DateTime.now().add(const Duration(seconds: 60));
      });
    }
  });
  Future<void> _confirmCode() => _run(() async {
    if (challengeId == null) {
      throw const DocumentFailure('Request a new code.');
    }
    await proof.confirmCode(code.text);
    final value = await gateway.change(property, 'confirm_consent', {
      'challengeId': challengeId,
      'readTerms': readTerms,
      'acceptTerms': acceptTerms,
    });
    if (mounted) {
      setState(() {
        property = OwnerPropertyRecord(value);
        page = 'fee';
        code.clear();
      });
    }
  });
  Future<void> _publish() => _run(() async {
    final value = await gateway.change(property, 'publish_listing', {
      'title': title.text.trim(),
      'locality': locality.text.trim(),
      'publicDetailsApproved': publicApproved,
      'publicPhotosApproved': publicApproved,
    });
    if (mounted) {
      setState(() {
        property = OwnerPropertyRecord(value);
        page = 'live';
      });
    }
  });
  Future<void> _photo(int index) => _run(() async {
    final file = widget.photoReader != null
        ? await widget.photoReader!(index)
        : await properties.readPhoto(property, index);
    if (mounted) {
      await reviewPrivateDocument(
        context,
        file,
        upload: false,
        selectionOnly: true,
        reviewTitle: 'Your listing photo',
      );
    }
  });
  Future<void> _addPhoto() => _run(() async {
    if (property.photos.length >= 5) {
      throw const DocumentFailure('Up to five photos are allowed.');
    }
    final file = await pickPrivateDocument();
    if (file == null || !mounted) {
      return;
    }
    if (file.contentType == 'application/pdf') {
      throw const DocumentFailure('Choose a JPG or PNG property photo.');
    }
    final reviewed = await reviewPrivateDocument(
      context,
      file,
      upload: true,
      selectionOnly: true,
      reviewTitle: 'Review your actual listing photo',
      instructions:
          'Use a clear property photo without people, identity documents, phone numbers or private details.',
    );
    if (!reviewed || !mounted) {
      return;
    }
    final existing = <AgreementPageFile>[];
    for (var index = 0; index < property.photos.length; index++) {
      existing.add(await properties.readPhoto(property, index));
    }
    existing.add(AgreementPageFile(name: file.name, bytes: file.bytes));
    final updated = await properties.uploadPhotos(
      property,
      existing,
      importOperationId(),
    );
    if (mounted) {
      setState(() {
        property = updated;
        publicApproved = false;
      });
    }
  });
  Future<void> _visit() async {
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 59)),
    );
    if (day == null || !mounted) {
      return;
    }
    final slot = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Visit time'),
        children: ['10:00–12:00', '12:00–14:00', '16:00–18:00']
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, value),
                child: Text(value),
              ),
            )
            .toList(),
      ),
    );
    if (slot != null) {
      await _change('visit', {
        'candidateId': candidateId,
        'day': DateFormat('yyyy-MM-dd').format(day),
        'slot': slot,
      });
    }
  }

  Widget _card(Widget child, {Color color = Colors.white}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: color == Colors.white
          ? Border.all(color: AppColors.border)
          : null,
    ),
    child: child,
  );
  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  Widget _heading(String heading, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 16, color: AppColors.muted),
        ),
      ],
    ),
  );
  Widget _helpBar(String heading) => _card(
    Row(
      children: [
        const Icon(Icons.headset_mic_outlined, color: AppColors.success),
        const SizedBox(width: 12),
        Expanded(child: Text(heading)),
        TextButton(
          onPressed: busy ? null : _help,
          child: const Text('Call me'),
        ),
      ],
    ),
    color: const Color(0xFFE6F7EF),
  );
  List<Widget> _fee() => [
    _heading(
      property.status == 'contract_accepted'
          ? 'Agreement confirmed'
          : 'Your fee',
      property.status == 'contract_accepted'
          ? 'Your consent is saved. The signed original will appear here when ready.'
          : 'Your free home check is complete.',
    ),
    _card(
      Column(
        children: [
          Text(
            fee,
            style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800),
          ),
          const Text('of rent', style: TextStyle(color: AppColors.primary)),
          const SizedBox(height: 10),
          Text(
            '$monthlyFee a month',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${rupeesInWords(((details['rentPaise'] as int) * feeBps + 5000) ~/ 10000)} a month',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.success),
          ),
        ],
      ),
      color: AppColors.primarySoft,
    ),
    const Text(
      'Why this fee?',
      style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    _card(
      Column(
        children: [
          _row(
            Icons.bed_outlined,
            'Home',
            '${details['rooms']} · ${details['furnishing']} furnished',
          ),
          const Divider(height: 1),
          _row(Icons.shield_outlined, 'Plan', planName),
          const Divider(height: 1),
          _row(
            Icons.currency_rupee,
            'Rent',
            workspaceMoney(details['rentPaise'] as int),
          ),
          const Divider(height: 1),
          _row(
            Icons.calendar_month_outlined,
            'Effective from',
            property.data['feeOffer']['effectiveFrom'] as String,
          ),
        ],
      ),
    ),
    if ((property.data['feeOffer']['notes'] as String? ?? '').isNotEmpty)
      Text(property.data['feeOffer']['notes'] as String),
    TextButton.icon(
      onPressed: busy || contract['sourceFile'] == null
          ? null
          : () => _readContract(),
      icon: const Icon(Icons.description_outlined),
      label: Text(
        contract['sourceFile'] == null
            ? 'Your full contract is being prepared'
            : 'Read full contract (${contract['sourceFile']['pageCount']} pages)',
      ),
    ),
    if (property.status != 'contract_accepted') ...[
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: readTerms,
        onChanged: null,
        title: const Text('I read every page of the current contract'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: acceptTerms,
        onChanged: busy
            ? null
            : (value) => setState(() => acceptTerms = value == true),
        title: const Text('I agree to this plan, fee and effective date'),
      ),
    ],
    TextButton.icon(
      onPressed: busy ? null : _help,
      icon: const Icon(Icons.chat_bubble_outline),
      label: const Text('I have a question about the fee'),
    ),
  ];
  List<Widget> _otp() => [
    _heading(
      'Sign with OTP',
      'A new six-digit code was requested for ${proof.phone}.',
    ),
    ApprovedOtpInput(controller: code, enabled: !busy),
    const SizedBox(height: 12),
    TextButton(
      onPressed: busy ? null : _sendCode,
      child: const Text('Send again · after 60 seconds'),
    ),
    _card(
      Column(
        children: [
          _row(Icons.shield_outlined, 'Plan', planName),
          _row(Icons.currency_rupee, 'Fee', '$fee · $monthlyFee a month'),
          _row(Icons.home_outlined, 'Home', details['address'] as String),
          TextButton(
            onPressed: busy ? null : () => _readContract(),
            child: const Text('Read full contract'),
          ),
        ],
      ),
    ),
    _helpBar('OTP not coming? We can help on a call'),
  ];
  List<Widget> _active() => [
    _heading('Your plan has started', 'Your signed owner contract is ready.'),
    const Icon(Icons.check_circle, size: 88, color: AppColors.success),
    const SizedBox(height: 20),
    TextButton.icon(
      onPressed: busy ? null : () => _readContract(signed: true),
      icon: const Icon(Icons.description_outlined),
      label: const Text('Read signed contract'),
    ),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Find a tenant',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review your photos and public listing, then put it live on TrustKeyper. Other property sites are not posted automatically.',
          ),
        ],
      ),
    ),
  ];
  List<Widget> _listing() => [
    _heading('Check your listing', 'This is what tenants will see.'),
    TextField(
      controller: title,
      maxLength: 100,
      decoration: const InputDecoration(labelText: 'Public home title'),
    ),
    TextField(
      controller: locality,
      maxLength: 150,
      decoration: const InputDecoration(
        labelText: 'Public locality and city (not private door details)',
      ),
    ),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${workspaceMoney(details['rentPaise'] as int)} / month',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          _row(
            Icons.bed_outlined,
            'Home',
            '${details['rooms']} · ${details['furnishing']} furnished',
          ),
          _row(
            Icons.people_outline,
            'Who can stay',
            details['whoCanStay'] as String,
          ),
          _row(
            Icons.calendar_month,
            'From',
            details['availableFrom'] as String,
          ),
          _row(
            Icons.shield_outlined,
            'Deposit',
            workspaceMoney(details['depositPaise'] as int),
          ),
          for (var index = 0; index < property.photos.length; index++)
            TextButton.icon(
              onPressed: busy ? null : () => _photo(index),
              icon: const Icon(Icons.photo_outlined),
              label: Text(
                'Review photo ${index + 1} of ${property.photos.length}',
              ),
            ),
        ],
      ),
    ),
    if (property.photos.length < 5)
      TextButton.icon(
        onPressed: busy ? null : _addPhoto,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add actual property photo'),
      ),
    if (property.photos.isEmpty)
      const Text(
        'Your manager must add the actual property photos before publishing.',
      ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: publicApproved,
      onChanged: busy
          ? null
          : (value) => setState(() => publicApproved = value == true),
      title: const Text(
        'I approve publishing these photos, title, locality and rent details',
      ),
    ),
    const Text(
      'Your phone and private documents are never shown. Tenants contact TrustKeyper first.',
      style: TextStyle(color: AppColors.muted),
    ),
  ];
  List<Widget> _live() => [
    _heading(
      'Your listing is live',
      '${listing['title']} · ${workspaceMoney(details['rentPaise'] as int)}',
    ),
    const Icon(Icons.check_circle, size: 88, color: AppColors.success),
    const SizedBox(height: 20),
    _card(
      Column(
        children: [
          _row(
            Icons.visibility_outlined,
            'Verified tenant views',
            '${listing['views'] ?? 0}',
          ),
          _row(
            Icons.favorite_border,
            'Interested tenants',
            '${interested.length}',
          ),
          _row(
            Icons.calendar_month,
            'Visits confirmed',
            '${interested.where((value) => value.value['visit'] != null).length}',
          ),
        ],
      ),
    ),
    SelectableText(publicLink),
    TextButton.icon(
      onPressed: () => Clipboard.setData(ClipboardData(text: publicLink)),
      icon: const Icon(Icons.copy),
      label: const Text('Copy listing link'),
    ),
    if (property.data['listing']['publishedAtMs'] is int &&
        DateTime.now().millisecondsSinceEpoch -
                (property.data['listing']['publishedAtMs'] as int) >=
            14 * 86400000 &&
        interested.every((value) => value.value['visit'] == null))
      _helpBar('No visits yet? Your manager can help improve the listing.'),
    TextButton(
      onPressed: busy
          ? null
          : () => _change('pause_listing').then((_) {
              if (mounted && property.status == 'listing_paused') {
                setState(() => page = 'active');
              }
            }),
      child: const Text('Pause listing'),
    ),
  ];
  List<Widget> _tenants() => [
    _heading(
      'Tenants who want it',
      '${listing['title']} · ${workspaceMoney(details['rentPaise'] as int)}',
    ),
    Wrap(
      spacing: 8,
      children: ['liked', 'visits']
          .map(
            (value) => ChoiceChip(
              label: Text(
                value == 'liked'
                    ? 'Liked ${interested.length}'
                    : 'Visits ${interested.where((value) => value.value['visit'] != null).length}',
              ),
              selected: filter == value,
              onSelected: (_) => setState(() => filter = value),
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 14),
    if (interested.isEmpty)
      const Text(
        'No enquiries yet. This updates when a verified tenant contacts TrustKeyper.',
      ),
    for (final entry in interested.where(
      (value) => filter != 'visits' || value.value['visit'] != null,
    ))
      _card(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.primarySoft,
            child: Text((entry.value['name'] as String).substring(0, 1)),
          ),
          title: Text(entry.value['name'] as String),
          subtitle: Text(
            '${entry.value['household']} people · ${entry.value['work']}\nWants to move in ${entry.value['moveIn']}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() {
            candidateId = entry.key;
            page = 'candidate';
          }),
        ),
      ),
    _helpBar('Not sure whom to pick? We can help you choose.'),
  ];
  List<Widget> _tenant() => [
    _heading(
      candidate['name'] as String? ?? 'Tenant',
      candidate['identityCheck']?['checked'] == true
          ? 'ID checked by TrustKeyper'
          : 'Identity check pending',
    ),
    _card(
      Column(
        children: [
          _row(Icons.people_outline, 'People', '${candidate['household']}'),
          _row(Icons.work_outline, 'Work', candidate['work'] as String),
          _row(Icons.calendar_month, 'Move in', candidate['moveIn'] as String),
          _row(
            Icons.currency_rupee,
            'Rent and deposit',
            '${workspaceMoney(details['rentPaise'] as int)} + ${workspaceMoney(details['depositPaise'] as int)}',
          ),
        ],
      ),
    ),
    if (candidate['visit'] != null || candidate['requestedVisit'] != null)
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              candidate['visit'] != null
                  ? 'Confirmed visit'
                  : 'Requested visit',
            ),
            Text(
              '${(candidate['visit'] ?? candidate['requestedVisit'])['day']} · ${(candidate['visit'] ?? candidate['requestedVisit'])['slot']}',
            ),
          ],
        ),
        color: const Color(0xFFFFF3E0),
      ),
    TextButton.icon(
      onPressed: busy ? null : _visit,
      icon: const Icon(Icons.schedule),
      label: Text(
        candidate['visit'] == null ? 'Confirm a visit' : 'Pick another time',
      ),
    ),
    TextButton(
      onPressed: busy
          ? null
          : () => _change('decline_tenant', {'candidateId': candidateId}).then((
              _,
            ) {
              if (mounted && candidate['status'] == 'declined') {
                setState(() => page = 'candidates');
              }
            }),
      child: const Text('Say no'),
    ),
  ];
  List<Widget> _chosen() => [
    _heading(
      '${candidate['name']} is your tenant',
      'Your listing is paused now.',
    ),
    const Icon(Icons.check_circle, size: 88, color: AppColors.success),
    const SizedBox(height: 20),
    _card(
      Column(
        children: [
          _row(
            Icons.description_outlined,
            'Our team makes the agreement',
            property.data['agreementId'] == null
                ? 'In progress'
                : 'Ready to review',
          ),
          _row(
            Icons.check_circle_outline,
            'You and the tenant review',
            'Before signing',
          ),
          _row(Icons.home_outlined, 'Move in', candidate['moveIn'] as String),
        ],
      ),
    ),
    if (property.data['agreementId'] == null)
      const Text(
        'The agreement link appears only when the actual agreement is prepared.',
      ),
    _helpBar('Not sure? Call us — we will help'),
  ];
  Widget? _footer() => switch (page) {
    'fee' =>
      property.status == 'contract_accepted'
          ? PrimaryButton(
              label: 'Check for signed copy',
              onPressed: busy ? null : _refresh,
            )
          : PrimaryButton(
              label: 'Agree and sign',
              icon: Icons.edit_outlined,
              onPressed:
                  busy ||
                      !readTerms ||
                      !acceptTerms ||
                      contract['status'] != 'ready'
                  ? null
                  : _sendCode,
            ),
    'otp' => PrimaryButton(
      label: 'Confirm',
      icon: Icons.check,
      onPressed: busy ? null : _confirmCode,
    ),
    'active' => PrimaryButton(
      label: 'Find a tenant',
      onPressed: busy
          ? null
          : () => setState(() {
              page = 'listing';
              publicApproved = false;
            }),
    ),
    'listing' => PrimaryButton(
      label: 'Put it live',
      icon: Icons.send_outlined,
      onPressed: busy || !publicApproved || property.photos.isEmpty
          ? null
          : _publish,
    ),
    'live' => PrimaryButton(
      label: 'See interested tenants',
      onPressed: busy ? null : () => setState(() => page = 'candidates'),
    ),
    'candidate' => PrimaryButton(
      label: 'Choose ${candidate['name']}',
      icon: Icons.check,
      onPressed: busy || candidate['identityCheck']?['checked'] != true
          ? null
          : () => _change('choose_tenant', {'candidateId': candidateId}),
    ),
    'chosen' => PrimaryButton(
      label: 'See the agreement',
      onPressed: busy || property.data['agreementId'] == null
          ? null
          : () => context.push(
              '/owner/agreement?id=${Uri.encodeQueryComponent(property.data['agreementId'] as String)}',
            ),
    ),
    _ => null,
  };
  @override
  Widget build(BuildContext context) => ApprovedAuthScaffold(
    showBack: false,
    header: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ApprovedBackButton(
            onPressed: () {
              if (page == 'candidate') {
                setState(() => page = 'candidates');
              } else if (['listing', 'candidates', 'otp'].contains(page)) {
                setState(
                  () => page = page == 'otp'
                      ? 'fee'
                      : property.status == 'listing_live'
                      ? 'live'
                      : 'active',
                );
              } else {
                Navigator.maybePop(context);
              }
            },
          ),
          const AppBrand(height: 28),
          IconButton(
            onPressed: busy ? null : _help,
            icon: const Icon(Icons.phone_outlined),
          ),
        ],
      ),
    ),
    footer: _footer(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.offline)
          const Text(
            'OFFLINE UI TEST · no real contract, listing or tenant is changed',
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error!, style: const TextStyle(color: AppColors.error)),
          ),
        ...switch (page) {
          'fee' => _fee(),
          'otp' => _otp(),
          'active' => _active(),
          'listing' => _listing(),
          'live' => _live(),
          'candidates' => _tenants(),
          'candidate' => _tenant(),
          'chosen' => _chosen(),
          _ => <Widget>[],
        },
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh saved property'),
        ),
      ],
    ),
  );
}
