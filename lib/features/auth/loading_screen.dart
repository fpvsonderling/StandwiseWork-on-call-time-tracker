import 'package:flutter/material.dart';

import '../../app/l10n.dart';

/// Shown while the sign-in state and profile load.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        label: context.l10n.loadingMessage,
        child: const CircularProgressIndicator(),
      ),
    ),
  );
}
