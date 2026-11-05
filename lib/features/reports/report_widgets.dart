import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../domain/date_ranges.dart';
import '../../domain/durations.dart';
import '../../domain/projects.dart';
import '../../domain/reports.dart';
import '../common/format.dart';
import '../common/widgets.dart';

/// The chosen report range: a preset, or a custom range (`preset == null`).
class ReportRange {
  const ReportRange(this.range, [this.preset]);

  factory ReportRange.preset(
    RangePreset preset, {
    int weekStart = DateTime.monday,
    DateTime? now,
  }) => ReportRange(
    presetRange(preset, now ?? DateTime.now(), weekStart: weekStart),
    preset,
  );

  final DateRange range;
  final RangePreset? preset;

  DateTime get lastDay =>
      DateTime(range.end.year, range.end.month, range.end.day - 1);
}

/// Range chips (This week … Custom range) plus the dates shown.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.value,
    required this.weekStart,
    required this.onChanged,
  });

  final ReportRange value;
  final int weekStart;
  final ValueChanged<ReportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      RangePreset.thisWeek: l10n.rangeThisWeek,
      RangePreset.lastWeek: l10n.rangeLastWeek,
      RangePreset.thisMonth: l10n.rangeThisMonth,
      RangePreset.lastMonth: l10n.rangeLastMonth,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in RangePreset.values)
          ChoiceChip(
            label: Text(labels[p]!),
            selected: value.preset == p,
            onSelected: (_) =>
                onChanged(ReportRange.preset(p, weekStart: weekStart)),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(
            value.preset == null
                ? '${dateLabel(context, value.range.start)} – ${dateLabel(context, value.lastDay)}'
                : l10n.rangeCustom,
          ),
          selected: value.preset == null,
          onSelected: (_) async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 366)),
              initialDateRange: DateTimeRange(
                start: value.range.start,
                end: value.lastDay,
              ),
            );
            if (picked != null) {
              onChanged(ReportRange(customRange(picked.start, picked.end)));
            }
          },
        ),
      ],
    );
  }
}

/// All projects / No project / one project (archived and deleted included,
/// since old entries still use them).
class ProjectFilterField extends StatelessWidget {
  const ProjectFilterField({
    super.key,
    required this.value,
    required this.projects,
    required this.onChanged,
  });

  final String? value;
  final List<Project> projects;
  final ValueChanged<String?> onChanged;

