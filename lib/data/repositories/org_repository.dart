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
}
