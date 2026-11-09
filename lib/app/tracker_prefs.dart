import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-device memory for the tracker bar: the last entry mode and the
/// last project per organization. Failures (no plugin, private mode) just
/// mean no memory.
abstract interface class TrackerPrefs {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final trackerPrefsProvider = Provider<TrackerPrefs>(
  (ref) => SharedTrackerPrefs(),
);

class SharedTrackerPrefs implements TrackerPrefs {
  // Created on first use so a missing plugin only means no memory.
  late final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) async {
    try {
      return await _prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } catch (_) {
      // Remembering is a convenience; ignore.
    }
  }
}

/// In-memory [TrackerPrefs] for tests.
class MemoryTrackerPrefs implements TrackerPrefs {
  MemoryTrackerPrefs([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

abstract final class TrackerPrefKeys {
  static const mode = 'tracker.mode';
  static String project(String orgId) => 'tracker.project.$orgId';
}
