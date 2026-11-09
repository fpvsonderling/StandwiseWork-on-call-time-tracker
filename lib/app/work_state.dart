import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/sync.dart';
import '../domain/date_ranges.dart';
import '../domain/models.dart';
import '../domain/projects.dart';
import '../domain/reports.dart';
import '../domain/summaries.dart';
import '../domain/timer.dart';
import 'session.dart';

/// Who is working where: the signed-in member in the organization in use.
class WorkContext {
  const WorkContext({
    required this.orgId,
    required this.uid,
    required this.membership,
    required this.settings,
    required this.writable,
  });

  final String orgId;
  final String uid;
  final Membership membership;
  final OrgSettings settings;

  /// Active member of a trial/active organization (spec §3.2).
  final bool writable;

  bool get isAdmin => membership.isAdmin;
  String get currency => settings.currency;
}

/// `null` until a session with an organization is ready.
final workContextProvider = Provider<WorkContext?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session is! SessionReady) return null;
  final org = ref.watch(currentOrgProvider).value;
  return WorkContext(
    orgId: session.orgId,
    uid: session.user.uid,
    membership: session.membership,
    settings: org?.settings ?? const OrgSettings(),
    writable: session.membership.isActive && (org?.status.writable ?? true),
  );
});

/// All projects of the organization in use (including archived/deleted).
final projectsProvider = StreamProvider<List<Project>>((ref) {
  final orgId = ref.watch(workContextProvider.select((c) => c?.orgId));
  if (orgId == null) return Stream.value(const []);
  return ref.watch(projectsRepositoryProvider).watchProjects(orgId);
});

final projectsByIdProvider = Provider<Map<String, Project>>(
  (ref) => {
    for (final p in ref.watch(projectsProvider).value ?? const <Project>[])
      p.id: p,
  },
);

/// Projects offered in pickers: active, sorted by name.
final activeProjectsProvider = Provider<List<Project>>(
  (ref) => sortedProjects(
    (ref.watch(projectsProvider).value ?? const <Project>[]).where(
      (p) => p.active,
    ),
  ),
);

/// The signed-in member's own rates, keyed by project ID.
final myRatesProvider = StreamProvider<Map<String, ProjectRate>>((ref) {
  final ctx = ref.watch(
    workContextProvider.select((c) => c == null ? null : (c.orgId, c.uid)),
  );
  if (ctx == null) return Stream.value(const {});
  return ref.watch(projectsRepositoryProvider).watchRates(ctx.$1, ctx.$2);
});

/// Another member's current rates (admins reading the team, D-044).
final memberRatesProvider =
    StreamProvider.family<Map<String, ProjectRate>, (String, String)>(
      (ref, key) =>
          ref.watch(projectsRepositoryProvider).watchRates(key.$1, key.$2),
    );

final syncStateProvider = StreamProvider<SyncState>(
  (ref) => ref.watch(syncTrackerProvider).states,
);

/// The signed-in member's running timer (spec §5.1).
final timerProvider = StreamProvider<RunningTimer?>((ref) {
  final ctx = ref.watch(
    workContextProvider.select((c) => c == null ? null : (c.orgId, c.uid)),
  );
  if (ctx == null) return Stream.value(null);
  return ref.watch(entriesRepositoryProvider).watchTimer(ctx.$1, ctx.$2);
});

/// How many days of history the Timer list shows (spec §5.1: 14, "Show
/// earlier days" adds 14 more).
class HistoryDays extends Notifier<int> {
  static const step = 14;

  @override
  int build() {
    // Back to two weeks when the organization changes.
    ref.watch(workContextProvider.select((c) => c?.orgId));
    return step;
  }

  void more() => state += step;
}

final historyDaysProvider = NotifierProvider<HistoryDays, int>(HistoryDays.new);

/// Start of the Timer list: [historyDaysProvider] days back, and never later
/// than the start of the current week (the week summary needs it).
DateTime historyStart(DateTime now, int days, int weekStart) {
  final back = DateTime(now.year, now.month, now.day - (days - 1));
  final week = startOfWeek(now, weekStart: weekStart);
  return back.isBefore(week) ? back : week;
}

/// The signed-in member's own entries for the Timer screen.
final myRecentEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final ctx = ref.watch(workContextProvider);
  if (ctx == null) return Stream.value(const []);
  final days = ref.watch(historyDaysProvider);
  final from = historyStart(DateTime.now(), days, ctx.settings.weekStart);
  return ref
      .watch(entriesRepositoryProvider)
      .watchEntries(ctx.orgId, uid: ctx.uid, from: from);
});

/// Writes the server rejected after the fact (shown as a SnackBar).
final writeErrorsProvider = StreamProvider<Object>(
  (ref) => ref.watch(syncTrackerProvider).errors,
);

/// Members of an organization (admins only; rules reject others).
final orgMembersProvider = StreamProvider.family<List<Membership>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).watchMembers(orgId),
);

/// The signed-in member's own monthly summaries, all months.
final mySummariesProvider = StreamProvider<List<MonthSummary>>((ref) {
  final ctx = ref.watch(
    workContextProvider.select((c) => c == null ? null : (c.orgId, c.uid)),
  );
  if (ctx == null) return Stream.value(const []);
  return ref
      .watch(entriesRepositoryProvider)
      .watchSummaries(ctx.$1, uid: ctx.$2);
});

/// Own total minutes per project ID (or [noProjectKey]), all time, for
/// Projects & rates (spec §5.4).
final myProjectTotalsProvider = Provider<Map<String, int>>((ref) {
  final totals = <String, int>{};
  for (final s
      in ref.watch(mySummariesProvider).value ?? const <MonthSummary>[]) {
    for (final c in s.cells()) {
      final key = c.projectId ?? noProjectKey;
      totals[key] = (totals[key] ?? 0) + c.totalMin;
    }
  }
  return totals;
});

/// Team cells (every member, every project) for the months [range] touches,
/// limited to days inside [range] (spec §5.5: Team reads summaries).
final teamCellsProvider = StreamProvider.family<List<ReportCell>, DateRange>((
  ref,
  range,
) {
  final orgId = ref.watch(workContextProvider.select((c) => c?.orgId));
  if (orgId == null) return Stream.value(const []);
  return ref
      .watch(entriesRepositoryProvider)
      .watchSummaries(orgId, uid: null, monthKeys: monthKeysIn(range))
      .map(
        (summaries) => [
          for (final s in summaries)
            ...s.cells().where((c) => range.contains(c.day)),
        ],
      );
});
