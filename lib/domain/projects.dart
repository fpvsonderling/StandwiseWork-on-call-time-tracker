/// Projects and per-member rates (spec §5.2, §5.4, §6).
library;

import 'models.dart';

/// The 10 project colors admins choose from (ARGB). Readable on light and
/// dark surfaces; distinct from the Work/Standby/Stop status colors.
const List<int> projectPalette = [
  0xFF1E88E5, // blue
  0xFF8E24AA, // purple
  0xFF00897B, // teal
  0xFFD81B60, // pink
  0xFF6D4C41, // brown
  0xFF3949AB, // indigo
  0xFF7CB342, // light green
  0xFFF4511E, // deep orange
  0xFF546E7A, // blue grey
  0xFFC0CA33, // lime
];

/// Rates document ID used for entries without a project (D-029).
const String noProjectKey = '_none';

/// Name prefix of the projects created by "Load sample data" (spec §5.1).
const String sampleProjectPrefix = 'Sample: ';

/// `orgs/{orgId}/projects/{projectId}`.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.client = '',
    this.color = 0xFF1E88E5,
    this.archived = false,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String client;
  final int color;
  final bool archived;

  /// Soft-deleted: hidden everywhere, old entries show "No project
  /// (deleted)".
  final bool deleted;

  /// Shown in pickers.
  bool get active => !archived && !deleted;

  bool get isSample => name.startsWith(sampleProjectPrefix);

  Project copyWith({
    String? name,
    String? client,
    int? color,
    bool? archived,
    bool? deleted,
  }) => Project(
    id: id,
    name: name ?? this.name,
    client: client ?? this.client,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    deleted: deleted ?? this.deleted,
  );
}

/// Validation of a project name or client (rules: 1–100 / 0–100 chars).
const int maxProjectNameLength = 100;

/// One member's own Work and Standby rate for one project, per hour in
/// minor units (`orgs/{orgId}/members/{uid}/rates/{projectId}`).
class ProjectRate {
  const ProjectRate({
    required this.projectId,
    this.workRateMinor = 0,
    this.standbyRateMinor = 0,
  });

  /// A project ID, or [noProjectKey].
  final String projectId;
  final int workRateMinor;
  final int standbyRateMinor;

  int forType(EntryType type) =>
      type == EntryType.work ? workRateMinor : standbyRateMinor;
}

/// The member's current rate for [projectId] and [type]; 0 when not set
/// (spec §5.2: new entries take the current rate).
int currentRate(
  Map<String, ProjectRate> rates,
  String? projectId,
  EntryType type,
) => rates[projectId ?? noProjectKey]?.forType(type) ?? 0;

/// Projects sorted for pickers and lists: by name, case-insensitive.
List<Project> sortedProjects(Iterable<Project> projects) =>
    projects.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
