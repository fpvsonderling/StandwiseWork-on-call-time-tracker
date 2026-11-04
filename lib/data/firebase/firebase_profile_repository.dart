import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors.dart';
import '../../domain/models.dart';
import '../../domain/person_name.dart';
import '../repositories/profile_repository.dart';

class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Stream<UserProfile?> watchProfile(String uid) =>
      _doc(uid).snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        return UserProfile(
          uid: uid,
          firstName: d['firstName'] as String? ?? '',
          lastName: d['lastName'] as String? ?? '',
          email: d['email'] as String? ?? '',
          photoUrl: d['photoUrl'] as String?,
          lastOrgId: d['lastOrgId'] as String?,
        );
      });

  @override
  Future<void> saveName({
    required AuthUser user,
    required String firstName,
    required String lastName,
    required bool exists,
  }) async {
    final write = _doc(user.uid).set({
      'firstName': normalizeName(firstName),
      'lastName': normalizeName(lastName),
      'email': user.email,
      if (user.photoUrl != null) 'photoUrl': user.photoUrl,
      if (!exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      // The future completes when the server confirms. Offline it waits for
      // the connection, but the local cache (and so the UI) already has the
      // new name, so don't block on it.
      await write.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      unawaited(
        write.catchError((Object e) {
          debugPrint('Profile write rejected after reconnect: $e');
        }),
      );
    } on FirebaseException catch (e) {
      throw AppException(
        e.code == 'permission-denied'
            ? AppErrorCode.permissionDenied
            : AppErrorCode.unknown,
        '${e.code}: ${e.message}',
      );
    }
  }
}
