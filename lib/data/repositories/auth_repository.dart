import '../../core/auth/google_tokens.dart';
import '../../domain/models.dart';

/// Authentication. Google is the only provider (spec §4.1).
abstract interface class AuthRepository {
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  /// Signs in with Google and returns the Firebase user.
  /// Throws `AppException` on cancel or failure.
  Future<AuthUser> signInWithGoogle({
    required BrowserRedirectMessages messages,
  });

  /// Whether [signInWithGoogleInBrowser] can be offered. True on Android,
  /// where the account picker (Credential Manager) fails silently on some
  /// phones, e.g. Xiaomi (docs/DECISIONS.md D-050).
  bool get hasBrowserSignIn;

  /// Signs in with Google through a browser tab instead of the system account
  /// picker. Throws `AppException` on cancel or failure.
  Future<AuthUser> signInWithGoogleInBrowser();

  Future<void> signOut();

  /// A fresh Firebase ID token for calling Cloud Functions, or `null` when
  /// signed out.
  Future<String?> idToken();
}
