import '../core/auth/google_tokens.dart';
import '../core/errors.dart';
import '../domain/models.dart';
import '../domain/projects.dart';
import 'repositories/auth_repository.dart';
import 'repositories/org_repository.dart';
import 'repositories/platform_check_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/projects_repository.dart';

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

  @override
  Future<String?> idToken() async => null;
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

class UnconfiguredProfileRepository implements ProfileRepository {
  const UnconfiguredProfileRepository();

  @override
  Stream<UserProfile?> watchProfile(String uid) => Stream.value(null);

  @override
  Future<void> saveName({
    required AuthUser user,
    required String firstName,
    required String lastName,
    required bool exists,
  }) => Future.error(const AppException(AppErrorCode.firebaseNotConfigured));

  @override
  Future<void> setLastOrg({required String uid, required String orgId}) async {}
}

class UnconfiguredOrgRepository implements OrgRepository {
  const UnconfiguredOrgRepository();

  static Future<Never> _fail() =>
      Future.error(const AppException(AppErrorCode.firebaseNotConfigured));

  @override
  Stream<List<Membership>> watchMyMemberships(String uid) => Stream.value([]);

  @override
  Stream<Organization?> watchOrg(String orgId) => Stream.value(null);

  @override
  Stream<List<Membership>> watchMembers(String orgId) => Stream.value([]);

  @override
  Stream<List<Invite>> watchPendingInvites(String orgId) => Stream.value([]);

  @override
  Future<String> createOrganization({
    required String name,
    required String currency,
    required String timezone,
  }) => _fail();

  @override
  Future<String> acceptInvite(String code) => _fail();

  @override
  Future<InviteCode> createInvite({
    required String orgId,
    required String email,
    required OrgRole role,
  }) => _fail();

  @override
  Future<InviteCode> resendInvite({
    required String orgId,
    required String inviteId,
  }) => _fail();

  @override
  Future<void> revokeInvite({
    required String orgId,
    required String inviteId,
  }) => _fail();
}

class UnconfiguredProjectsRepository implements ProjectsRepository {
  const UnconfiguredProjectsRepository();

  static Future<Never> _fail() =>
      Future.error(const AppException(AppErrorCode.firebaseNotConfigured));

  @override
  Stream<List<Project>> watchProjects(String orgId) => Stream.value([]);

  @override
  String newProjectId(String orgId) => 'local';

  @override
  Future<void> saveProject(
    String orgId,
    Project project, {
    required bool isNew,
  }) => _fail();

  @override
  Stream<Map<String, ProjectRate>> watchRates(String orgId, String uid) =>
      Stream.value(const {});

  @override
  Future<void> saveRate(String orgId, String uid, ProjectRate rate) => _fail();
}
