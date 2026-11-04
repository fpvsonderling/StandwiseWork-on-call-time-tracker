import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/person_name.dart';

void main() {
  group('validateName', () {
    test('accepts Unicode letters, hyphens, apostrophes, spaces', () {
      for (final n in [
        'Łukasz',
        "O'Neil",
        'Anna-Maria',
        'Jean Luc',
        'Zoë',
        'Ołeksandr',
        'D’Arcy',
      ]) {
        expect(validateName(n), isNull, reason: n);
      }
    });

    test('trims before validating', () {
      expect(validateName('  Ewa  '), isNull);
      expect(normalizeName('  Anna   Maria '), 'Anna Maria');
    });

    test('rejects empty, too long, digits and symbols', () {
      expect(validateName('   '), NameError.empty);
      expect(validateName('a' * 51), NameError.tooLong);
      expect(validateName('a' * 50), isNull);
      expect(validateName('R2D2'), NameError.invalidCharacters);
      expect(validateName('Bob!'), NameError.invalidCharacters);
      expect(validateName("--'"), NameError.invalidCharacters);
    });
  });

  test('splitDisplayName splits on the last space', () {
    expect(splitDisplayName('Anna Maria Kowalska'), (
      first: 'Anna Maria',
      last: 'Kowalska',
    ));
    expect(splitDisplayName('Cher'), (first: 'Cher', last: ''));
    expect(splitDisplayName(null), (first: '', last: ''));
    expect(splitDisplayName('  Jan   Nowak '), (first: 'Jan', last: 'Nowak'));
  });

  test('fullName', () {
    expect(fullName('Jan', 'Nowak'), 'Jan Nowak');
  });
}
