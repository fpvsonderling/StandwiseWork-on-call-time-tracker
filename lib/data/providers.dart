import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/flavor.dart';
import 'repositories/auth_repository.dart';
import 'repositories/platform_check_repository.dart';
import 'unconfigured.dart';

/// Overridden in `bootstrap()`; tests override with fakes.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

/// Whether Firebase initialized successfully at startup.
final firebaseReadyProvider = Provider<bool>((ref) => false);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const UnconfiguredAuthRepository(),
);

final platformCheckRepositoryProvider = Provider<PlatformCheckRepository>(
  (ref) => const UnconfiguredPlatformCheckRepository(),
);
