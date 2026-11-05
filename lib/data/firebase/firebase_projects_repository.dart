import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/projects.dart';
import '../repositories/projects_repository.dart';
import '../sync.dart';
import 'firestore_errors.dart';

class FirebaseProjectsRepository implements ProjectsRepository {
  FirebaseProjectsRepository(this._db, this._sync);

  final FirebaseFirestore _db;
  final SyncTracker _sync;

  CollectionReference<Map<String, dynamic>> _projects(String orgId) =>
      _db.collection('orgs').doc(orgId).collection('projects');

  CollectionReference<Map<String, dynamic>> _rates(String orgId, String uid) =>
      _db
          .collection('orgs')
          .doc(orgId)
          .collection('members')
          .doc(uid)
          .collection('rates');

  @override
  Stream<List<Project>> watchProjects(String orgId) =>
      _projects(orgId).snapshots().map(
        (s) => s.docs.map((d) {
          final m = d.data();
          return Project(
            id: d.id,
            name: m['name'] as String? ?? '',
            client: m['client'] as String? ?? '',
            color: m['color'] as int? ?? projectPalette.first,
            archived: m['archived'] as bool? ?? false,
            deleted: m['deleted'] as bool? ?? false,
          );
        }).toList(),
      );

  @override
  String newProjectId(String orgId) => _projects(orgId).doc().id;

  @override
  Future<void> saveProject(
    String orgId,
    Project project, {
    required bool isNew,
  }) async {
    final ref = _projects(orgId).doc(project.id);
    final data = <String, Object?>{
      'name': project.name.trim(),
      'client': project.client.trim(),
      'color': project.color,
      'archived': project.archived,
      'deleted': project.deleted,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    _sync.track(
      isNew
          ? ref.set({...data, 'createdAt': FieldValue.serverTimestamp()})
          : ref.update(data),
      mapError: appErrorFrom,
    );
  }

  @override
  Stream<Map<String, ProjectRate>> watchRates(String orgId, String uid) =>
      _rates(orgId, uid).snapshots().map(
        (s) => {
          for (final d in s.docs)
            d.id: ProjectRate(
              projectId: d.id,
              workRateMinor: d.data()['workRateMinor'] as int? ?? 0,
              standbyRateMinor: d.data()['standbyRateMinor'] as int? ?? 0,
            ),
        },
      );

  @override
  Future<void> saveRate(String orgId, String uid, ProjectRate rate) async {
    _sync.track(
      _rates(orgId, uid).doc(rate.projectId).set({
        'workRateMinor': rate.workRateMinor,
        'standbyRateMinor': rate.standbyRateMinor,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      mapError: appErrorFrom,
    );
  }
}
