import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../domain/models.dart';

/// Where the signed-in user is in onboarding (spec §4). Drives the router's
/// redirects; organization choice is added in stage 3.
sealed class SessionStatus {
  const SessionStatus();
}

/// Firebase is not configured for this build: open the app as-is.
final class SessionUnconfigured extends SessionStatus {
  const SessionUnconfigured();
}

final class SessionLoading extends SessionStatus {
  const SessionLoading();
}

final class SessionSignedOut extends SessionStatus {
  const SessionSignedOut();
}

/// Signed in, but `users/{uid}` has no valid first/last name yet.
final class SessionNeedsProfile extends SessionStatus {
  const SessionNeedsProfile(this.user, this.profile);

  final AuthUser user;

  /// The incomplete profile, if the document exists.
  final UserProfile? profile;
}

final class SessionReady extends SessionStatus {
  const SessionReady(this.user, this.profile);

  final AuthUser user;
  final UserProfile profile;
}

final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(profileRepositoryProvider).watchProfile(user.uid);
});

final sessionProvider = Provider<SessionStatus>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return const SessionUnconfigured();
  final auth = ref.watch(authStateProvider);
  if (!auth.hasValue && !auth.hasError) return const SessionLoading();
  final user = auth.value;
  if (user == null) return const SessionSignedOut();

  final profileState = ref.watch(profileProvider);
  final profile = profileState.value;
  // A previous user's profile can linger while the new one loads.
  final current = profile?.uid == user.uid ? profile : null;
  if (current == null && profileState.isLoading && !profileState.hasError) {
    return const SessionLoading();
  }
  if (current == null || !current.isComplete) {
    return SessionNeedsProfile(user, current);
  }
  return SessionReady(user, current);
});
