/// Money helpers. All money is stored and computed in integer minor units
/// (e.g. cents). Doubles are never used for amounts; rounding happens once,
/// in [amountForDuration], and formatting is display-only.
library;

import 'package:intl/intl.dart';

/// Largest hourly rate accepted, in minor units (spec §3.2: 0–1 000 000).
const int maxRateMinor = 1000000;

/// Amount earned for [durationMin] minutes at [rateMinor] per hour.
///
/// Computed as `rateMinor × durationMin / 60`, rounded half up to the nearest
/// minor unit, using integer arithmetic only.
int amountForDuration({required int rateMinor, required int durationMin}) {
  if (rateMinor < 0 || durationMin < 0) {
    throw ArgumentError('rateMinor and durationMin must be non-negative');
  }
  return (rateMinor * durationMin + 30) ~/ 60;
}

/// Parses an hourly rate typed by a user ("12", "12.5", "12,50", " 1 200,00 ")
/// into minor units. Accepts comma or dot as decimal mark and at most two
/// decimals. Returns `null` when the input is not a valid rate.
int? parseRateMinor(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'[\s  ]'), '');
  if (cleaned.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final minor = whole * 100 + int.parse(fraction);
  if (minor > maxRateMinor) return null;
  return minor;
}

/// Formats [minor] units of [currency] for display in [locale].
String formatMoney(int minor, {required String currency, String? locale}) {
  final format = NumberFormat.simpleCurrency(name: currency, locale: locale);
  final digits = format.decimalDigits ?? 2;
  final divisor = _pow10(digits);
  // Display-only conversion; the source of truth stays an int.
  return format.format(minor / divisor);
}

/// Formats [minor] units as a plain decimal number with two decimals using
/// [decimalMark] (used in CSV exports).
String formatMinorPlain(int minor, {String decimalMark = '.'}) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ 100;
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole$decimalMark$cents';
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
