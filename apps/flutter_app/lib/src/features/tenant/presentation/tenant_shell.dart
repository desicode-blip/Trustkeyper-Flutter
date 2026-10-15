import 'package:flutter/material.dart';
import '../../participants/data/participant_repository.dart';
import '../../participants/presentation/participant_session_screen.dart';

class TenantShell extends StatelessWidget {
  const TenantShell({this.repository, this.initialTab = 0, super.key});
  final ParticipantRepository? repository;
  final int initialTab;
  @override
  Widget build(BuildContext context) => ParticipantSessionScreen(
    role: 'tenant',
    repository: repository,
    initialTab: initialTab,
  );
}
