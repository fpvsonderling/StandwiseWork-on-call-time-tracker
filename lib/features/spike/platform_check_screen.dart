import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/auth/google_tokens.dart';
import '../../data/providers.dart';
import '../../data/repositories/platform_check_repository.dart';
import '../../domain/models.dart';

/// Dev-only stage 1 spike (spec §2.1): proves Google sign-in → Firebase Auth,
/// Firestore write/read, real-time listener and the offline cache on the
/// current device. Talks to Firebase only through repository interfaces.
class PlatformCheckScreen extends ConsumerStatefulWidget {
  const PlatformCheckScreen({super.key});

  @override
  ConsumerState<PlatformCheckScreen> createState() =>
      _PlatformCheckScreenState();
}

enum _Step { signIn, write, read, listener, offlineWrite, cacheRead, resync }

enum _Status { pending, running, passed, failed }

class _Result {
  const _Result(this.status, [this.detail]);

  final _Status status;
  final String? detail;
}

class _PlatformCheckScreenState extends ConsumerState<PlatformCheckScreen> {
  final Map<_Step, _Result> _results = {
    for (final s in _Step.values) s: const _Result(_Status.pending),
  };
  bool _running = false;
  ProbeSnapshot? _live;
  StreamSubscription<ProbeSnapshot?>? _sub;
  final _snapshots = StreamController<ProbeSnapshot?>.broadcast();

  String get _platform => defaultTargetPlatform.name;

  @override
  void dispose() {
    _sub?.cancel();
    _snapshots.close();
    super.dispose();
  }

  void _set(_Step step, _Status status, [String? detail]) {
    if (!mounted) return;
    setState(() => _results[step] = _Result(status, detail));
  }

  Future<void> _runStep(_Step step, Future<String?> Function() body) async {
    _set(step, _Status.running);
    try {
      final detail = await body();
      _set(step, _Status.passed, detail);
    } catch (e) {
      _set(step, _Status.failed, e.toString());
      rethrow;
    }
  }

  Future<ProbeSnapshot> _waitFor(
    bool Function(ProbeSnapshot s) test,
    Duration timeout,
  ) {
    if (_live != null && test(_live!)) return Future.value(_live);
    return _snapshots.stream
        .where((s) => s != null && test(s))
        .cast<ProbeSnapshot>()
        .first
        .timeout(timeout);
  }

