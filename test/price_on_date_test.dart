import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/price_on_date.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';

List<PricePoint> series() => [
      PricePoint(DateTime(2026, 8, 20), 0.6492),
      PricePoint(DateTime(2026, 8, 21), 0.6319),
      PricePoint(DateTime(2026, 8, 22), 0.6364),
      PricePoint(DateTime(2026, 8, 25), 0.5985),
    ];

void main() {
  group('picking the price that applied', () {
    test('an exact day returns that day', () {
      expect(priceOnDate(series(), DateTime(2026, 8, 21)), 0.6319);
      expect(priceOnDate(series(), DateTime(2026, 8, 25)), 0.5985);
    });

    test('a gap falls back to the last known close', () {
      // Nothing recorded on the 23rd or 24th, so the 22nd still applies.
      expect(priceOnDate(series(), DateTime(2026, 8, 23)), 0.6364);
      expect(priceOnDate(series(), DateTime(2026, 8, 24)), 0.6364);
    });

    test('the time of day does not matter, only the date', () {
      expect(priceOnDate(series(), DateTime(2026, 8, 21, 23, 59)), 0.6319);
      expect(priceOnDate(series(), DateTime(2026, 8, 21, 0, 1)), 0.6319);
    });

    test('it never looks forward', () {
      // A price that had not happened yet cannot be what something was worth.
      expect(priceOnDate(series(), DateTime(2026, 8, 19)), isNull);
      expect(priceOnDate(series(), DateTime(2022, 1, 1)), isNull);
    });

    test('a date beyond the series uses the latest known price', () {
      expect(priceOnDate(series(), DateTime(2026, 12, 31)), 0.5985);
    });

    test('an empty series yields nothing', () {
      expect(priceOnDate(const [], DateTime(2026, 8, 21)), isNull);
    });

    test('unsorted samples are handled', () {
      final shuffled = [
        PricePoint(DateTime(2026, 8, 25), 0.5985),
        PricePoint(DateTime(2026, 8, 20), 0.6492),
        PricePoint(DateTime(2026, 8, 22), 0.6364),
      ];
      expect(priceOnDate(shuffled, DateTime(2026, 8, 23)), 0.6364);
    });

    test('two samples on one day take the later one', () {
      final intraday = [
        PricePoint(DateTime(2026, 8, 21, 3), 0.60),
        PricePoint(DateTime(2026, 8, 21, 22), 0.65),
      ];
      expect(priceOnDate(intraday, DateTime(2026, 8, 21)), 0.65,
          reason: 'the closing figure is the one that applied');
    });
  });

  group('isToday', () {
    final now = DateTime(2026, 8, 25, 14, 30);

    test('the same date at any hour counts as today', () {
      expect(isToday(DateTime(2026, 8, 25), now: now), isTrue);
      expect(isToday(DateTime(2026, 8, 25, 23, 59), now: now), isTrue);
    });

    test('yesterday and tomorrow do not', () {
      expect(isToday(DateTime(2026, 8, 24, 23, 59), now: now), isFalse);
      expect(isToday(DateTime(2026, 8, 26), now: now), isFalse);
    });

    test('the same day in a different month or year does not', () {
      expect(isToday(DateTime(2026, 7, 25), now: now), isFalse);
      expect(isToday(DateTime(2025, 8, 25), now: now), isFalse);
    });
  });
}
