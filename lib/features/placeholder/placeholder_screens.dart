import 'package:flutter/material.dart';

import '../../app/l10n.dart';

/// Stage 1 stand-ins for the tabs built in later stages.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.body,
    required this.stage,
  });

  final IconData icon;
  final String title;
  final String body;
  final int stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.comingInStage(stage),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimerPlaceholder extends StatelessWidget {
  const TimerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => _Placeholder(
    icon: Icons.timer_outlined,
    title: context.l10n.timerPlaceholderTitle,
    body: context.l10n.timerPlaceholderBody,
    stage: 5,
  );
}

class ReportsPlaceholder extends StatelessWidget {
  const ReportsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => _Placeholder(
    icon: Icons.bar_chart_outlined,
    title: context.l10n.reportsPlaceholderTitle,
    body: context.l10n.reportsPlaceholderBody,
    stage: 6,
  );
}

class ProjectsPlaceholder extends StatelessWidget {
  const ProjectsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => _Placeholder(
    icon: Icons.folder_outlined,
    title: context.l10n.projectsPlaceholderTitle,
    body: context.l10n.projectsPlaceholderBody,
    stage: 4,
  );
}

class TeamPlaceholder extends StatelessWidget {
  const TeamPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => _Placeholder(
    icon: Icons.groups_outlined,
    title: context.l10n.teamPlaceholderTitle,
    body: context.l10n.teamPlaceholderBody,
    stage: 7,
  );
}
