import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../core/auth/google_tokens.dart';
import '../../core/errors.dart';
import '../../data/providers.dart';
import '../legal/legal_screen.dart';

/// Signed-out start screen: what the app does, Google sign-in, privacy link
/// (spec §4.1). The router moves on once Firebase reports the user.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;

  /// A failed sign-in, shown in red.
  Object? _error;

  /// The account picker closed without signing in. On Android this also
  /// happens when Credential Manager fails on its own (seen on Xiaomi), so
  /// it is reported and the browser sign-in is offered (D-050).
  AppException? _incomplete;

  Future<void> _signIn({bool browser = false}) async {
    final l10n = context.l10n;
    final auth = ref.read(authRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
      _incomplete = null;
    });
    try {
      if (browser) {
        await auth.signInWithGoogleInBrowser();
      } else {
        await auth.signInWithGoogle(
          messages: BrowserRedirectMessages(
            success: l10n.authRedirectSuccess,
            failure: l10n.authRedirectFailure,
          ),
        );
      }
    } on AppException catch (e) {
      debugPrint('Sign-in failed: ${e.code.name} ${e.detail ?? ''}');
      if (e.code != AppErrorCode.signInCancelled) {
        _error = e;
      } else if (auth.hasBrowserSignIn && !browser) {
        _incomplete = e;
      }
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      _error = e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _details(BuildContext context, Object? e) {
    final detail = e is AppException ? e.detail : e?.toString();
    if (detail == null || detail.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText(
        context.l10n.errorDetails(detail),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final config = ref.watch(appConfigProvider);
    final auth = ref.watch(authRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.appTitle,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  if (config.isDev)
                    Text(
                      l10n.flavorDev,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.welcomeHeadline,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.welcomeBody,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(l10n.welcomeSignIn),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.error(_error!),
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    _details(context, _error),
                  ],
                  if (_incomplete != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.welcomeSignInIncomplete,
                      textAlign: TextAlign.center,
                    ),
                    _details(context, _incomplete),
                  ],
                  if (auth.hasBrowserSignIn &&
                      (_error != null || _incomplete != null)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _signIn(browser: true),
                        icon: const Icon(Icons.open_in_browser),
                        label: Text(l10n.welcomeSignInBrowser),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    l10n.welcomePrivacy,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            showLegalDocument(context, LegalDocument.terms),
                        child: Text(l10n.settingsTerms),
                      ),
                      TextButton(
                        onPressed: () =>
                            showLegalDocument(context, LegalDocument.privacy),
                        child: Text(l10n.settingsPrivacyPolicy),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
