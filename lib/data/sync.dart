import 'dart:async';

/// What the header shows (spec §5: Saved / Saving… / Offline).
enum SyncState { saved, saving, offline }

/// Tracks everyday Firestore writes without waiting for the server.
///
/// Writes return as soon as the local cache has them, so the app works the
/// same offline (spec §8). The tracker counts writes the server hasn't
/// confirmed yet, remembers whether listeners are served from the cache
/// (offline), and passes rejected writes to the UI.
class SyncTracker {
  int _pending = 0;
  bool _fromCache = false;
  final _states = StreamController<SyncState>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  SyncState get state => _fromCache
      ? SyncState.offline
      : _pending > 0
      ? SyncState.saving
      : SyncState.saved;

  Stream<SyncState> get states async* {
    yield state;
    yield* _states.stream;
  }

  /// Writes the server rejected (e.g. a rule failed after reconnecting).
  Stream<Object> get errors => _errors.stream;

  void _emit() => _states.add(state);

  /// Registers [write] (already applied locally) and returns at once.
  void track(Future<void> write, {Object Function(Object)? mapError}) {
    _pending++;
    _emit();
    unawaited(
      write
          .then<void>(
            (_) {},
            onError: (Object e) => _errors.add(mapError?.call(e) ?? e),
          )
          .whenComplete(() {
            _pending--;
            _emit();
          }),
    );
  }

  /// Called by listeners with their snapshot metadata.
  void reportFromCache(bool fromCache) {
    if (fromCache == _fromCache) return;
    _fromCache = fromCache;
    _emit();
  }
}
