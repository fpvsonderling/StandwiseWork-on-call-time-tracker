import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/models.dart';

void main() {
  test('entry amount and duration across midnight', () {
    final e = TimeEntry(
      id: 'e1',
      uid: 'u1',
      type: EntryType.standby,
      rateMinor: 1500,
      start: DateTime.utc(2026, 11, 3, 22),
      end: DateTime.utc(2026, 11, 4, 6, 30),
    );
    expect(e.durationMin, 510);
    expect(e.amountMinor, 12750);
  });

  test('wire values', () {
    expect(EntryType.fromWire('standby'), EntryType.standby);
    expect(EntryType.fromWire('nonsense'), EntryType.work);
    expect(OrgRole.fromWire('admin').isAdminOrOwner, isTrue);
    expect(OrgRole.fromWire('employee').isAdminOrOwner, isFalse);
  });
}