  static const _all = '\u0000all';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sorted = sortedProjects(projects.where((p) => !p.deleted));
    return DropdownButtonFormField<String>(
      initialValue: value ?? _all,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.project, isDense: true),
      onChanged: (v) => onChanged(v == _all ? null : v),
      items: [
        DropdownMenuItem(value: _all, child: Text(l10n.allProjects)),
        DropdownMenuItem(value: noProjectKey, child: Text(l10n.noProject)),
        for (final p in sorted)
          DropdownMenuItem(
            value: p.id,
            child: Row(
              children: [
                ProjectDot(color: p.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.archived ? '${p.name} (${l10n.archived})' : p.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Total, Work, Standby and Amount tiles (spec §5.3).
class ReportTiles extends StatelessWidget {
  const ReportTiles({super.key, required this.totals, required this.currency});

  final Totals totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = context.statusColors;
    Widget tile(String title, String value, String? sub, Color? color) =>
        SizedBox(
          width: 170,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (color != null) ...[
                        Container(width: 10, height: 10, color: color),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontFeatures: tabularFigures),
                  ),
                  if (sub != null)
                    Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        tile(
          l10n.total,
          formatHoursMinutes(totals.totalMin),
          l10n.totalDetail(formatDecimalHours(totals.totalMin), totals.count),
          null,
        ),
        tile(
          l10n.typeWork,
          formatHoursMinutes(totals.workMin),
          null,
          status.work,
        ),
        tile(
          l10n.typeStandby,
          formatHoursMinutes(totals.standbyMin),
          null,
          status.standby,
        ),
        tile(
          l10n.amount,
          money(context, totals.amountMinor, currency),
          null,
          null,
        ),
      ],
    );
  }
}

/// Hours per day (or per week above 62 days), stacked by project.
class ReportChart extends StatelessWidget {
  const ReportChart({
    super.key,
    required this.cells,
    required this.range,
    required this.projects,
    required this.weekStart,
  });

  final List<ReportCell> cells;
  final DateRange range;
  final Map<String, Project> projects;
  final int weekStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final buckets = chartBuckets(cells, range, weekStart: weekStart);
    final weekly = useWeeklyBuckets(range);
    final maxMin = buckets.fold(0, (m, b) => b.totalMin > m ? b.totalMin : m);
    final maxY = ((maxMin / 60).ceil()).clamp(1, 1 << 20).toDouble();
    final noProjectColor = theme.colorScheme.outline;
    Color colorOf(String? id) {
      final p = id == null ? null : projects[id];
      return p == null || p.deleted ? noProjectColor : Color(p.color);
    }

    // Stable stacking order: by project name.
    String nameOf(String? id) => projectLabel(l10n, projects[id], id);
    final locale = localeOf(context);
    final dayFmt = DateFormat.Md(locale);
    final labelEvery = (buckets.length / 8).ceil().clamp(1, 1000);

    return Semantics(
      label: weekly ? l10n.chartLabelWeeks : l10n.chartLabelDays,
      child: SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, 1e9),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                axisNameWidget: Text(
                  l10n.hoursAxis,
                  style: theme.textTheme.labelSmall,
                ),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: (maxY / 4).ceilToDouble().clamp(1, 1e9),
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      v.toInt().toString(),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= buckets.length || i % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        dayFmt.format(buckets[i].start),
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                getTooltipItem: (group, _, _, _) {
                  final b = buckets[group.x];
                  final lines = [
                    weekly
                        ? l10n.weekOf(dateLabel(context, b.start))
                        : dateLabel(context, b.start),
                    '${l10n.total}: ${formatHoursMinutes(b.totalMin)}',
                    for (final MapEntry(:key, :value) in b.minutes.entries)
                      '${nameOf(key)}: ${formatHoursMinutes(value)}',
                  ];
                  return BarTooltipItem(
                    lines.join('\n'),
                    TextStyle(color: theme.colorScheme.onInverseSurface),
                  );
                },
              ),
            ),
            barGroups: [
              for (final (i, b) in buckets.indexed)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: b.totalMin / 60,
                      width: (280 / buckets.length).clamp(3, 18),
                      borderRadius: BorderRadius.zero,
                      color: Colors.transparent,
                      rodStackItems: _stack(b, colorOf, nameOf),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static List<BarChartRodStackItem> _stack(
    ChartBucket b,
    Color Function(String?) colorOf,
    String Function(String?) nameOf,
  ) {
    final keys = b.minutes.keys.toList()
      ..sort((x, y) => nameOf(x).compareTo(nameOf(y)));
    var y = 0.0;
    return [
      for (final k in keys)
        BarChartRodStackItem(y, y += b.minutes[k]! / 60, colorOf(k)),
    ];
  }
}

/// Project, Client, Work, Standby, Total, Share, Amount (spec §5.3).
class ProjectTable extends StatelessWidget {
  const ProjectTable({
    super.key,
    required this.cells,
    required this.projects,
    required this.currency,
  });

  final List<ReportCell> cells;
  final Map<String, Project> projects;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = projectRows(cells);
    final all = totalsOfCells(cells);
    const num = TextStyle(fontFeatures: tabularFigures);
    String share(int min) => all.totalMin == 0
        ? '–'
        : '${(min * 100 / all.totalMin).toStringAsFixed(0)}%';
    DataCell n(String v, {bool bold = false}) => DataCell(
      Text(v, style: bold ? num.copyWith(fontWeight: FontWeight.bold) : num),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        columns: [
          DataColumn(label: Text(l10n.project)),
          DataColumn(label: Text(l10n.client)),
          DataColumn(label: Text(l10n.typeWork), numeric: true),
          DataColumn(label: Text(l10n.typeStandby), numeric: true),
          DataColumn(label: Text(l10n.total), numeric: true),
          DataColumn(label: Text(l10n.share), numeric: true),
          DataColumn(label: Text(l10n.amount), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProjectDot(
                        color: projects[r.projectId]?.deleted == false
                            ? projects[r.projectId]!.color
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        projectLabel(l10n, projects[r.projectId], r.projectId),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(projects[r.projectId]?.client ?? '')),
                n(formatHoursMinutes(r.totals.workMin)),
                n(formatHoursMinutes(r.totals.standbyMin)),
                n(formatHoursMinutes(r.totals.totalMin)),
                n(share(r.totals.totalMin)),
                n(money(context, r.totals.amountMinor, currency)),
              ],
            ),
          DataRow(
            cells: [
              DataCell(
                Text(
                  l10n.total,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const DataCell(Text('')),
              n(formatHoursMinutes(all.workMin), bold: true),
              n(formatHoursMinutes(all.standbyMin), bold: true),
              n(formatHoursMinutes(all.totalMin), bold: true),
              n(all.totalMin == 0 ? '–' : '100%', bold: true),
              n(money(context, all.amountMinor, currency), bold: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Labels for CSV exports from the UI language.
CsvLabels csvLabels(AppLocalizations l10n) => CsvLabels(
  headers: [
    l10n.csvDate,
    l10n.csvStart,
    l10n.csvEnd,
    l10n.csvDuration,
    l10n.csvHours,
    l10n.csvType,
    l10n.rate,
    l10n.amount,
    l10n.project,
    l10n.client,
    l10n.description,
  ],
  teamHeaders: [l10n.profileFirstName, l10n.profileLastName, l10n.csvEmail],
  work: l10n.typeWork,
  standby: l10n.typeStandby,
  noProject: l10n.noProject,
  deletedProject: l10n.noProjectDeleted,
);
