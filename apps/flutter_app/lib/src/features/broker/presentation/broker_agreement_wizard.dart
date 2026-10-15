import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../agreement_approvals/presentation/broker_approval_screen.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/presentation/approved_auth_widgets.dart';
import '../data/agreement_draft.dart';
import '../data/agreement_draft_repository.dart';
import '../data/agreement_progress_repository.dart';
import '../data/private_documents.dart';
import '../data/broker_property_repository.dart';
import '../data/agreement_field_validation.dart';
import 'broker_property_screen.dart';
import 'private_documents_screen.dart';
import 'paper_party_tabs.dart';
import 'party_document_header.dart';
import '../data/demo_agreement.dart';
import 'demo_agreement_screen.dart';
import 'agreement_review_request.dart';
import '../../document_requests/data/document_request_repository.dart';

enum _Stage {
  ownerCount,
  owner,
  ownerPapers,
  tenantCount,
  tenant,
  tenantPapers,
  money,
  dates,
  periods,
  brokerage,
  review,
}

class BrokerAgreementWizard extends StatefulWidget {
  const BrokerAgreementWizard({
    this.property,
    this.initialDraft,
    this.repository,
    this.onSaved,
    this.initialProgress,
    this.progressRepository,
    this.documentFactory,
    this.pickDocument,
    this.takeDocumentPhoto,
    this.documentRequests,
    this.documentNow,
    this.initialPartyId,
    this.initialPartyRole,
    this.propertyRepository,
    super.key,
  });
  final BrokerProperty? property;
  final AgreementDraft? initialDraft;
  final AgreementDraftRepository? repository;
  final VoidCallback? onSaved;
  final AgreementProgress? initialProgress;
  final AgreementProgressRepository? progressRepository;
  final PrivateDocuments Function(AgreementDraft draft)? documentFactory;
  final Future<DocumentFile?> Function()? pickDocument;
  final Future<DocumentFile?> Function()? takeDocumentPhoto;
  final DocumentRequests? documentRequests;
  final DateTime Function()? documentNow;
  final String? initialPartyId;
  final String? initialPartyRole;
  final BrokerPropertyRepository? propertyRepository;
  @override
  State<BrokerAgreementWizard> createState() => _BrokerAgreementWizardState();
}

