import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/work_state.dart';
import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../domain/durations.dart';
import '../../domain/models.dart';
import '../../domain/projects.dart';
import '../../domain/timer.dart';

/// Timer and entry operations (spec §5.1). All are local-first Firestore
/// writes, so they work offline.
class TimerActions {
  TimerActions(this._ref);

  final Ref _ref;

  WorkContext get _ctx {
    final ctx = _ref.read(workContextProvider);
    if (ctx == null) throw const AppException(AppErrorCode.unknown, 'no org');
    if (!ctx.writable) throw const AppException(AppErrorCode.orgReadOnly);
    return ctx;
  }

  int _rate(String? projectId, EntryType type) => currentRate(
    _ref.read(myRatesProvider).value ?? const {},
    projectId,
    type,
  );

  /// The entry a running [timer] becomes when stopped at [now], or `null`
  /// when it ran for no time at all.
  TimeEntry? entryFromTimer(RunningTimer timer, String orgId, DateTime now) {
    final end = timer.stopTime(now);
    if (!end.isAfter(timer.start)) return null;
    return TimeEntry(
      id: _ref.read(entriesRepositoryProvider).newEntryId(orgId),
      uid: _ctx.uid,
      projectId: timer.projectId,
      type: timer.type,
      rateMinor: _rate(timer.projectId, timer.type),
      start: timer.start,
      end: end,
      description: timer.description.trim(),
    );
  }

  /// Starts a timer now; a running one is stopped and saved first (spec:
  /// at most one per person, in one batched write).
  Future<void> start({
    required String description,
    required String? projectId,
    required EntryType type,
    DateTime? now,
  }) {
    final ctx = _ctx;
    if (projectId == null) {
      throw const AppException(AppErrorCode.projectRequired);
    }
    final at = now ?? DateTime.now();
    final running = _ref.read(timerProvider).value;
    return _ref
        .read(entriesRepositoryProvider)
        .startTimer(
          ctx.orgId,
          ctx.uid,
          RunningTimer(
            start: at,
            projectId: projectId,
            type: type,
            description: description.trim(),
          ),
          stopped: running == null
              ? null
              : entryFromTimer(running, ctx.orgId, at),
        );
  }

  Future<void> stop({DateTime? now}) {
    final ctx = _ctx;
    final running = _ref.read(timerProvider).value;
    if (running == null) return Future.value();
    return _ref
        .read(entriesRepositoryProvider)
        .stopTimer(
          ctx.orgId,
          ctx.uid,
          entryFromTimer(running, ctx.orgId, now ?? DateTime.now()),
        );
  }

  /// Changes what the running timer is tracking.
  Future<void> updateRunning({
    String? description,
    String? projectId,
    bool clearProject = false,
    EntryType? type,
  }) {
    final ctx = _ctx;
    final t = _ref.read(timerProvider).value;
    if (t == null) return Future.value();
    return _ref
        .read(entriesRepositoryProvider)
        .updateTimer(
          ctx.orgId,
          ctx.uid,
          RunningTimer(
            start: t.start,
            projectId: clearProject ? null : projectId ?? t.projectId,
            type: type ?? t.type,
            description: description ?? t.description,
          ),
        );
  }

  /// "Continue": a new timer with the entry's description, project, type.
  Future<void> continueEntry(TimeEntry e) => start(
    description: e.description,
    projectId: _activeOrNull(e.projectId),
    type: e.type,
  );

  String? _activeOrNull(String? projectId) {
    if (projectId == null) return null;
    final p = _ref.read(projectsByIdProvider)[projectId];
    return p != null && p.active ? projectId : null;
  }

  /// Adds a manual entry; throws [SpanError] problems as [ArgumentError].
  Future<void> addManual({
    required DateTime start,
    required DateTime end,
    required String description,
    required String? projectId,
    required EntryType type,
  }) {
    final ctx = _ctx;
    if (projectId == null) {
      throw const AppException(AppErrorCode.projectRequired);
    }
    final repo = _ref.read(entriesRepositoryProvider);
    return repo.addEntry(
      ctx.orgId,
      TimeEntry(
        id: repo.newEntryId(ctx.orgId),
        uid: ctx.uid,
        projectId: projectId,
        type: type,
        rateMinor: _rate(projectId, type),
        start: start,
        end: end,
        description: description.trim(),
      ),
    );
  }

  Future<void> update(TimeEntry entry) =>
      _ref.read(entriesRepositoryProvider).updateEntry(_ctx.orgId, entry);

