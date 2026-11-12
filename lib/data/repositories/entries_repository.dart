import '../../domain/models.dart';
import '../../domain/summaries.dart';
import '../../domain/timer.dart';

/// Time entries and the running timer (spec §5.1, §6). Plain Firestore
/// writes protected by rules: they return once the local cache has them and
/// sync later when offline (spec §8).
abstract interface class EntriesRepository {
  Stream<RunningTimer?> watchTimer(String orgId, String uid);

  /// Starts [timer]. If another timer was running, pass the entry it becomes
  /// as [stopped]: both happen in one batched write.
  Future<void> startTimer(
    String orgId,
    String uid,
    RunningTimer timer, {
    TimeEntry? stopped,
  });

  /// Changes the running timer's description, project or type.
  Future<void> updateTimer(String orgId, String uid, RunningTimer timer);

  /// Deletes the timer and saves [entry] (if any) in one batched write.
  Future<void> stopTimer(String orgId, String uid, TimeEntry? entry);

  /// A new client-generated entry ID (so offline writes are idempotent).
  String newEntryId(String orgId);

  Future<void> addEntry(String orgId, TimeEntry entry);

  Future<void> updateEntry(String orgId, TimeEntry entry);

  /// An admin changes someone else's [entry]; [edit] (who and why) is saved
  /// with it so the owner can see it (D-051).
  Future<void> editEntryAsAdmin(String orgId, TimeEntry entry, EntryEdit edit);

  /// Soft delete ([deleted] true) or undo.
  Future<void> setDeleted(
    String orgId,
    String entryId, {
    required bool deleted,
  });

  /// Entries that start in `[from, to)`, newest first, without deleted ones.
  /// [uid] limits them to one person (required for employees); `null` reads
  /// the whole organization (admins).
  Stream<List<TimeEntry>> watchEntries(
    String orgId, {
    required String? uid,
    required DateTime from,
    DateTime? to,
  });

  /// Monthly summaries. [uid] limits them to one person (required for
  /// employees); [monthKeys] (`YYYY-MM`, sorted) to the months from the first
  /// to the last key; `null` reads all months.
  Stream<List<MonthSummary>> watchSummaries(
    String orgId, {
    required String? uid,
    List<String>? monthKeys,
  });
}
