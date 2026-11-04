import 'package:flutter/widgets.dart';

import '../core/errors.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppErrorText on AppLocalizations {
  String error(Object e) {
    final code = e is AppException ? e.code : AppErrorCode.unknown;
    return switch (code) {
      AppErrorCode.firebaseNotConfigured => errorFirebaseNotConfigured,
      AppErrorCode.googleClientNotConfigured => errorGoogleClientNotConfigured,
      AppErrorCode.signInCancelled => errorSignInCancelled,
      AppErrorCode.signInFailed => errorSignInFailed,
      AppErrorCode.network => errorNetwork,
      AppErrorCode.permissionDenied => errorPermissionDenied,
      AppErrorCode.unknown => errorUnknown,
    };
  }

  String role(OrgRole role) => switch (role) {
    OrgRole.owner => roleOwner,
    OrgRole.admin => roleAdmin,
    OrgRole.employee => roleEmployee,
  };
}