  Future<void> _runAll() async {
    final l10n = context.l10n;
    final auth = ref.read(authRepositoryProvider);
    final repo = ref.read(platformCheckRepositoryProvider);
    setState(() {
      _running = true;
      for (final s in _Step.values) {
        _results[s] = const _Result(_Status.pending);
      }
    });

    try {
      late AuthUser user;
      await _runStep(_Step.signIn, () async {
        user =
            auth.currentUser ??
            await auth.signInWithGoogle(
              messages: BrowserRedirectMessages(
                success: l10n.authRedirectSuccess,
                failure: l10n.authRedirectFailure,
              ),
            );
        return '${user.email} (verified: ${user.emailVerified})';
      });

      var counter = 0;
      await _runStep(_Step.write, () async {
        final existing = await repo
            .readProbe(uid: user.uid)
            .catchError((_) => null);
        counter = (existing?.counter ?? 0) + 1;
        final sw = Stopwatch()..start();
        await repo
            .writeProbe(uid: user.uid, counter: counter, platform: _platform)
            .timeout(const Duration(seconds: 15));
        return 'counter=$counter in ${sw.elapsedMilliseconds} ms';
      });

      await _runStep(_Step.read, () async {
        final s = await repo.readProbe(uid: user.uid);
        if (s?.counter != counter) {
          throw StateError('expected $counter, got ${s?.counter}');
        }
        return 'counter=${s!.counter}, fromCache=${s.fromCache}';
      });

      await _runStep(_Step.listener, () async {
        await _sub?.cancel();
        _sub = repo.watchProbe(uid: user.uid).listen((s) {
          if (mounted) setState(() => _live = s);
          _snapshots.add(s);
        }, onError: _snapshots.addError);
        final s = await _waitFor(
          (s) => s.counter == counter,
          const Duration(seconds: 10),
        );
        return 'counter=${s.counter}, pendingWrites=${s.hasPendingWrites}';
      });

      Future<void>? offlineWrite;
      final offlineCounter = counter + 1;
      try {
        await _runStep(_Step.offlineWrite, () async {
          await repo.setNetworkEnabled(false);
          // Not awaited: completes only after the server acknowledges it.
          offlineWrite = repo.writeProbe(
            uid: user.uid,
            counter: offlineCounter,
            platform: _platform,
          );
          unawaited(offlineWrite!.catchError((Object _) {}));
          final s = await _waitFor(
            (s) => s.counter == offlineCounter && s.hasPendingWrites,
            const Duration(seconds: 5),
          );
          return 'counter=${s.counter}, pendingWrites=${s.hasPendingWrites}, '
              'persistence=${repo.persistenceEnabled}';
        });

        await _runStep(_Step.cacheRead, () async {
          final s = await repo.readProbe(uid: user.uid, cacheOnly: true);
          if (s?.counter != offlineCounter) {
            throw StateError('expected $offlineCounter, got ${s?.counter}');
          }
          return 'counter=${s!.counter}, fromCache=${s.fromCache}';
        });
      } finally {
        await repo.setNetworkEnabled(true);
      }

      await _runStep(_Step.resync, () async {
        final sw = Stopwatch()..start();
        await offlineWrite?.timeout(const Duration(seconds: 20));
        final s = await _waitFor(
          (s) => s.counter == offlineCounter && !s.hasPendingWrites,
          const Duration(seconds: 20),
        );
        return 'synced in ${sw.elapsedMilliseconds} ms, fromCache=${s.fromCache}';
      });
    } catch (_) {
      // Failure already recorded on the step.
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _report(AppLocalizations l10n) {
    final b = StringBuffer()
      ..writeln('Platform check — ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Platform: $_platform');
    for (final step in _Step.values) {
      final r = _results[step]!;
      b.writeln(
        '- ${_label(l10n, step)}: ${r.status.name}${r.detail == null ? '' : ' — ${r.detail}'}',
      );
    }
    return b.toString();
  }

  String _label(AppLocalizations l10n, _Step s) => switch (s) {
    _Step.signIn => l10n.checkStepSignIn,
    _Step.write => l10n.checkStepWrite,
    _Step.read => l10n.checkStepRead,
    _Step.listener => l10n.checkStepListener,
    _Step.offlineWrite => l10n.checkStepOfflineWrite,
    _Step.cacheRead => l10n.checkStepCacheRead,
    _Step.resync => l10n.checkStepResync,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = context.statusColors;
    final auth = ref.watch(authRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkTitle)),
      body: StreamBuilder<AuthUser?>(
        stream: auth.authStateChanges(),
        builder: (context, snap) {
          final user = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.checkIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              Text(
                l10n.checkPlatform(_platform),
                style: theme.textTheme.labelLarge,
              ),
              Text(
                user == null
                    ? l10n.checkNotSignedIn
                    : l10n.checkSignedInAs(user.email),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _running ? null : _runAll,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.checkRunAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _report(l10n)),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.checkReportCopied)),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(l10n.checkCopyReport),
                  ),
                  if (user != null)
                    TextButton(
                      onPressed: _running ? null : auth.signOut,
                      child: Text(l10n.checkSignOut),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final step in _Step.values)
                _StepTile(
                  label: _label(l10n, step),
                  result: _results[step]!,
                  l10n: l10n,
                  status: status,
                ),
              if (_live != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.checkLiveValue(
                            _live!.counter,
                            _live!.platform ?? '?',
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.checkLiveHint,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.label,
    required this.result,
    required this.l10n,
    required this.status,
  });

  final String label;
  final _Result result;
  final AppLocalizations l10n;
  final StatusColors status;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text) = switch (result.status) {
      _Status.pending => (
        const Icon(Icons.radio_button_unchecked),
        l10n.checkStatusPending,
      ),
      _Status.running => (
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        l10n.checkStatusRunning,
      ),
      _Status.passed => (
        Icon(Icons.check_circle, color: status.work),
        l10n.checkStatusPassed,
      ),
      _Status.failed => (
        Icon(Icons.cancel, color: status.stop),
        l10n.checkStatusFailed,
      ),
    };
    return Semantics(
      label: '$label: $text',
      excludeSemantics: true,
      child: ListTile(
        leading: icon,
        title: Text(label),
        subtitle: Text(
          result.detail == null ? text : '$text — ${result.detail}',
        ),
      ),
    );
  }
}
