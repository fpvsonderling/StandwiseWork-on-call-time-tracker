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
      AppErrorCode.invalidInput => errorInvalidInput,
      AppErrorCode.profileRequired => errorProfileRequired,
      AppErrorCode.notAdmin => errorNotAdmin,
      AppErrorCode.orgReadOnly => errorOrgReadOnly,
      AppErrorCode.orgLimit => errorOrgLimit,
      AppErrorCode.alreadyMember => errorAlreadyMember,
      AppErrorCode.invitePending => errorInvitePending,
      AppErrorCode.inviteNotFound => errorInviteNotFound,
      AppErrorCode.inviteExpired => errorInviteExpired,
      AppErrorCode.inviteUsed => errorInviteUsed,
      AppErrorCode.inviteEmailMismatch => errorInviteEmailMismatch,
      AppErrorCode.memberNotFound => errorMemberNotFound,
      AppErrorCode.ownerProtected => errorOwnerProtected,
      AppErrorCode.selfChange => errorSelfChange,
      AppErrorCode.notOwner => errorNotOwner,
      AppErrorCode.ownerMustTransfer => errorOwnerMustTransfer,
      AppErrorCode.nameMismatch => errorNameMismatch,
      AppErrorCode.projectRequired => errorProjectRequired,
      AppErrorCode.unknown => errorUnknown,
    };
  }

  String role(OrgRole role) => switch (role) {
    OrgRole.owner => roleOwner,
    OrgRole.admin => roleAdmin,
    OrgRole.employee => roleEmployee,
  };
}