  /// An admin saves a change to someone else's [entry]. The owner sees who
  /// made it and the optional [comment] (D-050). The name must match the
  /// admin's membership exactly (firestore.rules).
  Future<void> editAsAdmin(TimeEntry entry, {required String comment}) {
    final ctx = _ctx;
    if (!ctx.isAdmin) throw const AppException(AppErrorCode.notAdmin);
    final m = ctx.membership;
    return _ref
        .read(entriesRepositoryProvider)
        .editEntryAsAdmin(
          ctx.orgId,
          entry,
          EntryEdit(
            byUid: ctx.uid,
            byName: '${m.firstName} ${m.lastName}',
            comment: comment.trim(),
          ),
        );
  }

  /// The current rate of [uid] (an admin editing a member's entry).
  int rateForMember(String uid, String? projectId, EntryType type) {
    if (uid == _ref.read(workContextProvider)?.uid) {
      return _rate(projectId, type);
    }
    final orgId = _ref.read(workContextProvider)?.orgId;
    if (orgId == null) return 0;
    return currentRate(
      _ref.read(memberRatesProvider((orgId, uid))).value ?? const {},
      projectId,
      type,
    );
  }

  Future<void> setDeleted(String entryId, {required bool deleted}) => _ref
      .read(entriesRepositoryProvider)
      .setDeleted(_ctx.orgId, entryId, deleted: deleted);

  /// The rate a changed project/type gets (spec §5.2).
  int rateFor(String? projectId, EntryType type) => _rate(projectId, type);

  /// Admins: three "Sample:" projects with rates and a few days of entries.
  Future<void> loadSampleData({DateTime? now}) async {
    final ctx = _ctx;
    final projectsRepo = _ref.read(projectsRepositoryProvider);
    final entriesRepo = _ref.read(entriesRepositoryProvider);
    final today = now ?? DateTime.now();
    const samples = [
      ('Website relaunch', 'Northwind', 0, 6500, 2000),
      ('On-call support', 'Contoso', 2, 7000, 2500),
      ('Maintenance', '', 6, 5500, 1500),
    ];
    final ids = <String>[];
    for (final (name, client, color, work, standby) in samples) {
      final id = projectsRepo.newProjectId(ctx.orgId);
      ids.add(id);
      await projectsRepo.saveProject(
        ctx.orgId,
        Project(
          id: id,
          name: '$sampleProjectPrefix$name',
          client: client,
          color: projectPalette[color],
        ),
        isNew: true,
      );
      await projectsRepo.saveRate(
        ctx.orgId,
        ctx.uid,
        ProjectRate(
          projectId: id,
          workRateMinor: work,
          standbyRateMinor: standby,
        ),
      );
    }
    // (days ago, project, type, start hour, hours, description)
    const plan = [
      (1, 0, EntryType.work, 8, 4, 'Landing page layout'),
      (1, 1, EntryType.standby, 18, 12, 'Weekend standby'),
      (2, 0, EntryType.work, 9, 6, 'Contact form and tests'),
      (2, 2, EntryType.work, 15, 2, 'Server updates'),
      (3, 1, EntryType.work, 22, 3, 'Database incident'),
      (4, 0, EntryType.work, 8, 5, 'Design review'),
    ];
    final rates = [for (final s in samples) (s.$4, s.$5)];
    for (final (daysAgo, p, type, hour, hours, text) in plan) {
      final start = DateTime(
        today.year,
        today.month,
        today.day - daysAgo,
        hour,
      );
      await entriesRepo.addEntry(
        ctx.orgId,
        TimeEntry(
          id: entriesRepo.newEntryId(ctx.orgId),
          uid: ctx.uid,
          projectId: ids[p],
          type: type,
          rateMinor: type == EntryType.work ? rates[p].$1 : rates[p].$2,
          start: start,
          end: start.add(Duration(hours: hours)),
          description: text,
        ),
      );
    }
  }

  /// Deletes the sample projects and the loaded entries that use them.
  Future<void> removeSampleData() async {
    final ctx = _ctx;
    final samples = (_ref.read(projectsProvider).value ?? const <Project>[])
        .where((p) => p.isSample && !p.deleted)
        .toList();
    final ids = samples.map((p) => p.id).toSet();
    for (final e
        in _ref.read(myRecentEntriesProvider).value ?? const <TimeEntry>[]) {
      if (ids.contains(e.projectId)) {
        await setDeleted(e.id, deleted: true);
      }
    }
    for (final p in samples) {
      await _ref
          .read(projectsRepositoryProvider)
          .saveProject(ctx.orgId, p.copyWith(deleted: true), isNew: false);
    }
  }
}

final timerActionsProvider = Provider<TimerActions>(TimerActions.new);

/// Validation for a manual or edited entry.
SpanError? entrySpanError(DateTime start, DateTime end) =>
    validateSpan(start, end);
