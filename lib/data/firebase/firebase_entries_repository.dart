import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/date_ranges.dart';
import '../../domain/models.dart';
import '../../domain/summaries.dart';
import '../../domain/timer.dart';
import '../repositories/entries_repository.dart';
import '../sync.dart';
import 'firestore_errors.dart';

class FirebaseEntriesRepository implements EntriesRepository {
  FirebaseEntriesRepository(this._db, this._sync);

  final FirebaseFirestore _db;
  final SyncTracker _sync;

  DocumentReference<Map<String, dynamic>> _org(String orgId) =>
      _db.collection('orgs').doc(orgId);

  CollectionReference<Map<String, dynamic>> _entries(String orgId) =>
      _org(orgId).collection('entries');

  DocumentReference<Map<String, dynamic>> _timer(String orgId, String uid) =>
      _org(orgId).collection('timers').doc(uid);

  void _track(Future<void> write) => _sync.track(write, mapError: appErrorFrom);

  static Map<String, Object?> _timerData(RunningTimer t) => {
    'projectId': t.projectId,
    'type': t.type.wire,
    'description': t.description,
    'start': Timestamp.fromDate(t.start),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Every field rules check, without `createdAt` (set only on create).
  static Map<String, Object?> _entryData(TimeEntry e) => {
    'uid': e.uid,
    'projectId': e.projectId,
    'type': e.type.wire,
    'rateMinor': e.rateMinor,
    'start': Timestamp.fromDate(e.start),
    'end': Timestamp.fromDate(e.end),
    'durationMin': e.durationMin,
    'description': e.description,
    'monthKey': monthKey(e.start),
    'deleted': e.deleted,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static TimeEntry _entry(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return TimeEntry(
      id: d.id,
      uid: m['uid'] as String? ?? '',
      projectId: m['projectId'] as String?,
      type: EntryType.fromWire(m['type'] as String? ?? ''),
      rateMinor: m['rateMinor'] as int? ?? 0,
      start: (m['start'] as Timestamp?)?.toDate() ?? DateTime(0),
      end: (m['end'] as Timestamp?)?.toDate() ?? DateTime(0),
      description: m['description'] as String? ?? '',
      deleted: m['deleted'] as bool? ?? false,
    );
  }

  @override
  Stream<RunningTimer?> watchTimer(String orgId, String uid) =>
      _timer(orgId, uid)
          .snapshots(includeMetadataChanges: true)
          .map((s) {
            // The timer listener is always on while the app is open, so it
            // tells the header whether we are offline.
            _sync.reportFromCache(s.metadata.isFromCache);
            final m = s.data();
            if (m == null) return null;
            return RunningTimer(
              start: (m['start'] as Timestamp?)?.toDate() ?? DateTime.now(),
              projectId: m['projectId'] as String?,
              type: EntryType.fromWire(m['type'] as String? ?? ''),
              description: m['description'] as String? ?? '',
            );
          })
          .distinct(_sameTimer);

  static bool _sameTimer(RunningTimer? a, RunningTimer? b) =>
      a?.start == b?.start &&
      a?.projectId == b?.projectId &&
      a?.type == b?.type &&
      a?.description == b?.description;

  @override
  Future<void> startTimer(
    String orgId,
    String uid,
    RunningTimer timer, {
    TimeEntry? stopped,
  }) async {
    final batch = _db.batch()..set(_timer(orgId, uid), _timerData(timer));
    if (stopped != null) {
      batch.set(_entries(orgId).doc(stopped.id), {
        ..._entryData(stopped),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    _track(batch.commit());
  }

  @override
  Future<void> updateTimer(
    String orgId,
    String uid,
    RunningTimer timer,
  ) async => _track(_timer(orgId, uid).set(_timerData(timer)));

  @override
  Future<void> stopTimer(String orgId, String uid, TimeEntry? entry) async {
    final batch = _db.batch()..delete(_timer(orgId, uid));
    if (entry != null) {
      batch.set(_entries(orgId).doc(entry.id), {
        ..._entryData(entry),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    _track(batch.commit());
  }

  @override
  String newEntryId(String orgId) => _entries(orgId).doc().id;

  @override
  Future<void> addEntry(String orgId, TimeEntry entry) async => _track(
    _entries(orgId)
        .doc(entry.id)
        .set({..._entryData(entry), 'createdAt': FieldValue.serverTimestamp()}),
  );

  @override
  Future<void> updateEntry(String orgId, TimeEntry entry) async =>
      _track(_entries(orgId).doc(entry.id).update(_entryData(entry)));

  @override
  Future<void> setDeleted(
    String orgId,
    String entryId, {
    required bool deleted,
  }) async => _track(
    _entries(orgId).doc(entryId).update({
      'deleted': deleted,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Stream<List<TimeEntry>> watchEntries(
    String orgId, {
    required String? uid,
    required DateTime from,
    DateTime? to,
  }) {
    Query<Map<String, dynamic>> q = _entries(orgId);
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    q = q.where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    if (to != null) q = q.where('start', isLessThan: Timestamp.fromDate(to));
    return q
        .orderBy('start', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_entry).where((e) => !e.deleted).toList());
  }

  @override
  Stream<List<MonthSummary>> watchSummaries(
    String orgId, {
    required String? uid,
    List<String>? monthKeys,
  }) {
    Query<Map<String, dynamic>> q = _org(orgId).collection('summaries');
    if (uid != null) q = q.where('uid', isEqualTo: uid);
    if (monthKeys != null && monthKeys.isNotEmpty) {
      q = q
          .where('monthKey', isGreaterThanOrEqualTo: monthKeys.first)
          .where('monthKey', isLessThanOrEqualTo: monthKeys.last);
    }
    return q.snapshots().map((s) => s.docs.map(_summary).toList());
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static SummaryBucket _bucket(Object? raw) {
    final m = raw is Map ? raw : const {};
    return SummaryBucket(
      workMin: _int(m['workMin']),
      standbyMin: _int(m['standbyMin']),
      amountMinor: _int(m['amountMinor']),
      count: _int(m['count']),
    );
  }

  static MonthSummary _summary(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final days = <int, Map<String, SummaryBucket>>{};
    final rawDays = m['days'];
    if (rawDays is Map) {
      for (final MapEntry(:key, :value) in rawDays.entries) {
        final day = int.tryParse('$key');
        final byProject = value is Map ? value['byProject'] : null;
        if (day == null || byProject is! Map) continue;
        days[day] = {
          for (final MapEntry(key: p, value: b) in byProject.entries)
            '$p': _bucket(b),
        };
      }
    }
    return MonthSummary(
      uid: m['uid'] as String? ?? '',
      monthKey: m['monthKey'] as String? ?? '',
      days: days,
    );
  }
}
