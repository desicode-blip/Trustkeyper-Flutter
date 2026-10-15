import 'dart:async';
import '../../account/data/account_gateway.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/firebase_auth_service.dart';
import '../data/participant_repository.dart';
import '../data/participant_workspace.dart';
import 'participant_workspace_screen.dart';
import '../../tenant/data/tenant_setup.dart';
import '../../tenant/presentation/tenant_workspace_gate.dart';

class ParticipantSessionScreen extends StatefulWidget {
  const ParticipantSessionScreen({
    required this.role,
    this.repository,
    this.initialTab = 0,
    this.agreementId,
    super.key,
  });
  final String role;
  final ParticipantRepository? repository;
  final int initialTab;
  final String? agreementId;
  @override
  State<ParticipantSessionScreen> createState() =>
      _ParticipantSessionScreenState();
}

class _ParticipantSessionScreenState extends State<ParticipantSessionScreen> {
  late ParticipantRepository repository;
  ParticipantIdentity identity = const ParticipantIdentity();
  ParticipantIssueWriter? writer;
  TenantSetupGateway? tenantSetup;
  AccountGateway? accountGateway;
  StreamSubscription<User?>? users;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final active = ++generation;
    users?.cancel();
    users = null;
    writer = null;
    tenantSetup = null;
    accountGateway = null;
    identity = const ParticipantIdentity();
    repository = widget.repository ?? SessionParticipantRepository.firebase();
    if (widget.repository != null) return;
    accountGateway = FirebaseAccountGateway();
    if (widget.role == 'tenant') {
      tenantSetup = FirebaseTenantSetupGateway();
    }
    writer = FirebaseParticipantIssueWriter(
      uid: () => FirebaseAuthService.instance.currentUser?.uid ?? '',
    );
    users = FirebaseAuth.instance.userChanges().listen(
      (user) {
        if (!mounted || generation != active) return;
        setState(
          () => identity = ParticipantIdentity(
            uid: user?.uid ?? '',
            name: user?.displayName ?? '',
            phone: user?.phoneNumber ?? '',
            email: user?.email ?? '',
            emailVerified: user?.emailVerified == true,
          ),
        );
      },
      onError: (Object error) {
        if (mounted && generation == active) {
          setState(() => identity = const ParticipantIdentity());
        }
      },
    );
  }

  @override
  void didUpdateWidget(ParticipantSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role) {
      _connect();
    }
  }

  @override
  void dispose() {
    generation++;
    users?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = identity.uid.isNotEmpty ? tenantSetup : null;
    final workspace = ParticipantWorkspaceScreen(
      key: ValueKey('${widget.role}:${identity.uid}'),
      repository: repository,
      role: widget.role,
      initialTab: widget.initialTab,
      agreementId: widget.agreementId,
      identity: identity,
      issueWriter: identity.uid.isEmpty ? null : writer,
      photoReader: writer is IssuePhotoReader
          ? writer as IssuePhotoReader
          : null,
      tenantSetup: setup,
      accountGateway: identity.uid.isEmpty ? null : accountGateway,
      onAccountSignedOut: () => context.go('/login'),
      onSwitchRole: identity.uid.isEmpty
          ? null
          : () => context.push('/switch-role'),
      onManagerSupport: identity.uid.isEmpty || widget.role != 'owner'
          ? null
          : () => context.push('/owner/support'),
      onOwnerSetup: identity.uid.isEmpty || widget.role != 'owner'
          ? null
          : () => context.push('/owner/onboarding'),
      onLogout: identity.uid.isEmpty
          ? null
          : () async {
              await FirebaseAuthService.instance.signOut();
              if (context.mounted) context.go('/login');
            },
    );
    return setup == null
        ? workspace
        : TenantWorkspaceGate(
            key: ValueKey('tenant-home:${identity.uid}'),
            repository: repository,
            gateway: setup,
            child: workspace,
          );
  }
}
