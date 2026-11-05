import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/sync.dart';
import '../domain/models.dart';
import '../domain/projects.dart';
import 'session.dart';

/// Who is working where: the signed-in member in the organization in use.
class WorkContext {
  const WorkContext({
    required this.orgId,
    required this.uid,
    required this.membership,
    required this.settings,
    required this.writable,
  });

  final String orgId;
  final String uid;
  final Membership membership;
  final OrgSettings settings;

  /// Active member of a trial/active organization (spec §3.2).
  final bool writable;

  bool get isAdmin => membership.isAdmin;
  String get currency => settings.currency;
}

/// `null` until a session with an organization is ready.
final workContextProvider = Provider<WorkContext?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session is! SessionReady) return null;
  final org = ref.watch(currentOrgProvider).value;
  return WorkContext(
    orgId: session.orgId,
    uid: session.user.uid,
    membership: session.membership,
    settings: org?.settings ?? const OrgSettings(),
    writable: session.membership.isActive && (org?.status.writable ?? true),
  );
});

/// All projects of the organization in use (including archived/deleted).
final projectsProvider = StreamProvider<List<Project>>((ref) {
  final orgId = ref.watch(workContextProvider.select((c) => c?.orgId));
  if (orgId == null) return Stream.value(const []);
  return ref.watch(projectsRepositoryProvider).watchProjects(orgId);
});

final projectsByIdProvider = Provider<Map<String, Project>>(
  (ref) => {
    for (final p in ref.watch(projectsProvider).value ?? const <Project>[])
      p.id: p,
  },
);

/// Projects offered in pickers: active, sorted by name.
final activeProjectsProvider = Provider<List<Project>>(
  (ref) => sortedProjects(
    (ref.watch(projectsProvider).value ?? const <Project>[]).where(
      (p) => p.active,
    ),
  ),
);

/// The signed-in member's own rates, keyed by project ID.
final myRatesProvider = StreamProvider<Map<String, ProjectRate>>((ref) {
  final ctx = ref.watch(
    workContextProvider.select((c) => c == null ? null : (c.orgId, c.uid)),
  );
  if (ctx == null) return Stream.value(const {});
  return ref.watch(projectsRepositoryProvider).watchRates(ctx.$1, ctx.$2);
});

final syncStateProvider = StreamProvider<SyncState>(
  (ref) => ref.watch(syncTrackerProvider).states,
);
