import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/session.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../common/widgets.dart';
import '../org/organization_choice_screen.dart' show orgCurrencies;

/// Settings → Organization (admins, spec §5.7): name, currency, timezone,
/// first day of week, clock and CSV format.
class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _form = GlobalKey<FormState>();
  TextEditingController? _name;
  TextEditingController? _timezone;
  late String _currency;
  late int _weekStart;
  late bool _use24h;
  late String _csv; // "<separator><decimal>"
  bool _saving = false;

  @override
  void dispose() {
    _name?.dispose();
    _timezone?.dispose();
    super.dispose();
  }

  void _init(Organization org) {
    if (_name != null) return;
    _name = TextEditingController(text: org.name);
    _timezone = TextEditingController(text: org.settings.timezone);
    _currency = org.settings.currency;
    _weekStart = org.settings.weekStart;
    _use24h = org.settings.use24h;
    _csv = '${org.settings.csvSeparator}${org.settings.csvDecimal}';
  }

  Future<void> _save(String orgId) async {
    if (!_form.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref
          .read(orgRepositoryProvider)
          .updateOrganization(
            orgId: orgId,
            name: _name!.text,
            settings: OrgSettings(
              currency: _currency,
              timezone: _timezone!.text.trim(),
              weekStart: _weekStart,
              use24h: _use24h,
              csvSeparator: _csv.substring(0, 1),
              csvDecimal: _csv.substring(1),
            ),
          );
      if (mounted) showError(context, l10n.saved);
    } catch (e) {
      if (mounted) showError(context, l10n.error(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    final org = ref.watch(currentOrgProvider).value;
    if (ctx == null || org == null || !ctx.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.settingsOrgDetails)),
        body: Center(child: Text(l10n.errorNotAdmin)),
      );
    }
    _init(org);
    final enabled = ctx.writable && !_saving;
    final currencies = {...orgCurrencies, _currency}.toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsOrgDetails)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: enabled,
                      maxLength: 100,
                      decoration: InputDecoration(labelText: l10n.orgName),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: InputDecoration(labelText: l10n.orgCurrency),
                      onChanged: enabled
                          ? (v) => setState(() => _currency = v!)
                          : null,
                      items: [
                        for (final c in currencies)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _timezone,
                      enabled: enabled,
                      decoration: InputDecoration(
                        labelText: l10n.orgTimezone,
                        helperText: l10n.orgTimezoneHelp,
                      ),
                      validator: (v) =>
                          RegExp(r'^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$')
                              .hasMatch((v ?? '').trim())
                          ? null
                          : l10n.orgTimezoneInvalid,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _weekStart,
                      decoration: InputDecoration(labelText: l10n.weekStart),
                      onChanged: enabled
                          ? (v) => setState(() => _weekStart = v!)
                          : null,
                      items: [
                        for (final d in [
                          DateTime.monday,
                          DateTime.saturday,
                          DateTime.sunday,
                        ])
                          DropdownMenuItem(
                            value: d,
                            child: Text(_weekdayName(context, d)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.use24h),
                      value: _use24h,
                      onChanged: enabled
                          ? (v) => setState(() => _use24h = v)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _csv,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.csvFormat),
                      onChanged: enabled
                          ? (v) => setState(() => _csv = v!)
                          : null,
                      items: [
                        DropdownMenuItem(
                          value: ',.',
                          child: Text(
                            l10n.csvFormatComma,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: ';,',
                          child: Text(
                            l10n.csvFormatSemicolon,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: '\t.',
                          child: Text(
                            l10n.csvFormatTab,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (![',.', ';,', '\t.'].contains(_csv))
                          DropdownMenuItem(value: _csv, child: Text(_csv)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: enabled ? () => _save(ctx.orgId) : null,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.save),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayName(BuildContext context, int weekday) {
  // 2024-01-01 was a Monday.
  final d = DateTime(2024, 1, weekday);
  return MaterialLocalizations.of(context).formatFullDate(d).split(',').first;
}
