import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../app/l10n.dart';
import '../../domain/date_ranges.dart';
import '../../domain/money.dart';

String localeOf(BuildContext context) =>
    Localizations.localeOf(context).toString();

String money(BuildContext context, int minor, String currency) =>
    formatMoney(minor, currency: currency, locale: localeOf(context));

DateFormat timeFormat(BuildContext context, {bool use24h = true}) => use24h
    ? DateFormat.Hm(localeOf(context))
    : DateFormat.jm(localeOf(context));

String dateLabel(BuildContext context, DateTime day) =>
    DateFormat.yMMMd(localeOf(context)).format(day);

/// "Today", "Yesterday", then "Tuesday, 3 November" (spec §5.1).
String dayLabel(BuildContext context, DateTime day, {DateTime? now}) {
  final l10n = context.l10n;
  final today = dateOnly(now ?? DateTime.now());
  final d = dateOnly(day);
  if (d == today) return l10n.today;
  if (d == DateTime(today.year, today.month, today.day - 1)) {
    return l10n.yesterday;
  }
  final pattern = d.year == today.year ? 'EEEE, d MMMM' : 'EEEE, d MMMM y';
  return DateFormat(pattern, localeOf(context)).format(d);
}
