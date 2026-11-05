import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors.dart';

/// Maps a Firestore error to an [AppException] for the UI.
Object appErrorFrom(Object e) {
  if (e is AppException) return e;
  if (e is FirebaseException) {
    final code = switch (e.code) {
      'permission-denied' => AppErrorCode.permissionDenied,
      'unavailable' || 'deadline-exceeded' => AppErrorCode.network,
      _ => AppErrorCode.unknown,
    };
    return AppException(code, '${e.code}: ${e.message}');
  }
  return AppException(AppErrorCode.unknown, '$e');
}
