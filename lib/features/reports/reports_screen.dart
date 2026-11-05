import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../../domain/date_ranges.dart';
import '../../domain/models.dart';
import '../../domain/reports.dart';
import '../common/csv_export.dart';
import '../common/widgets.dart';
import '../placeholder/placeholder_screens.dart';
import 'report_widgets.dart';

/// The signed-in member's own entries starting in a range.
final myEntriesInRangeProvider =
    StreamProvider.family<List<TimeEntry>, DateRange>((ref, range) {
      final ctx = ref.watch(
        workContextProvider.select((c) => c == null ? null : (c.orgId, c.uid)),
      );
      if (ctx == null) return Stream.value(const []);
      return ref
          .watch(entriesRepositoryProvider)
          .watchEntries(ctx.$1, uid: ctx.$2, from: range.start, to: range.end);
    });

/// My reports (spec §5.3): ranges, project filter, tiles, chart, project
/// table and CSV.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRange? _range;
  String? _project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    if (ctx == null) return const ReportsPlaceholder();
    final range =
        _range ??
        ReportRange.preset(
          RangePreset.thisWeek,
          weekStart: ctx.settings.weekStart,
        );
    final state = ref.watch(myEntriesInRangeProvider(range.range));
    final entries = (state.value ?? const <TimeEntry>[])
        .where((e) => matchesProject(e, _project))
        .toList();
    final projects = ref.watch(projectsByIdProvider);

    Future<void> export() async {
      final csv = entriesCsv(
        entries: entries,
        projects: projects,
        settings: ctx.settings,
        labels: csvLabels(l10n),
      );
      try {
        await ref
            .read(csvSaverProvider)
            .save(
              context,
              csvFileName('my-hours', range.range.start, range.lastDay),
              csv,
            );
      } catch (e) {
        if (context.mounted) showError(context, l10n.error(e));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RangeBar(
          value: range,
          weekStart: ctx.settings.weekStart,
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: ProjectFilterField(
                value: _project,
                projects: projects.values.toList(),
                onChanged: (p) => setState(() => _project = p),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: entries.isEmpty ? null : export,
              icon: const Icon(Icons.download),
              label: Text(l10n.exportCsv),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.isLoading && !state.hasValue)
          const Center(child: CircularProgressIndicator())
        else ...[
          ReportTiles(totals: totalsOf(entries), currency: ctx.currency),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.reportEmpty, textAlign: TextAlign.center),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: ReportChart(
                  cells: entries.map(cellOf).toList(),
                  range: range.range,
                  projects: projects,
                  weekStart: ctx.settings.weekStart,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ProjectTable(
                cells: entries.map(cellOf).toList(),
                projects: projects,
                currency: ctx.currency,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
