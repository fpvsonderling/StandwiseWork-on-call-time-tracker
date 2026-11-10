import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A newer release than the running app (D-047).
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.url});

  /// e.g. `0.1.1`.
  final String version;

  /// The platform's download (APK, Windows zip) or the release page.
  final Uri url;
}

/// Which download to offer from a release.
enum UpdatePlatform {
  android('-android.apk'),
  windows('-windows.zip');

  const UpdatePlatform(this.assetSuffix);
  final String assetSuffix;
}

/// `1.2.3` (an optional `v`, any `+build` or `-suffix` ignored) as numbers,
/// or `null` when it isn't a version.
List<int>? parseVersion(String s) {
  final core = s.trim().replaceFirst(RegExp('^v'), '').split(RegExp('[+-]'))[0];
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  return nums.cast<int>();
}

/// Whether [candidate] is a higher version than [current].
bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Asks GitHub for the latest published release (the Releases page,
/// D-046). Any failure (offline, rate limit, odd data) means "no update".
class UpdateChecker {
  UpdateChecker({required this.repo, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// `owner/name`.
  final String repo;
  final http.Client _http;

  Future<AvailableUpdate?> check({
    required String currentVersion,
    required UpdatePlatform platform,
  }) async {
    try {
      final res = await _http
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final tag = body['tag_name'];
      final page = body['html_url'];
      if (tag is! String || page is! String) return null;
      if (body['draft'] == true || body['prerelease'] == true) return null;
      if (!isNewerVersion(tag, currentVersion)) return null;
      var url = Uri.parse(page);
      final assets = body['assets'];
      if (assets is List) {
        for (final a in assets) {
          if (a is Map &&
              a['name'] is String &&
              (a['name'] as String).endsWith(platform.assetSuffix) &&
              a['browser_download_url'] is String) {
            url = Uri.parse(a['browser_download_url'] as String);
            break;
          }
        }
      }
      return AvailableUpdate(version: parseVersion(tag)!.join('.'), url: url);
    } catch (_) {
      return null;
    }
  }
}
