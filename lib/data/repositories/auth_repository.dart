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

  Future<void> signOut();
}
