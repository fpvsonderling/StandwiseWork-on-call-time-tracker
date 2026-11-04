import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n.dart';
import '../../app/router.dart';
import '../../app/session.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../domain/person_name.dart';

/// Required "Your name" step after the first sign-in (spec §4.2). Prefilled
/// from the Google display name; the user confirms or corrects it.
class ProfileSetupScreen extends ConsumerWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    if (session is! SessionNeedsProfile) {
      // The router is about to move on.
      return const Scaffold(body: SizedBox.shrink());
    }
    final existing = session.profile;
    final google = splitDisplayName(session.user.displayName);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileSetupTitle),
        automaticallyImplyLeading: false,
      ),
      body: ProfileForm(
        user: session.user,
        intro: l10n.profileSetupIntro,
        initialFirst: existing?.firstName.isNotEmpty == true
            ? existing!.firstName
            : google.first,
        initialLast: existing?.lastName.isNotEmpty == true
            ? existing!.lastName
            : google.last,
        exists: existing != null,
        submitLabel: l10n.profileContinue,
        footer: TextButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: Text(l10n.profileUseOtherAccount),
        ),
      ),
    );
  }
}

/// Settings → Profile: change first and last name later (spec §4.2).
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileEditTitle)),
      body: switch (session) {
        SessionReady(:final user, :final profile) => ProfileForm(
          user: user,
          initialFirst: profile.firstName,
          initialLast: profile.lastName,
          exists: true,
          submitLabel: l10n.profileSave,
          onSaved: () {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
            context.go(Routes.settings);
          },
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// First/last name form shared by setup and Settings → Profile.
class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({
    super.key,
    required this.user,
    required this.initialFirst,
    required this.initialLast,
    required this.exists,
    required this.submitLabel,
    this.intro,
    this.footer,
    this.onSaved,
  });

  final AuthUser user;
  final String initialFirst;
  final String initialLast;
  final bool exists;
  final String submitLabel;
  final String? intro;
  final Widget? footer;
  final VoidCallback? onSaved;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.initialFirst);
  late final _last = TextEditingController(text: widget.initialLast);
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final l10n = context.l10n;
    return switch (validateName(v ?? '')) {
      null => null,
      NameError.empty => l10n.nameErrorEmpty,
      NameError.tooLong => l10n.nameErrorTooLong,
      NameError.invalidCharacters => l10n.nameErrorInvalid,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .saveName(
            user: widget.user,
            firstName: _first.text,
            lastName: _last.text,
            exists: widget.exists,
          );
      if (mounted) widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.intro != null) ...[
                  Text(widget.intro!, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 24),
                ],
                TextFormField(
                  controller: _first,
                  decoration: InputDecoration(labelText: l10n.profileFirstName),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  textInputAction: TextInputAction.next,
                  maxLength: maxNameLength,
                  validator: _validate,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _last,
                  decoration: InputDecoration(labelText: l10n.profileLastName),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  textInputAction: TextInputAction.done,
                  maxLength: maxNameLength,
                  validator: _validate,
                  onFieldSubmitted: (_) => _busy ? null : _submit(),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: widget.user.email,
                  readOnly: true,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: l10n.profileEmail,
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.submitLabel),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.error(_error!),
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (widget.footer != null) ...[
                  const SizedBox(height: 16),
                  Center(child: widget.footer),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
