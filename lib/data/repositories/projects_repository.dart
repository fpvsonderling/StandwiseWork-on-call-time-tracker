import '../../domain/projects.dart';

/// Projects and the signed-in member's own rates (spec §5.2, §5.4). Plain
/// Firestore writes protected by rules, so they work offline: methods return
/// once the local cache has the change.
abstract interface class ProjectsRepository {
  /// All projects of the organization, including archived and deleted ones
  /// (entries still name them).
  Stream<List<Project>> watchProjects(String orgId);

  /// A new client-generated project ID.
  String newProjectId(String orgId);

  /// Admins only. [isNew] creates the document.
  Future<void> saveProject(
    String orgId,
    Project project, {
    required bool isNew,
  });

  /// The member's own rates keyed by project ID (or [noProjectKey]).
  Stream<Map<String, ProjectRate>> watchRates(String orgId, String uid);

  Future<void> saveRate(String orgId, String uid, ProjectRate rate);
}
