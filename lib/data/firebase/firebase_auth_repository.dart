import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

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
      throw _mapError(e);
    }
  }

  @override
  bool get hasBrowserSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<AuthUser> signInWithGoogleInBrowser() async {
    final provider = fb.GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      final result = await _auth.signInWithProvider(provider);
      return _map(result.user)!;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapError(e);
    }
  }

  static AppException _mapError(fb.FirebaseAuthException e) {
    final code = switch (e.code) {
      'network-request-failed' => AppErrorCode.network,
      'web-context-canceled' ||
      'web-context-cancelled' ||
      'canceled' => AppErrorCode.signInCancelled,
      _ => AppErrorCode.signInFailed,
    };
    return AppException(code, '${e.code}: ${e.message}');
  }

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
