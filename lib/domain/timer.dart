/// The running timer (spec §5.1, `orgs/{orgId}/timers/{uid}`).
library;

import 'durations.dart';
import 'models.dart';

class RunningTimer {
  const RunningTimer({
    required this.start,
    this.projectId,
    this.type = EntryType.work,
    this.description = '',
  });

  final DateTime start;
  final String? projectId;
  final EntryType type;
  final String description;

  /// Elapsed time, computed from [start] so it survives sleep and offline.
  Duration elapsed(DateTime now) => elapsedSince(start, now);

  /// The end time when stopping at [now]: never more than the 24-hour entry
  /// limit after [start] (spec §3.2).
  DateTime stopTime(DateTime now) {
    final limit = start.add(const Duration(minutes: maxEntryMinutes));
    return now.isAfter(limit) ? limit : now;
  }
}
