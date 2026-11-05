import 'dart:async';

import 'package:standwise/core/auth/google_tokens.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/repositories/auth_repository.dart';
import 'package:standwise/data/repositories/entries_repository.dart';
import 'package:standwise/data/repositories/org_repository.dart';
import 'package:standwise/data/repositories/profile_repository.dart';
import 'package:standwise/data/repositories/projects_repository.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/summaries.dart';
import 'package:standwise/domain/timer.dart';

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

  Membership _copyMember(Membership m, {OrgRole? role, MemberStatus? status}) =>
      Membership(
        orgId: m.orgId,
        uid: m.uid,
        role: role ?? m.role,
        status: status ?? m.status,
        firstName: m.firstName,
        lastName: m.lastName,
        email: m.email,
        joinedAt: m.joinedAt,
      );

  void _replaceMember(
    String orgId,
    String uid,
    Membership Function(Membership) change,
  ) {
    final i = _memberships.indexWhere((m) => m.orgId == orgId && m.uid == uid);
    if (i < 0) throw const AppException(AppErrorCode.memberNotFound);
    _memberships[i] = change(_memberships[i]);
  }

  @override
  Future<void> setMemberRole({
    required String orgId,
    required String uid,
    required OrgRole role,
  }) async {
    calls.add('setMemberRole:$uid:${role.wire}');
    _check();
    _replaceMember(orgId, uid, (m) => _copyMember(m, role: role));
    _changes.add(null);
  }

  @override
  Future<void> setMemberStatus({
    required String orgId,
    required String uid,
    required MemberStatus status,
  }) async {
    calls.add('setMemberStatus:$uid:${status.name}');
    _check();
    _replaceMember(orgId, uid, (m) => _copyMember(m, status: status));
    _changes.add(null);
  }

  @override
  Future<void> removeMember({
    required String orgId,
    required String uid,
  }) async {
    calls.add('removeMember:$uid');
    _check();
    _memberships.removeWhere((m) => m.orgId == orgId && m.uid == uid);
    _changes.add(null);
  }

  @override
  Future<void> transferOwnership({
    required String orgId,
    required String uid,
  }) async {
    calls.add('transferOwnership:$uid');
    _check();
    for (final m in [..._memberships.where((m) => m.orgId == orgId)]) {
      if (m.role == OrgRole.owner) {
        _replaceMember(
          orgId,
          m.uid,
          (x) => _copyMember(x, role: OrgRole.admin),
        );
      }
    }
    _replaceMember(orgId, uid, (m) => _copyMember(m, role: OrgRole.owner));
    _changes.add(null);
  }

  @override
  Future<void> leaveOrganization(String orgId) async {
    calls.add('leaveOrganization:$orgId');
    _check();
    _memberships.removeWhere((m) => m.orgId == orgId && m.uid == 'u1');
    _changes.add(null);
  }

  @override
  Future<void> deleteOrganization({
    required String orgId,
    required String confirmName,
  }) async {
    calls.add('deleteOrganization:$orgId:$confirmName');
    _check();
    if (_orgs[orgId]?.name != confirmName) {
      throw const AppException(AppErrorCode.nameMismatch);
    }
    _orgs.remove(orgId);
    _memberships.removeWhere((m) => m.orgId == orgId);
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    _check();
  }

  @override
  Future<void> updateOrganization({
    required String orgId,
    required String name,
    required OrgSettings settings,
  }) async {
    calls.add('updateOrganization:$orgId:$name:${settings.currency}');
    _check();
    final o = _orgs[orgId];
    if (o != null) {
      _orgs[orgId] = Organization(
        id: o.id,
        name: name,
        status: o.status,
        settings: settings,
      );
    }
    _changes.add(null);
  }

  /// Returned by [watchAuditLog].
  final audit = <AuditEntry>[];

  @override
  Stream<List<AuditEntry>> watchAuditLog(String orgId, {int limit = 100}) =>
      _watch(() => audit.take(limit).toList());
}

/// Emits [read]'s value now and after every [changes] event.
Stream<T> watchValue<T>(T Function() read, Stream<void> changes) async* {
  yield read();
  await for (final _ in changes) {
    yield read();
  }
}

