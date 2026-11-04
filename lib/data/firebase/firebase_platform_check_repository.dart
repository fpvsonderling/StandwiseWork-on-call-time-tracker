import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors.dart';
import '../repositories/platform_check_repository.dart';

/// Writes to `_platformChecks/{uid}` (own document only; see firestore.rules).
class FirebasePlatformCheckRepository implements PlatformCheckRepository {
  FirebasePlatformCheckRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('_platformChecks').doc(uid);

  static ProbeSnapshot? _map(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data();
    if (d == null) return null;
    return ProbeSnapshot(
      counter: (d['counter'] as num?)?.toInt() ?? 0,
      platform: d['platform'] as String?,
      fromCache: s.metadata.isFromCache,
      hasPendingWrites: s.metadata.hasPendingWrites,
    );
  }

  @override
  Future<void> writeProbe({
    required String uid,
    required int counter,
    required String platform,
  }) {
    // Not awaited for server ack when offline: Firestore resolves the future
    // only once the server confirms, so callers decide whether to await.
    return _guard(
      () => _doc(uid).set({
        'counter': counter,
        'platform': platform,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<ProbeSnapshot?> readProbe({
    required String uid,
    bool cacheOnly = false,
  }) => _guard(
    () async => _map(
      await _doc(uid)
          .get(GetOptions(source: cacheOnly ? Source.cache : Source.server)),
    ),
  );

  @override
  Stream<ProbeSnapshot?> watchProbe({required String uid}) =>
      _doc(uid).snapshots(includeMetadataChanges: true).map(_map);

  @override
  Future<void> setNetworkEnabled(bool enabled) =>
      enabled ? _db.enableNetwork() : _db.disableNetwork();

  @override
  bool get persistenceEnabled => _db.settings.persistenceEnabled ?? true;

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      throw AppException(switch (e.code) {
        'permission-denied' => AppErrorCode.permissionDenied,
        'unavailable' => AppErrorCode.network,
        _ => AppErrorCode.unknown,
      }, '${e.code}: ${e.message}');
    }
  }
}
