import 'package:flutter/material.dart';
import '../../participants/data/participant_repository.dart';
import '../../participants/presentation/participant_session_screen.dart';

class OwnerShell extends StatelessWidget {
  const OwnerShell({
    this.repository,
    this.initialTab = 0,
    this.agreementId,
    super.key,
  });
  final ParticipantRepository? repository;
  final int initialTab;
  final String? agreementId;
  @override
  Widget build(BuildContext context) => ParticipantSessionScreen(
    role: 'owner',
    repository: repository,
    initialTab: initialTab,
    agreementId: agreementId,
  );
}
