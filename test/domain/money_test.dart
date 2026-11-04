import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/money.dart';

void main() {
  group('amountForDuration', () {
    test('full hour equals rate', () {
      expect(amountForDuration(rateMinor: 4550, durationMin: 60), 4550);
    });

    test('integer maths, rounds half up once', () {
      // 33.33 €/h for 1 minute = 55.55 cents → 56
      expect(amountForDuration(rateMinor: 3333, durationMin: 1), 56);
      // 10.00 €/h for 1 minute = 16.666 cents → 17
      expect(amountForDuration(rateMinor: 1000, durationMin: 1), 17);
      // exact half: 0.30 €/h for 1 minute = 0.5 cents → 1
      expect(amountForDuration(rateMinor: 30, durationMin: 1), 1);
    });

    test('no floating-point drift on large totals', () {
      // 24h at max rate
      expect(
        amountForDuration(rateMinor: maxRateMinor, durationMin: 24 * 60),
        24 * maxRateMinor,
      );
      // 0.1 + 0.2 style trap: 10 cents/h for 18 minutes = 3 cents exactly
      expect(amountForDuration(rateMinor: 10, durationMin: 18), 3);
    });

    test('rejects negatives', () {
      expect(
        () => amountForDuration(rateMinor: -1, durationMin: 5),
        throwsArgumentError,
      );
    });
  });

  group('parseRateMinor', () {
    test('accepts dot and comma', () {
      expect(parseRateMinor('12'), 1200);
      expect(parseRateMinor('12.5'), 1250);
      expect(parseRateMinor('12,50'), 1250);
      expect(parseRateMinor(' 1 200,05 '), 120005);
      expect(parseRateMinor('0'), 0);
    });

    test('rejects invalid input', () {
      expect(parseRateMinor(''), isNull);
      expect(parseRateMinor('abc'), isNull);
      expect(parseRateMinor('1.234'), isNull);
      expect(parseRateMinor('-5'), isNull);
      expect(parseRateMinor('1,2,3'), isNull);
      expect(parseRateMinor('10000.01'), isNull); // above max
    });

    test('accepts the maximum', () {
      expect(parseRateMinor('10000'), maxRateMinor);
    });
  });

  test('formatMinorPlain', () {
    expect(formatMinorPlain(123456), '1234.56');
    expect(formatMinorPlain(5, decimalMark: ','), '0,05');
    expect(formatMinorPlain(-250), '-2.50');
  });

  test('formatMoney uses currency', () {
    expect(formatMoney(123456, currency: 'EUR', locale: 'en'), '€1,234.56');
  });
}