class FakeProjectsRepository implements ProjectsRepository {
  FakeProjectsRepository({
    List<Project>? projects,
    Map<String, ProjectRate>? rates,
  }) : projects = [...?projects],
       rates = {...?rates};

  final List<Project> projects;

  /// The signed-in member's rates.
  final Map<String, ProjectRate> rates;
  final _changes = StreamController<void>.broadcast();
  var _ids = 0;

  @override
  Stream<List<Project>> watchProjects(String orgId) =>
      watchValue(() => [...projects], _changes.stream);

  @override
  String newProjectId(String orgId) => 'p${++_ids}';

  @override
  Future<void> saveProject(
    String orgId,
    Project project, {
    required bool isNew,
  }) async {
    projects
      ..removeWhere((p) => p.id == project.id)
      ..add(project);
    _changes.add(null);
  }

  @override
  Stream<Map<String, ProjectRate>> watchRates(String orgId, String uid) =>
      watchValue(() => {...rates}, _changes.stream);

  @override
  Future<void> saveRate(String orgId, String uid, ProjectRate rate) async {
    rates[rate.projectId] = rate;
    _changes.add(null);
  }
}

class FakeEntriesRepository implements EntriesRepository {
  FakeEntriesRepository({
    List<TimeEntry>? entries,
    this.timer,
    List<MonthSummary>? summaries,
  }) : entries = [...?entries],
       summaries = [...?summaries];

  /// Server-written monthly summaries (the Team view reads these).
  final List<MonthSummary> summaries;

  /// Including soft-deleted ones.
  final List<TimeEntry> entries;
  RunningTimer? timer;
  final _changes = StreamController<void>.broadcast();
  var _ids = 0;

  void _changed() => _changes.add(null);

  /// Replaces the running timer as if another device changed it.
  void setTimer(RunningTimer? t) {
    timer = t;
    _changed();
  }

  void _put(TimeEntry e) {
    entries
      ..removeWhere((x) => x.id == e.id)
      ..add(e);
  }

  @override
  Stream<RunningTimer?> watchTimer(String orgId, String uid) =>
      watchValue(() => timer, _changes.stream);

  @override
  Future<void> startTimer(
    String orgId,
    String uid,
    RunningTimer timer, {
    TimeEntry? stopped,
  }) async {
    if (stopped != null) _put(stopped);
    this.timer = timer;
    _changed();
  }

  @override
  Future<void> updateTimer(String orgId, String uid, RunningTimer timer) async {
    this.timer = timer;
    _changed();
  }

  @override
  Future<void> stopTimer(String orgId, String uid, TimeEntry? entry) async {
    if (entry != null) _put(entry);
    timer = null;
    _changed();
  }

  @override
  String newEntryId(String orgId) => 'e${++_ids}';

  @override
  Future<void> addEntry(String orgId, TimeEntry entry) async {
    _put(entry);
    _changed();
  }

  @override
  Future<void> updateEntry(String orgId, TimeEntry entry) async {
    _put(entry);
    _changed();
  }

  @override
  Future<void> setDeleted(
    String orgId,
    String entryId, {
    required bool deleted,
  }) async {
    final e = entries.firstWhere((x) => x.id == entryId);
    _put(e.copyWith(deleted: deleted));
    _changed();
  }

  @override
  Stream<List<TimeEntry>> watchEntries(
    String orgId, {
    required String? uid,
    required DateTime from,
    DateTime? to,
  }) => watchValue(
    () =>
        entries
            .where(
              (e) =>
                  !e.deleted &&
                  (uid == null || e.uid == uid) &&
                  !e.start.isBefore(from) &&
                  (to == null || e.start.isBefore(to)),
            )
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start)),
    _changes.stream,
  );

  @override
  Stream<List<MonthSummary>> watchSummaries(
    String orgId, {
    required String? uid,
    List<String>? monthKeys,
  }) => watchValue(
    () => summaries
        .where(
          (m) =>
              (uid == null || m.uid == uid) &&
              (monthKeys == null || monthKeys.contains(m.monthKey)),
        )
        .toList(),
    _changes.stream,
  );
}
