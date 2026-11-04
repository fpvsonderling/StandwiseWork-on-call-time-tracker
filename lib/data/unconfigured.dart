import '../core/auth/google_tokens.dart';
import '../core/errors.dart';
import '../domain/models.dart';
import 'repositories/auth_repository.dart';
import 'repositories/platform_check_repository.dart';

/// Used when Firebase has not been configured yet, so the app still starts
/// (and CI can build it) before `flutterfire configure` has run.
class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(null);

  @override
  AuthUser? get currentUser => null;

  @override
  Future<AuthUser> signInWithGoogle({
    required BrowserRedirectMessages messages,
  }) => Future.error(const AppException(AppErrorCode.firebaseNotConfigured));

  @override
  Future<void> signOut() async {}
}

class UnconfiguredPlatformCheckRepository implements PlatformCheckRepository {
  const UnconfiguredPlatformCheckRepository();

  static Never _fail() =>
      throw const AppException(AppErrorCode.firebaseNotConfigured);

  @override
  Future<void> writeProbe({
    required String uid,
    required int counter,
    required String platform,
  }) async => _fail();

  @override
  Future<ProbeSnapshot?> readProbe({
    required String uid,
    bool cacheOnly = false,
  }) async => _fail();

  @override
  Stream<ProbeSnapshot?> watchProbe({required String uid}) =>
      Stream.error(const AppException(AppErrorCode.firebaseNotConfigured));

  @override
  Future<void> setNetworkEnabled(bool enabled) async => _fail();

  @override
  bool get persistenceEnabled => false;
}
