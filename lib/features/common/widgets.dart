import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../domain/projects.dart';

/// A section title inside a list.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The project's color dot.
class ProjectDot extends StatelessWidget {
  const ProjectDot({super.key, this.color, this.size = 12});

  /// ARGB; `null` for "No project" (an outlined dot).
  final int? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c == null ? null : Color(c),
        border: c == null
            ? Border.all(color: Theme.of(context).colorScheme.outline)
            : null,
      ),
    );
  }
}

/// "No project", "No project (deleted)" or the project's name.
String projectLabel(AppLocalizations l10n, Project? project, String? id) {
  if (id == null) return l10n.noProject;
  if (project == null || project.deleted) return l10n.noProjectDeleted;
  return project.name;
}

/// Asks to confirm a destructive action.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