class _BrokerAgreementWizardState extends State<BrokerAgreementWizard> {
  late final AgreementDraftRepository repository;
  late final String draftId;
  late final AgreementProgressRepository? progressRepository;
  final documentIdentities = <String, String>{};
  int progressVersion = 0;
  bool documentBusy = false;
  final completedPapers = <String, bool>{};
  bool progressSaved = false;
  final owners = <_PartyFields>[];
  final tenants = <_PartyFields>[];
  final rent = TextEditingController();
  final maintenance = TextEditingController(text: '0');
  final deposit = TextEditingController();
  final ownerBrokerage = TextEditingController(text: '0');
  final tenantBrokerage = TextEditingController(text: '0');
  _Stage stage = _Stage.ownerCount;
  int person = 0;
  int sequence = 0;
  int dueDay = 5;
  int durationMonths = 11;
  int lockIn = 0;
  int notice = 1;
  int? depositMonths;
  DateTime? startDate;
  DateTime? endDate;
  bool extraMaintenance = false;
  String payer = 'Tenant';
  String? error;
  List<AgreementFieldIssue> fieldIssues = [];
  final fieldKeys = <String, GlobalKey>{};
  final fieldFocus = <String, FocusNode>{};
  BrokerProperty? currentProperty;
  bool saving = false;
  bool dirty = false;
  bool editing = false;
  String get address =>
      currentProperty?.address ?? initialDraft?.propertyAddress ?? '';
  AgreementDraft? get initialDraft =>
      widget.initialProgress?.draft ?? widget.initialDraft;
  int get rentPaise => parseRupeesToPaise(rent.text) ?? 0;
  int get depositPaise => parseRupeesToPaise(deposit.text) ?? 0;
  int get ownerFee => payer == 'Owner' || payer == 'Both'
      ? parseRupeesToPaise(ownerBrokerage.text) ?? 0
      : 0;
  int get tenantFee => payer == 'Tenant' || payer == 'Both'
      ? parseRupeesToPaise(tenantBrokerage.text) ?? 0
      : 0;
  bool get ownerStage =>
      [_Stage.ownerCount, _Stage.owner, _Stage.ownerPapers].contains(stage);
  bool get tenantStage =>
      [_Stage.tenantCount, _Stage.tenant, _Stage.tenantPapers].contains(stage);
  int get step => ownerStage
      ? 2
      : tenantStage
      ? 3
      : stage == _Stage.brokerage || stage == _Stage.review
      ? 5
      : 4;

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? FirebaseAgreementDraftRepository();
    progressRepository =
        widget.progressRepository ??
        (repository is FirebaseAgreementDraftRepository
            ? FirebaseAgreementProgressRepository()
            : null);
    draftId = initialDraft?.id ?? repository.newId();
    final draft = initialDraft;
    currentProperty = widget.property;
    if (currentProperty == null && draft?.propertyDetails != null) {
      currentProperty = BrokerProperty.fromMap(draft!.propertyId ?? '', {
        ...draft.propertyDetails!,
        'address': draft.propertyAddress,
      });
    }
    for (final party in draft?.owners ?? const <AgreementParty>[]) {
      owners.add(_PartyFields(party.id, party: party));
    }
    for (final party in draft?.tenants ?? const <AgreementParty>[]) {
      tenants.add(_PartyFields(party.id, party: party));
    }
    if (owners.isEmpty) owners.add(_PartyFields(_newPartyId('owner')));
    if (tenants.isEmpty) tenants.add(_PartyFields(_newPartyId('tenant')));
    if (draft != null) {
      rent.text = _input(draft.monthlyRentPaise);
      maintenance.text = _input(draft.maintenancePaise);
      deposit.text = _input(draft.depositPaise);
      ownerBrokerage.text = _input(draft.ownerBrokeragePaise);
      tenantBrokerage.text = _input(draft.tenantBrokeragePaise);
      extraMaintenance = draft.maintenancePaise > 0;
      dueDay = draft.rentDueDay;
      lockIn = draft.lockInMonths;
      notice = draft.noticeMonths;
      startDate = draft.startDate;
      endDate = draft.endDate;
      if (startDate != null && endDate != null) {
        durationMonths = 0;
        for (var months = 1; months <= 60; months++) {
          if (addCalendarMonths(
                startDate!,
                months,
              ).subtract(const Duration(days: 1)) ==
              endDate) {
            durationMonths = months;
            break;
          }
        }
      }
      payer = draft.brokeragePaise == 0
          ? 'None'
          : draft.ownerBrokeragePaise == 0
          ? 'Tenant'
          : draft.tenantBrokeragePaise == 0
          ? 'Owner'
          : 'Both';
      stage = _Stage.review;
      if (draft.legacySplitTotalPaise != null) {
        stage = _Stage.brokerage;
        payer = 'Both';
      }
    }
    final progress = widget.initialProgress;
    if (progress != null) {
      stage = _Stage.values.firstWhere((value) => value.name == progress.stage);
      person = progress.person;
      progressVersion = progress.version;
      final inputs = progress.inputs;
      rent.text = inputs['rent'] as String? ?? rent.text;
      maintenance.text = inputs['maintenance'] as String? ?? maintenance.text;
      deposit.text = inputs['deposit'] as String? ?? deposit.text;
      ownerBrokerage.text =
          inputs['ownerBrokerage'] as String? ?? ownerBrokerage.text;
      tenantBrokerage.text =
          inputs['tenantBrokerage'] as String? ?? tenantBrokerage.text;
      payer = inputs['payer'] as String? ?? payer;
      extraMaintenance = inputs['extraMaintenance'] == true;
      depositMonths = inputs['depositMonths'] as int?;
      durationMonths = inputs['durationMonths'] as int? ?? durationMonths;
      dirty = true;
      progressSaved = true;
    }
    if (widget.initialPartyId != null) {
      final target = widget.initialPartyRole == 'owner' ? owners : tenants;
      final position = target.indexWhere(
        (party) => party.id == widget.initialPartyId,
      );
      if (position >= 0 &&
          ['owner', 'tenant'].contains(widget.initialPartyRole)) {
        person = position;
        stage = widget.initialPartyRole == 'owner'
            ? _Stage.ownerPapers
            : _Stage.tenantPapers;
      }
    }
    for (final fields in [...owners, ...tenants]) {
      documentIdentities[fields.id] = _identity(fields);
    }
    for (final controller in [
      rent,
      maintenance,
      deposit,
      ownerBrokerage,
      tenantBrokerage,
    ]) {
      controller.addListener(_changed);
    }
  }

  String _newPartyId(String role) =>
      '$role-${DateTime.now().microsecondsSinceEpoch}-${sequence++}';
  void _changed() {
    if (!mounted) return;
    if (depositMonths != null &&
        deposit.text != _input(rentPaise * depositMonths!)) {
      deposit.text = _input(rentPaise * depositMonths!);
    }
    setState(() {
      dirty = true;
      progressSaved = false;
      error = null;
      if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
    });
  }

  @override
  void dispose() {
    for (final focus in fieldFocus.values) {
      focus.dispose();
    }
    for (final fields in [...owners, ...tenants]) {
      fields.dispose();
    }
    for (final controller in [
      rent,
      maintenance,
      deposit,
      ownerBrokerage,
      tenantBrokerage,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _identity(_PartyFields fields) =>
      '${fields.name.text.trim()}|${fields.value.phone}|${fields.email.text.trim().toLowerCase()}';

  void _syncDocumentIdentities() {
    for (final fields in [...owners, ...tenants]) {
      final identity = _identity(fields);
      if (documentIdentities.containsKey(fields.id) &&
          documentIdentities[fields.id] != identity) {
        fields.id = _newPartyId(owners.contains(fields) ? 'owner' : 'tenant');
      }
      documentIdentities[fields.id] = identity;
    }
  }

  AgreementDraft _draft({int? documentRevision}) => AgreementDraft(
    id: draftId,
    propertyAddress: address,
    propertyId: currentProperty?.id ?? initialDraft?.propertyId,
    renewalSourceId: initialDraft?.renewalSourceId,
    propertyDetails: currentProperty?.toMap() ?? initialDraft?.propertyDetails,
    owners: owners.map((fields) => fields.value).toList(),
    tenants: tenants.map((fields) => fields.value).toList(),
    monthlyRentPaise: parseRupeesToPaise(rent.text) ?? -1,
    maintenancePaise: extraMaintenance
        ? parseRupeesToPaise(maintenance.text) ?? -1
        : 0,
    depositPaise: parseRupeesToPaise(deposit.text) ?? -1,
    startDate: startDate,
    endDate: endDate,
    rentDueDay: dueDay,
    lockInMonths: lockIn,
    noticeMonths: notice,
    ownerBrokeragePaise: payer == 'Owner' || payer == 'Both'
        ? parseRupeesToPaise(ownerBrokerage.text) ?? -1
        : 0,
    tenantBrokeragePaise: payer == 'Tenant' || payer == 'Both'
        ? parseRupeesToPaise(tenantBrokerage.text) ?? -1
        : 0,
    revision: documentRevision ?? initialDraft?.revision ?? 0,
  );

  List<AgreementFieldIssue> _allIssues() => agreementFieldIssues(
    _draft(),
    inputs: {
      'rent': rent.text,
      'maintenance': maintenance.text,
      'deposit': deposit.text,
      'ownerBrokerage': ownerBrokerage.text,
      'tenantBrokerage': tenantBrokerage.text,
    },
    payer: payer,
  );

  List<AgreementFieldIssue> _stageIssues() => _allIssues().where((issue) {
    if (issue.field == 'address' || stage == _Stage.review) return true;
    if (issue.stage != stage.name) {
      return stage == _Stage.periods && issue.stage == 'dates';
    }
    return !['owner', 'tenant'].contains(issue.stage) || issue.person == person;
  }).toList();

  String? _fieldError(String field) {
    for (final issue in fieldIssues) {
      if (issue.field == field) return issue.message;
    }
    return null;
  }

  GlobalKey _fieldKey(String field) =>
      fieldKeys.putIfAbsent(field, GlobalKey.new);
  FocusNode _fieldFocus(String field) =>
      fieldFocus.putIfAbsent(field, FocusNode.new);

  Future<void> _openIssue(AgreementFieldIssue issue) async {
    if (saving || documentBusy) return;
    if (issue.stage == 'property') {
      final property =
          currentProperty ??
          BrokerProperty.fromMap(initialDraft?.propertyId ?? '', {
            ...?initialDraft?.propertyDetails,
            'address': address,
          });
      final updated = await Navigator.of(context).push<BrokerProperty>(
        MaterialPageRoute(
          builder: (editorContext) => BrokerPropertyScreen(
            initialProperty: property,
            repository: widget.propertyRepository,
            onSelected: (value) => Navigator.pop(editorContext, value),
          ),
        ),
      );
      if (!mounted || updated == null) return;
      setState(() {
        currentProperty = updated;
        dirty = true;
        progressSaved = false;
        fieldIssues = _stageIssues();
        error = null;
      });
      return;
    }
    setState(() {
      stage = _Stage.values.firstWhere((value) => value.name == issue.stage);
      person =
          [
            'owner',
            'tenant',
            'ownerPapers',
            'tenantPapers',
          ].contains(issue.stage)
          ? issue.person
          : 0;
      editing = false;
      error = null;
      fieldIssues = _stageIssues();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = issue.field == 'rentShares'
          ? 'tenant/0/rentShare'
          : issue.field == 'depositShares'
          ? 'tenant/0/depositShare'
          : issue.field == 'brokerageTotal'
          ? payer == 'Tenant'
                ? 'tenantBrokerage'
                : 'ownerBrokerage'
          : issue.field;
      final fieldContext = fieldKeys[target]?.currentContext;
      if (fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 200),
          alignment: .3,
        );
        fieldFocus[target]?.requestFocus();
      }
    });
  }

  Widget _validationSummary() => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: AppColors.error),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please check these details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.heading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.viewInsetsOf(context).bottom > 0 ? 90 : 144,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final issue in fieldIssues)
                    InkWell(
                      onTap: () => _openIssue(issue),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${issue.label}: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(text: issue.message),
                                  ],
                                ),
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Fix',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<bool> _checkpoint({bool notify = false}) async {
    _syncDocumentIdentities();
    final progressStore = progressRepository;
    if (progressStore == null) return true;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      progressVersion = await progressStore.save(
        AgreementProgress(
          draft: _draft(),
          stage: stage.name,
          person: person,
          version: progressVersion,
          inputs: {
            'rent': rent.text,
            'maintenance': maintenance.text,
            'deposit': deposit.text,
            'ownerBrokerage': ownerBrokerage.text,
            'tenantBrokerage': tenantBrokerage.text,
            'payer': payer,
            'extraMaintenance': extraMaintenance,
            'depositMonths': depositMonths,
            'durationMonths': durationMonths,
          },
        ),
      );
      if (!mounted) return false;
      setState(() => progressSaved = true);
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft progress saved. Resume it from Agreements.'),
          ),
        );
      }
      return true;
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is DraftFailure
              ? failure.message
              : 'Could not save progress. Check your connection and retry.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _next() async {
    if (saving || documentBusy) return;
    FocusScope.of(context).unfocus();
    final issues = _stageIssues();
    if (issues.isNotEmpty) {
      setState(() {
        fieldIssues = issues;
        error = null;
      });
      if (stage != _Stage.review && issues.first.stage != stage.name) {
        await _openIssue(issues.first);
      }
      return;
    }
    setState(() => fieldIssues = []);
    String? validation;
    if (stage == _Stage.owner || stage == _Stage.tenant) {
      final fields = ownerStage ? owners : tenants;
      validation = fields[person].value.validationError;
      final phones = fields
          .map((entry) => entry.value.phone)
          .where((phone) => phone.length == 13)
          .toList();
      if (validation == null && phones.toSet().length != phones.length) {
        validation = 'Each person needs a different mobile number.';
      }
    } else if (stage == _Stage.money) {
      validation = _draft().moneyError;
    } else if (stage == _Stage.dates) {
      if (startDate == null ||
          endDate == null ||
          !endDate!.isAfter(startDate!)) {
        validation = 'Choose valid start and end dates.';
      }
    } else if (stage == _Stage.periods) {
      validation = _draft().datesError;
    } else if (stage == _Stage.brokerage) {
      if ((payer == 'Owner' || payer == 'Both') &&
              parseRupeesToPaise(ownerBrokerage.text) == null ||
          (payer == 'Tenant' || payer == 'Both') &&
              parseRupeesToPaise(tenantBrokerage.text) == null) {
        validation = 'Enter valid brokerage amounts.';
      }
      if (payer == 'Both' && (ownerFee <= 0 || tenantFee <= 0)) {
        validation =
            'Enter both brokerage amounts, or choose Owner, Tenant or None.';
      }
    } else if (stage == _Stage.review) {
      validation = _draft().validationError;
    }
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    _syncDocumentIdentities();
    if (stage == _Stage.review) {
      await _save();
      return;
    }
    final previousStage = stage;
    final previousPerson = person;
    final previousEditing = editing;
    setState(() {
      error = null;
      switch (stage) {
        case _Stage.ownerCount:
          person = 0;
          stage = _Stage.owner;
        case _Stage.owner:
          stage = _Stage.ownerPapers;
        case _Stage.ownerPapers:
          if (++person < owners.length) {
            stage = _Stage.owner;
          } else {
            person = 0;
            stage = editing ? _Stage.review : _Stage.tenantCount;
            editing = false;
          }
        case _Stage.tenantCount:
          person = 0;
          stage = _Stage.tenant;
        case _Stage.tenant:
          stage = _Stage.tenantPapers;
        case _Stage.tenantPapers:
          if (++person < tenants.length) {
            stage = _Stage.tenant;
          } else {
            person = 0;
            stage = editing ? _Stage.review : _Stage.money;
            editing = false;
          }
        case _Stage.money:
          stage = editing ? _Stage.review : _Stage.dates;
          editing = false;
        case _Stage.dates:
          stage = _Stage.periods;
        case _Stage.periods:
          stage = editing ? _Stage.review : _Stage.brokerage;
          editing = false;
        case _Stage.brokerage:
          stage = _Stage.review;
          editing = false;
        case _Stage.review:
          break;
      }
    });
    if (!await _checkpoint() && mounted) {
      setState(() {
        stage = previousStage;
        person = previousPerson;
        editing = previousEditing;
      });
    }
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _back() async {
    if (saving || documentBusy) return;
    setState(() => fieldIssues = []);
    if (editing) {
      setState(() {
        stage = _Stage.review;
        editing = false;
        error = null;
      });
      return;
    }
    if (stage == _Stage.ownerCount) {
      if (dirty &&
          !progressSaved &&
          !await _confirm('Leave without saving this draft?')) {
        return;
      }
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/broker/start');
      }
      return;
    }
    setState(() {
      error = null;
      switch (stage) {
        case _Stage.owner:
          if (person > 0) {
            person--;
            stage = _Stage.ownerPapers;
          } else {
            stage = _Stage.ownerCount;
          }
        case _Stage.ownerPapers:
          stage = _Stage.owner;
        case _Stage.tenantCount:
          person = owners.length - 1;
          stage = _Stage.ownerPapers;
        case _Stage.tenant:
          if (person > 0) {
            person--;
            stage = _Stage.tenantPapers;
          } else {
            stage = _Stage.tenantCount;
          }
        case _Stage.tenantPapers:
          stage = _Stage.tenant;
        case _Stage.money:
          person = tenants.length - 1;
          stage = _Stage.tenantPapers;
        case _Stage.dates:
          stage = _Stage.money;
        case _Stage.periods:
          stage = _Stage.dates;
        case _Stage.brokerage:
          stage = _Stage.periods;
        case _Stage.review:
          stage = _Stage.brokerage;
        case _Stage.ownerCount:
          break;
      }
    });
  }

  String get title => ownerStage
      ? 'Owner details'
      : tenantStage
      ? 'Tenant details'
      : stage == _Stage.brokerage
      ? 'Your brokerage'
      : stage == _Stage.review
      ? 'Check agreement'
      : 'Agreement details';
  String get subtitle => ownerStage
      ? 'Who is giving the property on rent?'
      : tenantStage
      ? 'Who will live in the property?'
      : stage == _Stage.money
      ? 'Rent and deposit.'
      : stage == _Stage.brokerage
      ? 'Money you get for this deal.'
      : stage == _Stage.review
      ? 'Check every person, amount and date.'
      : 'Dates, rent day and notice.';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: step / 5,
                        minHeight: 6,
                        backgroundColor: AppColors.primaryBorder,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (progressRepository != null &&
                        stage != _Stage.ownerPapers &&
                        stage != _Stage.tenantPapers)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: saving || documentBusy
                              ? null
                              : () => _checkpoint(notify: true),
                          icon: Icon(
                            progressSaved
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_upload_outlined,
                          ),
                          label: Text(
                            progressSaved ? 'Progress saved' : 'Save progress',
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stage == _Stage.review
                                ? 'Review'
                                : 'Step $step of 5 · ${ownerStage
                                      ? 'Owner'
                                      : tenantStage
                                      ? 'Tenant'
                                      : step == 5
                                      ? 'Brokerage'
                                      : 'Details'}',
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            fixedSize: const Size(48, 48),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.heading,
                          ),
                          onPressed: () =>
                              launchUrl(Uri.parse('tel:+918088516875')),
                          tooltip: 'Call us',
                          icon: const Icon(Icons.call_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        ApprovedBackButton(onPressed: _back),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 17,
                        height: 24 / 17,
                      ),
                    ),
                    SizedBox(
                      height:
                          stage == _Stage.ownerPapers ||
                              stage == _Stage.tenantPapers
                          ? 20
                          : 28,
                    ),
                    AbsorbPointer(
                      absorbing: saving,
                      child: switch (stage) {
                        _Stage.ownerCount => _count(true),
                        _Stage.tenantCount => _count(false),
                        _Stage.owner => _person(true),
                        _Stage.tenant => _person(false),
                        _Stage.ownerPapers => _papers(true),
                        _Stage.tenantPapers => _papers(false),
                        _Stage.money => _money(),
                        _Stage.dates => _dates(),
                        _Stage.periods => _periods(),
                        _Stage.brokerage => _brokerage(),
                        _Stage.review => _review(),
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEDF1F6))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stage == _Stage.review && fieldIssues.isNotEmpty) ...[
                    _validationSummary(),
                    const SizedBox(height: 10),
                  ],
                  if (error != null) ...[
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: TextButton(
                          onPressed: saving || documentBusy ? null : _back,
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chevron_left, size: 20),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Back',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 17),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          label: saving
                              ? 'Saving…'
                              : stage == _Stage.review
                              ? 'Save private draft'
                              : stage == _Stage.brokerage
                              ? 'Check agreement'
                              : stage == _Stage.ownerPapers &&
                                    person + 1 < owners.length
                              ? 'Next: Owner ${person + 2}'
                              : stage == _Stage.tenantPapers &&
                                    person + 1 < tenants.length
                              ? 'Next: Tenant ${person + 2}'
                              : 'Next',
                          icon: Icons.chevron_right,
                          onPressed: saving || documentBusy ? null : _next,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _count(bool owner) {
    final fields = owner ? owners : tenants;
    return Padding(
      padding: const EdgeInsets.only(top: 100, bottom: 60),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primarySoft,
            child: Icon(
              Icons.people_outline,
              size: 40,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'How many ${owner ? 'owners' : 'tenants'}?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: fields.length > 1 ? () => _resize(owner, -1) : null,
                tooltip: 'Remove ${owner ? 'owner' : 'tenant'}',
                icon: const Icon(Icons.remove),
                iconSize: 30,
              ),
              const SizedBox(width: 18),
              Container(
                width: 100,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${fields.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              IconButton.filled(
                onPressed: fields.length < 20 ? () => _resize(owner, 1) : null,
                tooltip: 'Add ${owner ? 'owner' : 'tenant'}',
                icon: const Icon(Icons.add),
                iconSize: 30,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resize(bool owner, int change) async {
    final fields = owner ? owners : tenants;
    if (saving ||
        change < 0 && fields.length <= 1 ||
        change > 0 && fields.length >= 20) {
      return;
    }
    if (change < 0 &&
        !await _confirm(
          'Remove ${owner ? 'Owner' : 'Tenant'} ${fields.length} and their draft details?',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (change > 0) {
        fields.add(_PartyFields(_newPartyId(owner ? 'owner' : 'tenant')));
      } else {
        fields.removeLast().dispose();
      }
      dirty = true;
      progressSaved = false;
    });
  }

  Widget _person(bool owner) {
    final fields = owner ? owners : tenants;
    final selected = fields[person];
    final role = owner ? 'Owner' : 'Tenant';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < fields.length; index++)
              ChoiceChip(
                label: Text(
                  '$role ${index + 1}${index == person ? ' of ${fields.length}' : ''}',
                ),
                selected: person == index,
                onSelected: (_) => setState(() {
                  person = index;
                  error = null;
                  fieldIssues = [];
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '$role ${person + 1} details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        TextField(
          key: _fieldKey('${owner ? 'owner' : 'tenant'}/$person/name'),
          focusNode: _fieldFocus('${owner ? 'owner' : 'tenant'}/$person/name'),
          controller: selected.name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Full name *',
            prefixIcon: const Icon(Icons.person_outline),
            errorText: _fieldError(
              '${owner ? 'owner' : 'tenant'}/$person/name',
            ),
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 14),
        TextField(
          key: _fieldKey('${owner ? 'owner' : 'tenant'}/$person/phone'),
          focusNode: _fieldFocus('${owner ? 'owner' : 'tenant'}/$person/phone'),
          controller: selected.phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: 'Mobile number *',
            prefixText: 'IN +91 ',
            prefixIcon: const Icon(Icons.call_outlined),
            errorText: _fieldError(
              '${owner ? 'owner' : 'tenant'}/$person/phone',
            ),
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 14),
        TextField(
          key: _fieldKey('${owner ? 'owner' : 'tenant'}/$person/email'),
          focusNode: _fieldFocus('${owner ? 'owner' : 'tenant'}/$person/email'),
          controller: selected.email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: const Icon(Icons.mail_outline),
            errorText: _fieldError(
              '${owner ? 'owner' : 'tenant'}/$person/email',
            ),
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(),
        ),
      ],
    );
  }

  Widget _papers(bool owner) {
    final party = (owner ? owners : tenants)[person];
    final draft = _draft(documentRevision: (initialDraft?.revision ?? 0) + 1);
    final previousDraft = initialDraft;
    final previousDocuments =
        previousDraft != null &&
            previousDraft.revision > 0 &&
            [
              ...previousDraft.owners,
              ...previousDraft.tenants,
            ].any((previous) => previous.id == party.id)
        ? widget.documentFactory?.call(previousDraft) ??
              PrivateDocuments.firebase(
                draftId: draftId,
                revision: previousDraft.revision,
                partyIds: {party.id},
              )
        : null;
    final phone = RegExp(r'^\d{10}$').hasMatch(party.phone.text)
        ? '${party.phone.text.substring(0, 5)} ${party.phone.text.substring(5)}'
        : party.phone.text;
    return DefaultTextStyle.merge(
      style: const TextStyle(letterSpacing: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PaperPartyTabs(
            owner: owner,
            count: (owner ? owners : tenants).length,
            selected: person,
            onSelected: saving || documentBusy
                ? null
                : (index) => setState(() => person = index),
          ),
          const SizedBox(height: 14),
          PartyDocumentHeader(
            name: party.name.text.trim(),
            contact:
                '$phone${party.email.text.trim().isEmpty ? '' : ' · ${party.email.text.trim()}'}',
            complete: completedPapers[party.id] == true,
            onEdit: saving || documentBusy
                ? null
                : () => setState(
                    () => stage = owner ? _Stage.owner : _Stage.tenant,
                  ),
          ),
          PrivateDocumentsScreen(
            documentNow: widget.documentNow,
            key: ValueKey('documents/$draftId/${draft.revision}/${party.id}'),
            draft: draft,
            embedded: true,
            onlyPartyId: party.id,
            enabled: !saving,
            documents: widget.documentFactory?.call(draft),
            previousDocuments: previousDocuments,
            pickFile: widget.pickDocument,
            takePhoto: widget.takeDocumentPhoto,
            requests: widget.documentRequests,
            onBusyChanged: (value) {
              if (mounted) setState(() => documentBusy = value);
            },
            onCompletionChanged: (value) {
              if (mounted && completedPapers[party.id] != value) {
                setState(() => completedPapers[party.id] = value);
              }
            },
            beforeRequest: _checkpoint,
            onEditPerson: () =>
                setState(() => stage = owner ? _Stage.owner : _Stage.tenant),
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: _fieldKey(_amountField(controller)),
        focusNode: _fieldFocus(_amountField(controller)),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹ ',
          errorText: _fieldError(_amountField(controller)),
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        rupeesInWords(parseRupeesToPaise(controller.text) ?? 0),
        style: const TextStyle(color: Color(0xFF008763), fontSize: 13),
      ),
    ],
  );
  String _amountField(TextEditingController controller) => controller == rent
      ? 'rent'
      : controller == maintenance
      ? 'maintenance'
      : controller == deposit
      ? 'deposit'
      : controller == ownerBrokerage
      ? 'ownerBrokerage'
      : 'tenantBrokerage';

  Widget _inlineError(String field) => _fieldError(field) == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _fieldError(field)!,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
        );
  Widget _money() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _amount('Monthly rent *', rent),
      const SizedBox(height: 22),
      const Text('Maintenance'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final extra in [false, true])
            ChoiceChip(
              label: Text(
                extra
                    ? 'Extra · paid every month'
                    : 'In the rent · no extra money',
              ),
              selected: extraMaintenance == extra,
              onSelected: (_) => setState(() {
                extraMaintenance = extra;
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      if (extraMaintenance) ...[
        const SizedBox(height: 12),
        _amount('Monthly maintenance', maintenance),
      ],
      const SizedBox(height: 22),
      const Text('Deposit *'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final months in [1, 2, 3])
            ChoiceChip(
              label: Text('$months ${months == 1 ? 'month' : 'months'}'),
              selected: depositMonths == months,
              onSelected: (_) => setState(() {
                depositMonths = months;
                deposit.text = _input(rentPaise * months);
                dirty = true;
                progressSaved = false;
              }),
            ),
          ActionChip(
            label: const Text('Other amount'),
            onPressed: () => setState(() {
              depositMonths = null;
              dirty = true;
              progressSaved = false;
            }),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _amount('Security deposit *', deposit),
      if (depositMonths != null)
        const Text(
          'Deposit follows the selected rent-month preset.',
          style: TextStyle(color: AppColors.muted),
        ),
      const SizedBox(height: 22),
      Row(
        children: [
          const Expanded(child: Text('Tenant shares')),
          TextButton(
            onPressed: _splitShares,
            child: const Text('Split equally'),
          ),
        ],
      ),
      _inlineError('rentShares'),
      _inlineError('depositShares'),
      for (var index = 0; index < tenants.length; index++) ...[
        const SizedBox(height: 14),
        Text(
          tenants[index].name.text.isEmpty
              ? 'Tenant ${index + 1}'
              : tenants[index].name.text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        TextField(
          key: _fieldKey('tenant/$index/rentShare'),
          focusNode: _fieldFocus('tenant/$index/rentShare'),
          controller: tenants[index].rentShare,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rent share *',
            prefixText: '₹ ',
            errorText: _fieldError('tenant/$index/rentShare'),
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 10),
        TextField(
          key: _fieldKey('tenant/$index/depositShare'),
          focusNode: _fieldFocus('tenant/$index/depositShare'),
          controller: tenants[index].depositShare,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Deposit share *',
            prefixText: '₹ ',
            errorText: _fieldError('tenant/$index/depositShare'),
            errorMaxLines: 3,
          ),
          onChanged: (_) => _changed(),
        ),
      ],
    ],
  );
  void _splitShares() {
    setState(() {
      for (var index = 0; index < tenants.length; index++) {
        tenants[index].rentShare.text = _input(
          rentPaise ~/ tenants.length +
              (index < rentPaise % tenants.length ? 1 : 0),
        );
        tenants[index].depositShare.text = _input(
          depositPaise ~/ tenants.length +
              (index < depositPaise % tenants.length ? 1 : 0),
        );
      }
      dirty = true;
      progressSaved = false;
      error = null;
    });
  }

  Widget _dates() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        key: _fieldKey('startDate'),
        onPressed: initialDraft?.renewalSourceId == null ? _pickStart : null,
        icon: const Icon(Icons.event_outlined),
        label: Text(
          startDate == null
              ? 'Choose start date *'
              : DateFormat('d MMM yyyy').format(startDate!),
        ),
      ),
      _inlineError('startDate'),
      if (initialDraft?.renewalSourceId != null) ...[
        const SizedBox(height: 8),
        const Text(
          'Renewal starts the day after the original ends. Change the new length below; the original stays unchanged.',
        ),
      ],
      const SizedBox(height: 22),
      Text('Agreement length', key: _fieldKey('endDate')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final months in [6, 11, 12, 24])
            ChoiceChip(
              label: Text('$months months'),
              selected: durationMonths == months,
              onSelected: (_) => setState(() {
                durationMonths = months;
                _calculateEnd();
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'Ends: ${endDate == null ? 'Choose start date first' : DateFormat('d MMM yyyy').format(endDate!)}',
      ),
      _inlineError('endDate'),
      const SizedBox(height: 22),
      Text('Rent day', key: _fieldKey('dueDay')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final day in [1, 5, 10])
            ChoiceChip(
              label: Text('Day $day'),
              selected: dueDay == day,
              onSelected: (_) => setState(() {
                dueDay = day;
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      _inlineError('dueDay'),
    ],
  );
  void _calculateEnd() {
    if (startDate != null && durationMonths > 0) {
      endDate = addCalendarMonths(
        startDate!,
        durationMonths,
      ).subtract(const Duration(days: 1));
    }
  }

  Future<void> _pickStart() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: startDate ?? today,
      firstDate: startDate != null && startDate!.isBefore(today)
          ? startDate!
          : today,
      lastDate: DateTime(today.year + 5),
    );
    if (selected == null || !mounted) return;
    setState(() {
      startDate = selected;
      _calculateEnd();
      dirty = true;
      progressSaved = false;
      error = null;
      if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
    });
  }

  Widget _periods() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Lock-in period', key: _fieldKey('lockIn')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final months in [0, 3, 6, 11, 12])
            ChoiceChip(
              label: Text(months == 0 ? 'No lock-in' : '$months months'),
              selected: lockIn == months,
              onSelected: (_) => setState(() {
                lockIn = months;
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      _inlineError('lockIn'),
      const SizedBox(height: 24),
      Text('Notice period', key: _fieldKey('notice')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final months in [1, 2, 3])
            ChoiceChip(
              label: Text('$months ${months == 1 ? 'month' : 'months'}'),
              selected: notice == months,
              onSelected: (_) => setState(() {
                notice = months;
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      _inlineError('notice'),
    ],
  );
  Widget _brokerage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.initialDraft?.legacySplitTotalPaise != null) ...[
        Text(
          'This older draft has ${_currency(widget.initialDraft!.legacySplitTotalPaise!)} total brokerage, but its split was not saved. Review and enter each amount; nothing has been paid.',
        ),
        const SizedBox(height: 16),
      ],
      Wrap(
        spacing: 8,
        children: [
          for (final choice in ['Owner', 'Tenant', 'Both', 'None'])
            ChoiceChip(
              label: Text(choice),
              selected: payer == choice,
              onSelected: (_) => setState(() {
                payer = choice;
                dirty = true;
                progressSaved = false;
                if (fieldIssues.isNotEmpty) fieldIssues = _stageIssues();
              }),
            ),
        ],
      ),
      if (payer == 'Owner' || payer == 'Both') ...[
        const SizedBox(height: 24),
        _amount('From owner', ownerBrokerage),
        _feePresets(ownerBrokerage),
      ],
      if (payer == 'Tenant' || payer == 'Both') ...[
        const SizedBox(height: 24),
        _amount('From tenant', tenantBrokerage),
        _feePresets(tenantBrokerage),
      ],
      _inlineError('brokerageTotal'),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE5F8F0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'You will get',
                style: TextStyle(color: Color(0xFF008763)),
              ),
            ),
            Flexible(
              child: Text(
                _currency(ownerFee + tenantFee),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _feePresets(TextEditingController controller) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      spacing: 8,
      children: [
        ActionChip(
          label: const Text('½ month rent'),
          onPressed: () => controller.text = _input((rentPaise / 2).round()),
        ),
        ActionChip(
          label: const Text('1 month rent'),
          onPressed: () => controller.text = _input(rentPaise),
        ),
      ],
    ),
  );
  void _edit(_Stage target) => setState(() {
    stage = target;
    person = 0;
    editing = true;
    error = null;
  });
  Widget _review() {
    final draft = _draft();
    final original = widget.initialDraft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(address, style: Theme.of(context).textTheme.titleLarge),
        if (original?.reviewReturnReason?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text('Team requested corrections: ${original!.reviewReturnReason}'),
          const Text(
            'Save a new revision after correcting these details, then reopen to request review again.',
          ),
        ],
        const SizedBox(height: 20),
        _reviewBlock(
          'Owners',
          owners
              .map((fields) => '${fields.name.text} · ${fields.value.phone}')
              .join('\n'),
          _Stage.ownerCount,
          changed:
              original != null &&
              draft.owners.map((party) => party.toMap().toString()).join() !=
                  original.owners
                      .map((party) => party.toMap().toString())
                      .join(),
        ),
        _reviewBlock(
          'Tenants',
          tenants
              .map(
                (fields) =>
                    '${fields.name.text} · ${fields.value.phone}\nRent ${_currency(fields.value.rentSharePaise)} · Deposit ${_currency(fields.value.depositSharePaise)}',
              )
              .join('\n\n'),
          _Stage.tenantCount,
          changed:
              original != null &&
              draft.tenants.map((party) => party.toMap().toString()).join() !=
                  original.tenants
                      .map((party) => party.toMap().toString())
                      .join(),
        ),
        _reviewBlock(
          'Rent and deposit',
          '${_currency(rentPaise)} monthly rent\n${_currency(draft.maintenancePaise)} maintenance\n${_currency(depositPaise)} deposit',
          _Stage.money,
          changed:
              original != null &&
              (draft.monthlyRentPaise != original.monthlyRentPaise ||
                  draft.depositPaise != original.depositPaise ||
                  draft.maintenancePaise != original.maintenancePaise),
        ),
        _reviewBlock(
          'Dates and notice',
          '${_date(startDate)} – ${_date(endDate)}\nRent day $dueDay · $lockIn months lock-in · $notice months notice',
          _Stage.dates,
          changed:
              original != null &&
              (draft.startDate != original.startDate ||
                  draft.endDate != original.endDate ||
                  dueDay != original.rentDueDay ||
                  lockIn != original.lockInMonths ||
                  notice != original.noticeMonths),
        ),
        _reviewBlock(
          'Brokerage',
          '${_currency(ownerFee)} from owner\n${_currency(tenantFee)} from tenant\nTotal ${_currency(ownerFee + tenantFee)}',
          _Stage.brokerage,
          changed:
              original != null &&
              (ownerFee != original.ownerBrokeragePaise ||
                  tenantFee != original.tenantBrokeragePaise),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: draft.validationError != null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DemoAgreementScreen(
                      agreement: DemoAgreement(draft),
                      previous:
                          original == null || original.validationError != null
                          ? null
                          : DemoAgreement(original),
                    ),
                  ),
                ),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Preview demo agreement'),
        ),
        if (original != null && original.revision > 0)
          OutlinedButton.icon(
            onPressed: dirty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BrokerApprovalScreen(draft: original),
                    ),
                  ),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send for approval · Demo only'),
          ),
        if (original != null && original.revision > 0)
          OutlinedButton.icon(
            onPressed: dirty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PrivateDocumentsScreen(draft: original),
                    ),
                  ),
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Manage private documents'),
          ),
        if (original != null && dirty)
          const Text(
            'Save and reopen this draft before adding documents to the changed details.',
          ),
        if (original != null &&
            original.revision > 0 &&
            !dirty &&
            repository is FirebaseAgreementDraftRepository)
          AgreementReviewRequest(
            agreementId: original.id,
            revision: original.revision,
            onSubmitted: () => context.go('/broker'),
          ),
        const Text(
          'The demo preview is not a legally approved contract. Send the saved version for demo replies; saving changes invalidates previous links and replies. Bank verification, legal consent and signing are still pending. Saving does not send messages or collect money.',
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
      ],
    );
  }

  Widget _reviewBlock(
    String label,
    String details,
    _Stage target, {
    bool changed = false,
  }) => Card(
    color: changed ? const Color(0xFFE5F8F0) : null,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  changed ? '$label · Changed' : label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => _edit(target),
                child: const Text('Change'),
              ),
            ],
          ),
          Text(details),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    _syncDocumentIdentities();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await repository.save(_draft());
      if (progressRepository != null && progressVersion > 0) {
        try {
          await progressRepository!.remove(draftId, progressVersion);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The complete draft is saved. An older progress entry may remain; reopen the complete draft from Agreements.',
                ),
              ),
            );
          }
        }
      }
      if (!mounted) return;
      dirty = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Private draft saved'),
          content: const Text(
            'All parties and terms are saved. No documents, links or approval requests have been sent.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        context.go('/broker');
      }
    } on DraftFailure catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure.message;
        });
      }
    } on FirebaseException catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure.code == 'permission-denied'
              ? 'Draft creation requires an approved broker account.'
              : 'Could not save. Your details are still here; try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save. Your details are still here; try again.';
        });
      }
    }
  }
}

