import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../../domain/durations.dart';
import '../../domain/money.dart';
import '../../domain/projects.dart';
import '../common/widgets.dart';

/// Own total minutes per project (or [noProjectKey]), all time. Filled from
/// the monthly summaries (stage 7); empty until then.
final myProjectTotalsProvider = Provider<Map<String, int>>((ref) => const {});

/// Projects & rates (spec §5.4). Everyone sets their own Work/Standby rate
/// per project; admins also add, edit, archive and delete projects.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    if (ctx == null) return const SizedBox.shrink();
    final all = ref.watch(projectsProvider).value ?? const <Project>[];
    final rates = ref.watch(myRatesProvider).value ?? const {};
    final totals = ref.watch(myProjectTotalsProvider);
    final active = sortedProjects(all.where((p) => p.active));
    final archived = sortedProjects(all.where((p) => p.archived && !p.deleted));
    final canManage = ctx.isAdmin && ctx.writable;

    Widget row(Project? p) => _ProjectRow(
      key: ValueKey(p?.id ?? noProjectKey),
      project: p,
      rate: rates[p?.id ?? noProjectKey],
      totalMin: totals[p?.id ?? noProjectKey] ?? 0,
      currency: ctx.currency,
      editableRates: ctx.writable,
      canManage: canManage,
    );

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => editProject(context, ref, null),
              icon: const Icon(Icons.add),
              label: Text(l10n.projectAdd),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.projectsIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SectionHeader(l10n.projectsActive(active.length)),
          if (active.isEmpty)
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(
                ctx.isAdmin ? l10n.projectsEmptyAdmin : l10n.projectsEmpty,
              ),
            ),
          for (final p in active) row(p),
          row(null),
          if (ctx.isAdmin && archived.isNotEmpty) ...[
            SectionHeader(l10n.projectsArchived(archived.length)),
            for (final p in archived) row(p),
          ],
        ],
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  const _ProjectRow({
    super.key,
    required this.project,
    required this.rate,
    required this.totalMin,
    required this.currency,
    required this.editableRates,
    required this.canManage,
  });

  /// `null` is the "No project" row.
  final Project? project;
  final ProjectRate? rate;
  final int totalMin;
  final String currency;
  final bool editableRates;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = project;
    final theme = Theme.of(context);
    final key = p?.id ?? noProjectKey;

    void save({int? work, int? standby}) {
      final ctx = ref.read(workContextProvider);
      if (ctx == null) return;
      ref
          .read(projectsRepositoryProvider)
          .saveRate(
            ctx.orgId,
            ctx.uid,
            ProjectRate(
              projectId: key,
              workRateMinor: work ?? rate?.workRateMinor ?? 0,
              standbyRateMinor: standby ?? rate?.standbyRateMinor ?? 0,
            ),
          )
          .catchError((Object e) {
            if (context.mounted) showError(context, l10n.error(e));
          });
    }

    final title = Row(
      children: [
        ProjectDot(color: p?.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p?.name ?? l10n.noProject,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  if (p != null && p.client.isNotEmpty) p.client,
                  l10n.projectYourTotal(formatHoursMinutes(totalMin)),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (canManage && p != null) _ProjectMenu(project: p),
      ],
    );

    final fields = [
      RateField(
        label: l10n.typeWork,
        valueMinor: rate?.workRateMinor ?? 0,
        currency: currency,
        enabled: editableRates,
        onSaved: (v) => save(work: v),
      ),
      RateField(
        label: l10n.typeStandby,
        valueMinor: rate?.standbyRateMinor ?? 0,
        currency: currency,
        enabled: editableRates,
        onSaved: (v) => save(standby: v),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= Breakpoints.medium) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: title),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: fields[0]),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: fields[1]),
                  ],
                );
              }
              return Column(
                children: [
                  title,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Action { edit, archive, restore, delete }

class _ProjectMenu extends ConsumerWidget {
  const _ProjectMenu({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopupMenuButton<_Action>(
      tooltip: l10n.projectActions,
      onSelected: (a) async {
        final ctx = ref.read(workContextProvider);
        if (ctx == null) return;
        final repo = ref.read(projectsRepositoryProvider);
        Future<void> save(Project p) =>
            repo.saveProject(ctx.orgId, p, isNew: false).catchError((Object e) {
              if (context.mounted) showError(context, l10n.error(e));
            });
        switch (a) {
          case _Action.edit:
            await editProject(context, ref, project);
          case _Action.archive:
            await save(project.copyWith(archived: true));
          case _Action.restore:
            await save(project.copyWith(archived: false));
          case _Action.delete:
            final ok = await confirm(
              context,
              title: l10n.projectDeleteTitle(project.name),
              body: l10n.projectDeleteBody,
              action: l10n.delete,
            );
            if (ok) await save(project.copyWith(deleted: true));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: _Action.edit, child: Text(l10n.edit)),
        if (project.archived)
          PopupMenuItem(value: _Action.restore, child: Text(l10n.restore))
        else
          PopupMenuItem(value: _Action.archive, child: Text(l10n.archive)),
        PopupMenuItem(value: _Action.delete, child: Text(l10n.delete)),
      ],
    );
  }
}

/// An hourly rate input that saves on Enter or when focus leaves.
class RateField extends StatefulWidget {
  const RateField({
    super.key,
    required this.label,
    required this.valueMinor,
    required this.currency,
    required this.onSaved,
    this.enabled = true,
  });

  final String label;
  final int valueMinor;
  final String currency;
  final bool enabled;
  final ValueChanged<int> onSaved;

  @override
  State<RateField> createState() => _RateFieldState();
}

class _RateFieldState extends State<RateField> {
  late final _controller = TextEditingController(
    text: formatMinorPlain(widget.valueMinor),
  );
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(RateField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.valueMinor != widget.valueMinor) {
      _controller.text = formatMinorPlain(widget.valueMinor);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = parseRateMinor(_controller.text);
    setState(() => _error = v == null ? context.l10n.rateInvalid : null);
    if (v == null) return;
    _controller.text = formatMinorPlain(v);
    if (v != widget.valueMinor) widget.onSaved(v);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    enabled: widget.enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _commit(),
    style: const TextStyle(fontFeatures: tabularFigures),
    decoration: InputDecoration(
      labelText: widget.label,
      suffixText: context.l10n.perHour(widget.currency),
      errorText: _error,
      isDense: true,
    ),
  );
}

/// Add ([project] `null`) or edit a project (admins).
Future<void> editProject(
  BuildContext context,
  WidgetRef ref,
  Project? project,
) async {
  final ctx = ref.read(workContextProvider);
  if (ctx == null) return;
  final repo = ref.read(projectsRepositoryProvider);
  final result = await showDialog<Project>(
    context: context,
    builder: (_) => _ProjectDialog(
      project:
          project ??
          Project(
            id: repo.newProjectId(ctx.orgId),
            name: '',
            color:
                projectPalette[(ref.read(projectsProvider).value?.length ?? 0) %
                    projectPalette.length],
          ),
      isNew: project == null,
    ),
  );
  if (result == null) return;
  try {
    await repo.saveProject(ctx.orgId, result, isNew: project == null);
  } catch (e) {
    if (context.mounted) showError(context, context.l10n.error(e));
  }
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({required this.project, required this.isNew});

  final Project project;
  final bool isNew;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project.name);
  late final _client = TextEditingController(text: widget.project.client);
  late int _color = widget.project.color;

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.project.copyWith(
        name: _name.text.trim(),
        client: _client.text.trim(),
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.isNew ? l10n.projectAdd : l10n.projectEdit),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: maxProjectNameLength,
                decoration: InputDecoration(labelText: l10n.projectName),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              TextFormField(
                controller: _client,
                maxLength: maxProjectNameLength,
                decoration: InputDecoration(labelText: l10n.projectClient),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.projectColor,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, c) in projectPalette.indexed)
                    Semantics(
                      label: l10n.projectColorN(i + 1),
                      selected: c == _color,
                      button: true,
                      child: InkResponse(
                        onTap: () => setState(() => _color = c),
                        radius: 22,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: c == _color
                                ? Border.all(
                                    width: 3,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  )
                                : null,
                          ),
                          child: c == _color
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
