import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/trustkeyper_ui.dart';
import '../../journeys/presentation/guided_journey_screen.dart';
import '../data/experience_catalog.dart';
import '../data/implemented_experiences.dart';

class ExperienceHubScreen extends StatefulWidget {
  const ExperienceHubScreen({super.key});

  @override
  State<ExperienceHubScreen> createState() => _ExperienceHubScreenState();
}

class _ExperienceHubScreenState extends State<ExperienceHubScreen> {
  String audience = 'All';

  @override
  Widget build(BuildContext context) {
    final active = ExperienceCatalog.all
        .where((item) => !item.archived)
        .where((item) => audience == 'All' || item.audience.contains(audience))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('All product journeys'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/roles'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Implemented journeys open their working screens. Other journeys are not connected yet and cannot be acceptance-tested. Discarded designs on pages 13 and 14 are excluded.',
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in [
                  'All',
                  'Broker',
                  'Owner',
                  'Tenant',
                  'Admin',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(value),
                      selected: audience == value,
                      onSelected: (_) => setState(() => audience = value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final experience in active) ...[
            TkChoiceCard(
              icon: experience.icon,
              title:
                  '${experience.page.toString().padLeft(2, '0')} · ${experience.title}',
              subtitle: '${experience.audience} · ${experience.description}',
              badge: implementedExperiences.containsKey(experience.id)
                  ? 'Working entry'
                  : 'Not connected',
              onTap: () => _open(context, experience),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Archive: pages 13 and 14 are superseded and are not shipped.',
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, ExperienceDefinition experience) {
    final entries = implementedExperiences[experience.id];
    context.push(
      entries?.length == 1
          ? entries!.single.route
          : '/experience/${experience.id}',
    );
  }
}

class ExperienceFlowScreen extends StatelessWidget {
  const ExperienceFlowScreen({required this.experienceId, super.key});

  final String experienceId;

  @override
  Widget build(BuildContext context) {
    final experience = ExperienceCatalog.byId(experienceId);
    final entries = implementedExperiences[experienceId];
    if (experience != null && entries != null) {
      return TkPage(
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/experiences'),
        title: experience.title,
        subtitle:
            'Open a real account and choose your saved home. Each operation still checks your verified role and access. Secure approval or document uploads start from the broker’s personal link.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TkPrimaryButton(
                  label: entry.label,
                  onPressed: () => context.push(entry.route),
                ),
              ),
          ],
        ),
      );
    }
    if (experience == null || experience.steps.isEmpty) {
      return TkPage(
        onBack: () => context.pop(),
        title: 'Journey not found',
        subtitle: 'Return to all product journeys and choose another flow.',
        child: TkPrimaryButton(
          label: 'View all journeys',
          onPressed: () => context.go('/experiences'),
        ),
      );
    }
    return GuidedJourneyScreen(
      journeyTitle: experience.title,
      steps: experience.steps,
      completionRoute: '/experiences',
    );
  }
}
