/// Core domain models shared by features and repositories. Pure Dart: no
/// Flutter or Firebase imports.
library;

import 'durations.dart';
import 'money.dart';

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

  int get durationMin => durationMinutes(start, end);

  int get amountMinor =>
      amountForDuration(rateMinor: rateMinor, durationMin: durationMin);
}
