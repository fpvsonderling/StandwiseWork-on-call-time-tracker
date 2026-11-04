import 'dart:async';

import 'package:standwise/core/auth/google_tokens.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/repositories/auth_repository.dart';
import 'package:standwise/data/repositories/org_repository.dart';
import 'package:standwise/data/repositories/profile_repository.dart';
import 'package:standwise/domain/models.dart';

const testUser = AuthUser(
  uid: 'u1',
  email: 'anna@example.com',
  emailVerified: true,
  displayName: 'Anna Maria Kowalska',
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? signedIn, this.signInResult = testUser})
    : _user = signedIn;

  AuthUser? _user;
  final AuthUser signInResult;
  final _changes = StreamController<AuthUser?>.broadcast();
  AppException? nextSignInError;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithGoogle({
    required BrowserRedirectMessages messages,
  }) async {
    final error = nextSignInError;
    if (error != null) {
      nextSignInError = null;
      throw error;
    }
    _user = signInResult;
    _changes.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }

  @override
  Future<String?> idToken() async => _user == null ? null : 'token';
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([Map<String, UserProfile>? profiles])
    : _profiles = {...?profiles};

  final Map<String, UserProfile> _profiles;
  final _changes = StreamController<void>.broadcast();
  final saved = <({String first, String last, bool exists})>[];

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield _profiles[uid];
    await for (final _ in _changes.stream) {
      yield _profiles[uid];
    }
  }

  @override
  Future<void> saveName({
    required AuthUser user,
    required String firstName,
    required String lastName,
    required bool exists,
  }) async {
    saved.add((first: firstName, last: lastName, exists: exists));
    _profiles[user.uid] = UserProfile(
      uid: user.uid,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: user.email,
      lastOrgId: _profiles[user.uid]?.lastOrgId,
    );
    _changes.add(null);
  }

  @override
  Future<void> setLastOrg({required String uid, required String orgId}) async {
    final p = _profiles[uid];
    if (p == null) return;
    _profiles[uid] = UserProfile(
      uid: p.uid,
      firstName: p.firstName,
      lastName: p.lastName,
      email: p.email,
      lastOrgId: orgId,
    );
    _changes.add(null);
  }
}

Membership membershipOf(
  String orgId, {
  String uid = 'u1',
  OrgRole role = OrgRole.owner,
  MemberStatus status = MemberStatus.active,
  String firstName = 'Anna',
  String lastName = 'Kowalska',
  String email = 'anna@example.com',
}) => Membership(
  orgId: orgId,
  uid: uid,
  role: role,
  status: status,
  firstName: firstName,
  lastName: lastName,
  email: email,
);

/// In-memory organizations; "functions" act immediately, like the server.
class FakeOrgRepository implements OrgRepository {
  FakeOrgRepository({
    List<Membership>? memberships,
    Map<String, Organization>? orgs,
    this.profiles,
  }) : _memberships = [...?memberships],
       _orgs = {...?orgs};

  final List<Membership> _memberships;
  final Map<String, Organization> _orgs;
  final _invites = <String, List<Invite>>{};
  final FakeProfileRepository? profiles;
  final _changes = StreamController<void>.broadcast();
  final calls = <String>[];
  AppException? nextError;

  /// Code -> orgId accepted by [acceptInvite].
  final validCodes = <String, String>{};

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  void _check() {
    final e = nextError;
    if (e != null) {
      nextError = null;
      throw e;
    }
  }

  @override
  Stream<List<Membership>> watchMyMemberships(String uid) =>
      _watch(() => _memberships.where((m) => m.uid == uid).toList());

  @override
  Stream<Organization?> watchOrg(String orgId) => _watch(() => _orgs[orgId]);

  @override
  Stream<List<Membership>> watchMembers(String orgId) =>
      _watch(() => _memberships.where((m) => m.orgId == orgId).toList());

  @override
  Stream<List<Invite>> watchPendingInvites(String orgId) =>
      _watch(() => [...?_invites[orgId]]);

  @override
  Future<String> createOrganization({
    required String name,
    required String currency,
    required String timezone,
  }) async {
    calls.add('createOrganization:$name:$currency:$timezone');
    _check();
    final id = 'org${_orgs.length + 1}';
    _orgs[id] = Organization(id: id, name: name, status: OrgStatus.trial);
    _memberships.add(membershipOf(id));
    await profiles?.setLastOrg(uid: 'u1', orgId: id);
    _changes.add(null);
    return id;
  }

  @override
  Future<String> acceptInvite(String code) async {
    calls.add('acceptInvite:$code');
    _check();
    final orgId = validCodes[code];
    if (orgId == null) {
      throw const AppException(AppErrorCode.inviteNotFound);
    }
    _memberships.add(membershipOf(orgId, role: OrgRole.employee));
    await profiles?.setLastOrg(uid: 'u1', orgId: orgId);
    _changes.add(null);
    return orgId;
  }

  @override
  Future<InviteCode> createInvite({
    required String orgId,
    required String email,
    required OrgRole role,
  }) async {
    calls.add('createInvite:$email:${role.wire}');
    _check();
    final expires = DateTime.utc(2030, 1, 8);
    (_invites[orgId] ??= []).add(
      Invite(
        id: 'i${calls.length}',
        email: email,
        role: role,
        expiresAt: expires,
      ),
    );
    _changes.add(null);
    return InviteCode(code: 'K7M2-9QXP', expiresAt: expires);
  }

  @override
  Future<InviteCode> resendInvite({
    required String orgId,
    required String inviteId,
  }) async {
    calls.add('resendInvite:$inviteId');
    _check();
    return InviteCode(code: 'ABCD-EFGH', expiresAt: DateTime.utc(2030, 1, 9));
  }

  @override
  Future<void> revokeInvite({
    required String orgId,
    required String inviteId,
  }) async {
    calls.add('revokeInvite:$inviteId');
    _check();
    _invites[orgId]?.removeWhere((i) => i.id == inviteId);
    _changes.add(null);
  }
}
