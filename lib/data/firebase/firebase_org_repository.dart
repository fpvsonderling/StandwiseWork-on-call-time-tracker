import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors.dart';

import '../../domain/models.dart';
import '../repositories/org_repository.dart';
import 'callable_client.dart';
import 'firestore_errors.dart';

class FirebaseOrgRepository implements OrgRepository {
  FirebaseOrgRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final CallableClient _functions;

  static Membership _membership(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Membership(
      orgId: d.reference.parent.parent!.id,
      uid: m['uid'] as String? ?? d.id,
      role: OrgRole.fromWire(m['role'] as String? ?? ''),
      status: MemberStatus.fromWire(m['status'] as String?),
      firstName: m['firstName'] as String? ?? '',
      lastName: m['lastName'] as String? ?? '',
      email: m['email'] as String? ?? '',
      joinedAt: (m['joinedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  Stream<List<Membership>> watchMyMemberships(String uid) => _db
      .collectionGroup('members')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(_membership).toList());

  @override
  Stream<Organization?> watchOrg(String orgId) =>
      _db.collection('orgs').doc(orgId).snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final settings = d['settings'] as Map<String, dynamic>? ?? const {};
        const defaults = OrgSettings();
        return Organization(
          id: s.id,
          name: d['name'] as String? ?? '',
          status: OrgStatus.fromWire(d['status'] as String?),
          settings: OrgSettings(
            currency: settings['currency'] as String? ?? defaults.currency,
            timezone: settings['timezone'] as String? ?? defaults.timezone,
            weekStart: settings['weekStart'] as int? ?? defaults.weekStart,
            use24h: settings['use24h'] as bool? ?? defaults.use24h,
            csvSeparator:
                settings['csvSeparator'] as String? ?? defaults.csvSeparator,
            csvDecimal:
                settings['csvDecimal'] as String? ?? defaults.csvDecimal,
          ),
        );
      });

  @override
  Stream<List<Membership>> watchMembers(String orgId) => _db
      .collection('orgs')
      .doc(orgId)
      .collection('members')
      .snapshots()
      .map((s) => s.docs.map(_membership).toList());

  @override
  Stream<List<Invite>> watchPendingInvites(String orgId) => _db
      .collection('orgs')
      .doc(orgId)
      .collection('invites')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map(
        (s) => s.docs.map((d) {
          final m = d.data();
          return Invite(
            id: d.id,
            email: m['email'] as String? ?? '',
            role: OrgRole.fromWire(m['role'] as String? ?? ''),
            expiresAt: (m['expiresAt'] as Timestamp?)?.toDate() ?? DateTime(0),
          );
        }).toList()..sort((a, b) => b.expiresAt.compareTo(a.expiresAt)),
      );

  @override
  Future<String> createOrganization({
    required String name,
    required String currency,
    required String timezone,
  }) async {
    final r = await _functions.call('createOrganization', {
      'name': name,
      'currency': currency,
      'timezone': timezone,
    });
    return r['orgId'] as String;
  }

  @override
  Future<String> acceptInvite(String code) async {
    final r = await _functions.call('acceptInvite', {'code': code});
    return r['orgId'] as String;
  }

  @override
  Future<List<MyInvite>> myInvites() async {
    final r = await _functions.call('listMyInvites', {});
    final list = r['invites'];
    return [
      for (final i in (list is List ? list : const []))
        if (i is Map)
          MyInvite(
            orgId: i['orgId'] as String,
            inviteId: i['inviteId'] as String,
            orgName: i['orgName'] as String? ?? '',
            inviterName: i['inviterName'] as String? ?? '',
            role: OrgRole.fromWire(i['role'] as String? ?? ''),
          ),
    ];
  }

  @override
  Future<String> acceptInviteById({
    required String orgId,
    required String inviteId,
  }) async {
    final r = await _functions.call('acceptInvite', {
      'orgId': orgId,
      'inviteId': inviteId,
    });
    return r['orgId'] as String;
  }

  static InviteCode _code(Map<String, dynamic> r) => InviteCode(
    code: r['code'] as String,
    expiresAt: DateTime.parse(r['expiresAt'] as String),
  );

  @override
  Future<InviteCode> createInvite({
    required String orgId,
    required String email,
    required OrgRole role,
  }) async => _code(
    await _functions.call('createInvite', {
      'orgId': orgId,
      'email': email,
      'role': role.wire,
    }),
  );

  @override
  Future<InviteCode> resendInvite({
    required String orgId,
    required String inviteId,
  }) async => _code(
    await _functions.call('resendInvite', {
      'orgId': orgId,
      'inviteId': inviteId,
    }),
  );

  @override
  Future<void> revokeInvite({
    required String orgId,
    required String inviteId,
  }) => _functions.call('revokeInvite', {'orgId': orgId, 'inviteId': inviteId});

  @override
  Future<void> setMemberRole({
    required String orgId,
    required String uid,
    required OrgRole role,
  }) => _functions.call('setMemberRole', {
    'orgId': orgId,
    'uid': uid,
    'role': role.wire,
  });

  @override
  Future<void> setMemberStatus({
    required String orgId,
    required String uid,
    required MemberStatus status,
  }) => _functions.call('setMemberStatus', {
    'orgId': orgId,
    'uid': uid,
    'status': status.wire,
  });

  @override
  Future<void> removeMember({required String orgId, required String uid}) =>
      _functions.call('removeMember', {'orgId': orgId, 'uid': uid});

  @override
  Future<void> transferOwnership({
    required String orgId,
    required String uid,
  }) => _functions.call('transferOwnership', {'orgId': orgId, 'uid': uid});

  @override
  Future<void> leaveOrganization(String orgId) =>
      _functions.call('leaveOrganization', {'orgId': orgId});

  @override
  Future<void> deleteOrganization({
    required String orgId,
    required String confirmName,
  }) => _functions.call('deleteOrganization', {
    'orgId': orgId,
    'confirmName': confirmName,
  });

  @override
  Future<void> deleteAccount() => _functions.call('deleteAccount', {});

  @override
  Future<void> updateOrganization({
    required String orgId,
    required String name,
    required OrgSettings settings,
  }) async {
    final write = _db.collection('orgs').doc(orgId).update({
      'name': name.trim(),
      'settings': {
        'currency': settings.currency,
        'timezone': settings.timezone,
        'weekStart': settings.weekStart,
        'use24h': settings.use24h,
        'csvSeparator': settings.csvSeparator,
        'csvDecimal': settings.csvDecimal,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      // Settings are rare: wait for the server so a rejected change shows.
      await write.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AppException(AppErrorCode.network);
    } catch (e) {
      throw appErrorFrom(e);
    }
  }

  @override
  Stream<List<AuditEntry>> watchAuditLog(String orgId, {int limit = 100}) => _db
      .collection('orgs')
      .doc(orgId)
      .collection('auditLog')
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => s.docs.map((d) {
          final m = d.data();
          return AuditEntry(
            id: d.id,
            at: (m['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
            actorUid: m['actorUid'] as String? ?? '',
            action: m['action'] as String? ?? '',
            entity: m['entity'] as String? ?? '',
            entityId: m['entityId'] as String? ?? '',
            details: Map<String, Object?>.from(
              m['details'] as Map? ?? const {},
            ),
          );
        }).toList(),
      );
}
