import '../../domain/models.dart';

/// The signed-in user's own profile document (`users/{uid}`).
abstract interface class ProfileRepository {
  /// Emits `null` while the profile document does not exist yet.
  Stream<UserProfile?> watchProfile(String uid);

  /// Saves the first and last name (normalized) plus the account email.
  ///
  /// [exists] says whether the profile document already exists, so its
  /// `createdAt` is set only once. Completes once the write is accepted or
  /// queued offline; throws `AppException` if it is rejected.
  Future<void> saveName({
    required AuthUser user,
    required String firstName,
    required String lastName,
    required bool exists,
  });

  /// Remembers the organization last used on any device (spec §4.4).
  Future<void> setLastOrg({required String uid, required String orgId});
}
