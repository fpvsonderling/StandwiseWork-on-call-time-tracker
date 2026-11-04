import 'package:flutter/material.dart';

/// Layout breakpoints (spec §5.8).
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 900;
}

/// Semantic colors not covered by [ColorScheme]: green for Start/Work, amber
/// for Standby, red for Stop/delete (spec §5.8).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.work,
    required this.onWork,
    required this.standby,
    required this.onStandby,
    required this.stop,
    required this.onStop,
  });

  final Color work;
  final Color onWork;
  final Color standby;
  final Color onStandby;
  final Color stop;
  final Color onStop;

  static const light = StatusColors(
    work: Color(0xFF1B7F4B),
    onWork: Colors.white,
    standby: Color(0xFFB86E00),
    onStandby: Colors.white,
    stop: Color(0xFFC62828),
    onStop: Colors.white,
  );

  static const dark = StatusColors(
    work: Color(0xFF5DD39A),
    onWork: Color(0xFF00391F),
    standby: Color(0xFFFFB74D),
    onStandby: Color(0xFF452B00),
    stop: Color(0xFFFF8A80),
    onStop: Color(0xFF5C0000),
  );

  @override
  StatusColors copyWith({
    Color? work,
    Color? onWork,
    Color? standby,
    Color? onStandby,
    Color? stop,
    Color? onStop,
  }) => StatusColors(
    work: work ?? this.work,
    onWork: onWork ?? this.onWork,
    standby: standby ?? this.standby,
    onStandby: onStandby ?? this.onStandby,
    stop: stop ?? this.stop,
    onStop: onStop ?? this.onStop,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      work: Color.lerp(work, other.work, t)!,
      onWork: Color.lerp(onWork, other.onWork, t)!,
      standby: Color.lerp(standby, other.standby, t)!,
      onStandby: Color.lerp(onStandby, other.onStandby, t)!,
      stop: Color.lerp(stop, other.stop, t)!,
      onStop: Color.lerp(onStop, other.onStop, t)!,
    );
  }
}

extension StatusColorsX on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>()!;
}

/// Tabular figures so time digits don't jump (spec §5.8).
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

abstract final class AppTheme {
  /// Deep teal-blue brand seed; Work/Standby/Stop live in [StatusColors].
  static const Color _seed = Color(0xFF1E5F74);

  static ThemeData light() => _build(Brightness.light, StatusColors.light);

  static ThemeData dark() => _build(Brightness.dark, StatusColors.dark);

  static ThemeData _build(Brightness brightness, StatusColors status) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return base.copyWith(
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
