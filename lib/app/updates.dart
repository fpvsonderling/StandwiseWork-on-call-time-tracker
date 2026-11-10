import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/update_check.dart';
import 'brand.dart';

/// Checks the Releases page for a newer version (D-047).
final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(repo: Brand.repoSlug),
);

/// A newer release for this platform, checked once per app start. Only
/// Android and Windows: iPhone, iPad and Mac update through TestFlight or
/// the App Store.
final availableUpdateProvider = FutureProvider<AvailableUpdate?>((ref) async {
  if (kIsWeb) return null;
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.android => UpdatePlatform.android,
    TargetPlatform.windows => UpdatePlatform.windows,
    _ => null,
  };
  if (platform == null) return null;
  try {
    final info = await PackageInfo.fromPlatform();
    return await ref
        .read(updateCheckerProvider)
        .check(currentVersion: info.version, platform: platform);
  } catch (_) {
    return null;
  }
});

/// "Later" hides the banner until the next start.
final updateDismissedProvider = NotifierProvider<UpdateDismissed, bool>(
  UpdateDismissed.new,
);

class UpdateDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}
