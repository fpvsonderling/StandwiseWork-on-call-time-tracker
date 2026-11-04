import '../../app/flavor.dart';
import 'google_tokens.dart';

/// Non-IO platforms (future Web): no desktop-specific provider.
GoogleTokenProvider? platformGoogleTokenProvider(AppConfig config) => null;
