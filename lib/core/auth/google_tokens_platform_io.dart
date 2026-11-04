import 'dart:io' show Platform;

import '../../app/flavor.dart';
import 'desktop_google_oauth.dart';
import 'google_tokens.dart';

/// On Windows (and Linux, unsupported but harmless) use the desktop OAuth
/// loopback flow; everywhere else fall back to `google_sign_in`.
GoogleTokenProvider? platformGoogleTokenProvider(AppConfig config) {
  if (Platform.isWindows || Platform.isLinux) {
    return DesktopGoogleOAuth(
      clientId: config.googleDesktopClientId,
      clientSecret: config.googleDesktopClientSecret,
    );
  }
  return null;
}
