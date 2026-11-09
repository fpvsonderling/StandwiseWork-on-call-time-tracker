/// The product name lives here and only here (spec: "keep the name in one
/// config place"). Store texts in `store/` and native app labels are the only
/// other places that repeat it; see docs/DECISIONS.md.
abstract final class Brand {
  static const String appName = 'Standwise';
  static const String urlScheme = 'standwise';
  static const String repoUrl =
      'https://github.com/fpvsonderling/StandwiseWork-on-call-time-tracker';
  /// Public copies of the bundled legal texts, for the store listings only;
  /// the app shows its own copies (lib/features/legal).
  static const String privacyPolicyUrl = '$repoUrl/blob/main/docs/PRIVACY.md';
  static const String termsUrl = '$repoUrl/blob/main/docs/TERMS.md';
}
