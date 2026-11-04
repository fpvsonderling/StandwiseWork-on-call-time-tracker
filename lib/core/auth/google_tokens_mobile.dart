import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/flavor.dart';
import '../errors.dart';
import 'google_tokens.dart';

/// Android, iOS and macOS: the `google_sign_in` plugin.
class MobileGoogleTokenProvider implements GoogleTokenProvider {
  MobileGoogleTokenProvider(this._config);

  final AppConfig _config;
  Future<void>? _init;

  GoogleSignIn get _gsi => GoogleSignIn.instance;

  Future<void> _ensureInitialized() {
    return _init ??= () {
      final isApple =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      final clientId = isApple && _config.googleAppleClientId.isNotEmpty
          ? _config.googleAppleClientId
          : null;
      // Android needs the Firebase Web client ID as serverClientId so the
      // returned ID token is accepted by Firebase Auth.
      final serverClientId = _config.googleServerClientId.isEmpty
          ? null
          : _config.googleServerClientId;
      return _gsi.initialize(
        clientId: clientId,
        serverClientId: serverClientId,
      );
    }();
  }

  @override
  Future<GoogleTokens> signIn({
    required BrowserRedirectMessages messages,
  }) async {
    await _ensureInitialized();
    if (!_gsi.supportsAuthenticate()) {
      throw const AppException(
        AppErrorCode.signInFailed,
        'google_sign_in.authenticate is not supported on this platform',
      );
    }
    try {
      final account = await _gsi.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppException(
          AppErrorCode.signInFailed,
          'No ID token returned',
        );
      }
      return GoogleTokens(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AppException(AppErrorCode.signInCancelled, e.description);
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw AppException(
          AppErrorCode.googleClientNotConfigured,
          e.description,
        );
      }
      throw AppException(
        AppErrorCode.signInFailed,
        '${e.code.name}: ${e.description}',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await _gsi.signOut();
  }
}
