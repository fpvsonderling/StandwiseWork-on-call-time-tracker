/// Low-level Firestore probe used by the dev-only platform check (stage 1
/// Windows/macOS spike, spec §2.1). Not used by product features.
class ProbeSnapshot {
  const ProbeSnapshot({
    required this.counter,
    required this.fromCache,
    required this.hasPendingWrites,
    this.platform,
  });

  final int counter;
  final bool fromCache;
  final bool hasPendingWrites;

  /// Platform that last wrote the probe (shows cross-device sync).
  final String? platform;
}

abstract interface class PlatformCheckRepository {
  /// Full-document `set` of the caller's own probe document.
  Future<void> writeProbe({
    required String uid,
    required int counter,
    required String platform,
  });

  /// One-off read. With [cacheOnly] the read must be served from the offline cache.
  Future<ProbeSnapshot?> readProbe({
    required String uid,
    bool cacheOnly = false,
  });

  /// Real-time listener including metadata changes.
  Stream<ProbeSnapshot?> watchProbe({required String uid});

  /// Simulates going offline / online.
  Future<void> setNetworkEnabled(bool enabled);

  /// Whether offline persistence is enabled in the current settings.
  bool get persistenceEnabled;
}