class _PartyFields {
  _PartyFields(this.id, {AgreementParty? party}) {
    name.text = party?.name ?? '';
    phone.text = party?.phone.replaceFirst('+91', '') ?? '';
    email.text = party?.email ?? '';
    rentShare.text = _input(party?.rentSharePaise ?? 0);
    depositShare.text = _input(party?.depositSharePaise ?? 0);
  }
  String id;
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final rentShare = TextEditingController();
  final depositShare = TextEditingController();
  AgreementParty get value => AgreementParty(
    id: id,
    name: name.text.trim(),
    phone: '+91${phone.text.replaceAll(RegExp(r'\D'), '')}',
    email: email.text.trim().toLowerCase(),
    rentSharePaise: parseRupeesToPaise(rentShare.text) ?? -1,
    depositSharePaise: parseRupeesToPaise(depositShare.text) ?? -1,
  );
  void dispose() {
    for (final controller in [name, phone, email, rentShare, depositShare]) {
      controller.dispose();
    }
  }
}

String _input(int paise) =>
    paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);
String _currency(int paise) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: paise % 100 == 0 ? 0 : 2,
).format(paise / 100);
String _date(DateTime? value) =>
    value == null ? 'Not selected' : DateFormat('d MMM yyyy').format(value);

class BrokerDraftScreen extends StatefulWidget {
  const BrokerDraftScreen({
    required this.id,
    this.repository,
    this.partyId,
    this.role,
    super.key,
  });
  final String id;
  final AgreementDraftRepository? repository;
  final String? partyId;
  final String? role;
  @override
  State<BrokerDraftScreen> createState() => _BrokerDraftScreenState();
}

class _BrokerDraftScreenState extends State<BrokerDraftScreen> {
  late final AgreementDraftRepository repository =
      widget.repository ?? FirebaseAgreementDraftRepository();
  late Future<AgreementDraft> draft = repository.load(widget.id);
  @override
  Widget build(BuildContext context) => FutureBuilder<AgreementDraft>(
    future: draft,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return BrokerAgreementWizard(
          initialDraft: snapshot.data,
          initialPartyId: widget.partyId,
          initialPartyRole: widget.role,
          repository: repository,
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Open draft')),
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not open this private draft. Check your login and connection.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            setState(() => draft = repository.load(widget.id)),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
