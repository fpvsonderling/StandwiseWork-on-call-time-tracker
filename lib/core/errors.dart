/// Error codes surfaced to the UI. Screens map each code to an ARB string, so
/// no user-facing text lives in data or core code.
enum AppErrorCode {
  firebaseNotConfigured,
  googleClientNotConfigured,
  signInCancelled,
  signInFailed,
  network,
  permissionDenied,
  unknown,
}

class AppException implements Exception {
  const AppException(this.code, [this.detail]);

  final AppErrorCode code;

  /// Technical detail for logs and the dev platform check; never shown as the
  /// main message.
  final String? detail;

  @override
  String toString() =>
      'AppException(${code.name}${detail == null ? '' : ': $detail'})';
}
