import '../../app/flavor.dart';
import 'google_tokens_mobile.dart';
import 'google_tokens_platform.dart'
    if (dart.library.io) 'google_tokens_platform_io.dart';

/// Tokens returned by a Google sign-in, ready for
/// `GoogleAuthProvider.credential(idToken:, accessToken:)`.
class GoogleTokens {
  const GoogleTokens({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;
}

/// Text shown in the browser tab after the Windows desktop OAuth redirect.
/// Passed in from the UI so it comes from the ARB files.
class BrowserRedirectMessages {
  const BrowserRedirectMessages({required this.success, required this.failure});

  final String success;
  final String failure;
}

/// Obtains Google tokens on the current platform.
abstract interface class GoogleTokenProvider {
  Future<GoogleTokens> signIn({required BrowserRedirectMessages messages});

  Future<void> signOut();

  /// Picks the implementation for the running platform:
  /// `google_sign_in` on Android/iOS/macOS, loopback + PKCE on Windows.
  factory GoogleTokenProvider.forPlatform(AppConfig config) =>
      platformGoogleTokenProvider(config) ?? MobileGoogleTokenProvider(config);
}
