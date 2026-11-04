import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';

/// Calls HTTPS callable Cloud Functions with the plain callable protocol
/// (`POST {"data": …}` → `{"result": …}` or `{"error": …}`), so it works the
/// same on every platform, including Windows where the `cloud_functions`
/// plugin is not available (docs/DECISIONS.md D-026).
class CallableClient {
  CallableClient({
    required this.baseUrl,
    required this.idToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// e.g. `https://europe-west1-standwise-dev.cloudfunctions.net` or the
  /// emulator `http://127.0.0.1:5001/standwise-dev/europe-west1`.
  final String baseUrl;
  final Future<String?> Function() idToken;
  final http.Client _http;

  static const timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, Object?> data,
  ) async {
    final token = await idToken();
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/$name'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AppException(AppErrorCode.network, 'timeout');
    } on http.ClientException catch (e) {
      // Includes socket errors (no connection, DNS) on every platform.
      throw AppException(AppErrorCode.network, e.message);
    }

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw AppException(AppErrorCode.unknown, 'HTTP ${res.statusCode}');
    }
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) throw errorFrom(error);
      if (res.statusCode == 200) {
        final result = body['result'];
        return result is Map<String, dynamic> ? result : <String, dynamic>{};
      }
    }
    throw AppException(AppErrorCode.unknown, 'HTTP ${res.statusCode}');
  }

  /// Maps a callable error to an [AppException], preferring the function's
  /// machine-readable `details.reason` (functions/src/lib/errors.ts).
  static AppException errorFrom(Map<String, dynamic> error) {
    final status = error['status'] as String? ?? '';
    final message = error['message'] as String?;
    final details = error['details'];
    final reason = details is Map ? details['reason'] as String? : null;
    final code = switch (reason) {
      'profile-required' => AppErrorCode.profileRequired,
      'not-admin' => AppErrorCode.notAdmin,
      'org-not-found' => AppErrorCode.notAdmin,
      'org-read-only' => AppErrorCode.orgReadOnly,
      'org-limit' => AppErrorCode.orgLimit,
      'already-member' => AppErrorCode.alreadyMember,
      'invite-pending' => AppErrorCode.invitePending,
      'invite-not-found' => AppErrorCode.inviteNotFound,
      'invite-expired' => AppErrorCode.inviteExpired,
      'invite-used' => AppErrorCode.inviteUsed,
      'invite-email-mismatch' => AppErrorCode.inviteEmailMismatch,
      _ => switch (status) {
        'INVALID_ARGUMENT' => AppErrorCode.invalidInput,
        'PERMISSION_DENIED' ||
        'UNAUTHENTICATED' => AppErrorCode.permissionDenied,
        'UNAVAILABLE' || 'DEADLINE_EXCEEDED' => AppErrorCode.network,
        _ => AppErrorCode.unknown,
      },
    };
    return AppException(code, '$status: $message');
  }
}
