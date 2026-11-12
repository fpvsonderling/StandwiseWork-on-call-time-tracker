/// Core domain models shared by features and repositories. Pure Dart: no
/// Flutter or Firebase imports.
library;

import 'durations.dart';
import 'money.dart';
import 'person_name.dart';

enum EntryType {
  work('work'),
  standby('standby');

  const EntryType(this.wire);

  /// Value stored in Firestore.
  final String wire;

  static EntryType fromWire(String v) =>
      values.firstWhere((t) => t.wire == v, orElse: () => EntryType.work);
}

enum OrgRole {
  owner('owner'),
  admin('admin'),
  employee('employee');

  const OrgRole(this.wire);
  final String wire;

  bool get isAdminOrOwner => this == owner || this == admin;

  static OrgRole fromWire(String v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => OrgRole.employee);
}

/// A signed-in user as seen by the app (from Firebase Auth).
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;
  final String? photoUrl;
}

/// A tracked time entry (spec §6 `orgs/{orgId}/entries/{entryId}`).
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.uid,
    required this.type,
    required this.rateMinor,
    required this.start,
    required this.end,
    this.projectId,
    this.description = '',
    this.deleted = false,
    this.edit,
  });

  final String id;
  final String uid;
  final String? projectId;
  final EntryType type;
  final int rateMinor;
  final DateTime start;
  final DateTime end;
  final String description;
  final bool deleted;

  /// Set when an admin last changed someone else's entry (D-051).
  final EntryEdit? edit;

  int get durationMin => durationMinutes(start, end);

  int get amountMinor =>
      amountForDuration(rateMinor: rateMinor, durationMin: durationMin);

  /// [clearProject] sets [projectId] to `null` ("No project").
  TimeEntry copyWith({
    String? projectId,
    bool clearProject = false,
    EntryType? type,
    int? rateMinor,
    DateTime? start,
    DateTime? end,
    String? description,
    bool? deleted,
  }) => TimeEntry(
    id: id,
    uid: uid,
    projectId: clearProject ? null : projectId ?? this.projectId,
    type: type ?? this.type,
    rateMinor: rateMinor ?? this.rateMinor,
    start: start ?? this.start,
    end: end ?? this.end,
    description: description ?? this.description,
    deleted: deleted ?? this.deleted,
    edit: edit,
  );
}

/// Who changed an entry on its owner's behalf, when, and why (D-051).
class EntryEdit {
  const EntryEdit({
    required this.byUid,
    required this.byName,
    this.at,
    this.comment = '',
  });

  final String byUid;
  final String byName;

  /// Server time; `null` until the write has synced.
  final DateTime? at;
  final String comment;
}

/// The signed-in user's profile (spec §6 `users/{uid}`).
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.photoUrl,
    this.lastOrgId,
  });

  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String? photoUrl;
  final String? lastOrgId;

  /// Both names are present and valid; otherwise the "Your name" screen is
  /// shown before anything else (spec §4.2).
  bool get isComplete =>
      validateName(firstName) == null && validateName(lastName) == null;

  /// "First Last", as shown in reports, CSV and Team.
  String get displayName => fullName(firstName, lastName);
}

enum MemberStatus {
  active('active'),
  disabled('disabled');

  const MemberStatus(this.wire);
  final String wire;

  static MemberStatus fromWire(String? v) =>
      v == disabled.wire ? disabled : active;
}

enum OrgStatus {
  trial('trial'),
  active('active'),
  suspended('suspended');

  const OrgStatus(this.wire);
  final String wire;

  /// Suspended organizations are read-only (spec §3.2, §9).
  bool get writable => this != suspended;

  static OrgStatus fromWire(String? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => OrgStatus.suspended);
}

/// Per-organization regional settings (spec §1, §6 `orgs.settings`).
class OrgSettings {
  const OrgSettings({
    this.currency = 'EUR',
    this.timezone = 'Europe/Warsaw',
    this.weekStart = DateTime.monday,
    this.use24h = true,
    this.csvSeparator = ',',
    this.csvDecimal = '.',
  });

  final String currency;
  final String timezone;
  final int weekStart;
  final bool use24h;
  final String csvSeparator;
  final String csvDecimal;
}

/// `orgs/{orgId}`.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.status,
    this.settings = const OrgSettings(),
  });

  final String id;
  final String name;
  final OrgStatus status;
  final OrgSettings settings;
}

/// `orgs/{orgId}/members/{uid}`: one person's role in one organization.
class Membership {
  const Membership({
    required this.orgId,
    required this.uid,
    required this.role,
    required this.status,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.joinedAt,
  });

  final String orgId;
  final String uid;
  final OrgRole role;
  final MemberStatus status;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime? joinedAt;

  bool get isActive => status == MemberStatus.active;
  bool get isAdmin => isActive && role.isAdminOrOwner;
  String get displayName => fullName(firstName, lastName);
}

/// A pending invite as admins see it (the code itself is never stored).
class Invite {
  const Invite({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
  });

  final String id;
  final String email;
  final OrgRole role;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

/// A freshly created or resent invite code, shown once to the admin.
/// An invitation for the signed-in user's email (from `listMyInvites`), so
/// they can join without typing the code.
class MyInvite {
  const MyInvite({
    required this.orgId,
    required this.inviteId,
    required this.orgName,
    required this.inviterName,
    required this.role,
  });

  final String orgId;
  final String inviteId;
  final String orgName;
  final String inviterName;
  final OrgRole role;
}

class InviteCode {
  const InviteCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// `orgs/{orgId}/auditLog/{id}`, written only by functions (spec §6).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actorUid,
    required this.action,
    required this.entity,
    required this.entityId,
    this.details = const {},
  });

  final String id;
  final DateTime at;
  final String actorUid;

  /// e.g. `member.role`, `invite.create`, `org.create`.
  final String action;
  final String entity;
  final String entityId;
  final Map<String, Object?> details;
}
