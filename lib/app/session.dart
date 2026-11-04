import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../domain/models.dart';

/// Where the signed-in user is in onboarding (spec §4): signed in → profile →
/// organization. Drives the router's redirects.
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

/// Profile done, but no organization yet: create one or join with a code.
final class SessionNeedsOrganization extends SessionStatus {
  const SessionNeedsOrganization(this.user, this.profile);

  final AuthUser user;
  final UserProfile profile;
}

final class SessionReady extends SessionStatus {
  const SessionReady(
    this.user,
    this.profile, {
    required this.memberships,
    required this.membership,
  });

  final AuthUser user;
  final UserProfile profile;

  /// Every organization the user belongs to.
  final List<Membership> memberships;

  /// The organization in use: the last one used, else the first.
  final Membership membership;

  String get orgId => membership.orgId;
}

/// Picks the organization in use (spec §4.4: the last used one is
/// remembered across devices in `users/{uid}.lastOrgId`).
Membership? activeMembership(List<Membership> memberships, String? lastOrgId) {
  if (memberships.isEmpty) return null;
  for (final m in memberships) {
    if (m.orgId == lastOrgId) return m;
  }
  final active = memberships.where((m) => m.isActive);
  return active.isNotEmpty ? active.first : memberships.first;
}

final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(profileRepositoryProvider).watchProfile(user.uid);
});

final myMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(orgRepositoryProvider).watchMyMemberships(user.uid);
});

/// Any organization by ID (for names in the switcher).
final orgProvider = StreamProvider.family<Organization?, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).watchOrg(orgId),
);

/// The organization in use, or `null` before one is chosen.
final currentOrgProvider = Provider<AsyncValue<Organization?>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session is! SessionReady) return const AsyncData(null);
  return ref.watch(orgProvider(session.orgId));
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

  final membershipsState = ref.watch(myMembershipsProvider);
  if (!membershipsState.hasValue && !membershipsState.hasError) {
    return const SessionLoading();
  }
  // Drop a previous user's memberships that may linger while reloading.
  final memberships = (membershipsState.value ?? const <Membership>[])
      .where((m) => m.uid == user.uid)
      .toList();
  final membership = activeMembership(memberships, current.lastOrgId);
  if (membership == null) {
    if (membershipsState.isLoading) return const SessionLoading();
    return SessionNeedsOrganization(user, current);
  }
  return SessionReady(
    user,
    current,
    memberships: memberships,
    membership: membership,
  );
});
