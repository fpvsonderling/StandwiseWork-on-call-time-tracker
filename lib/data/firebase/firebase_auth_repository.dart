import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../core/auth/google_tokens.dart';
import '../../core/errors.dart';
import '../../domain/models.dart';
import '../repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._google);

  final fb.FirebaseAuth _auth;
  final GoogleTokenProvider _google;

  static AuthUser? _map(fb.User? u) => u == null
      ? null
      : AuthUser(
          uid: u.uid,
          email: u.email ?? '',
          emailVerified: u.emailVerified,
          displayName: u.displayName,
          photoUrl: u.photoURL,
        );

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AuthUser> signInWithGoogle({
    required BrowserRedirectMessages messages,
  }) async {
    final tokens = await _google.signIn(messages: messages);
    try {
      final cred = fb.GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      final result = await _auth.signInWithCredential(cred);
      return _map(result.user)!;
    } on fb.FirebaseAuthException catch (e) {
      throw AppException(
        e.code == 'network-request-failed'
            ? AppErrorCode.network
            : AppErrorCode.signInFailed,
        '${e.code}: ${e.message}',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
