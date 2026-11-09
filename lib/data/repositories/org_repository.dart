import '../../domain/models.dart';

/// Organizations, memberships and invites (spec §4.3, §5.6). Reads are
/// Firestore listeners; changes go through Cloud Functions and need a
/// connection.
abstract interface class OrgRepository {
  /// All organizations the user belongs to (any status).
  Stream<List<Membership>> watchMyMemberships(String uid);

  Stream<Organization?> watchOrg(String orgId);

  /// Admins only.
  Stream<List<Membership>> watchMembers(String orgId);

  /// Admins only. Pending invites, including expired ones.
  Stream<List<Invite>> watchPendingInvites(String orgId);

  /// Returns the new organization's ID; the caller becomes its owner.
  Future<String> createOrganization({
    required String name,
    required String currency,
    required String timezone,
  });

  /// Returns the joined organization's ID.
  Future<String> acceptInvite(String code);

  /// Pending invitations for the signed-in user's email.
  Future<List<MyInvite>> myInvites();

  /// Joins from [myInvites] without the code; returns the organization ID.
  Future<String> acceptInviteById({
    required String orgId,
    required String inviteId,
  });

  Future<InviteCode> createInvite({
    required String orgId,
    required String email,
    required OrgRole role,
  });

  Future<InviteCode> resendInvite({
    required String orgId,
    required String inviteId,
  });

  Future<void> revokeInvite({required String orgId, required String inviteId});

  // ----- Stage 7: members, organization, account -----

  /// Admins: change another member's role (not the owner's).
  Future<void> setMemberRole({
    required String orgId,
    required String uid,
    required OrgRole role,
  });

  /// Admins: disable or re-enable another member.
  Future<void> setMemberStatus({
    required String orgId,
    required String uid,
    required MemberStatus status,
  });

  /// Admins: remove another member (their hours stay).
  Future<void> removeMember({required String orgId, required String uid});

  /// Owner: make [uid] the owner; the caller becomes admin.
  Future<void> transferOwnership({required String orgId, required String uid});

  /// Members other than the owner.
  Future<void> leaveOrganization(String orgId);

  /// Owner, with the organization's name typed again.
  Future<void> deleteOrganization({
    required String orgId,
    required String confirmName,
  });

  /// Deletes the signed-in user's account (spec §4.5).
  Future<void> deleteAccount();

  /// Admins: name and settings (a plain Firestore write, rules-checked).
  Future<void> updateOrganization({
    required String orgId,
    required String name,
    required OrgSettings settings,
  });

  /// Admins: latest activity first.
  Stream<List<AuditEntry>> watchAuditLog(String orgId, {int limit = 100});
}
