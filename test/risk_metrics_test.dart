import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/risk_metrics.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';

List<ValueSnapshot> series(List<(double value, double invested)> rows) {
  var day = DateTime(2026, 1, 1);
  return [
    for (final r in rows)
      ValueSnapshot(
        date: day = day.add(const Duration(days: 1)),
        value: r.$1,
        invested: r.$2,
      )
  ];
}

void main() {
  group('daily returns', () {
    test('a deposit is not a gain', () {
      // Value doubles purely because money was paid in. The market did
      // nothing, so the return must be zero.
      final returns = dailyReturns(series([(100, 100), (200, 200)]));

      expect(returns.single, closeTo(0, 1e-9),
          reason: 'the naive formula would report +100%');
    });

    test('a withdrawal is not a loss', () {
      final returns = dailyReturns(series([(200, 200), (100, 100)]));
      expect(returns.single, closeTo(0, 1e-9));
    });

    test('a pure market move is reported in full', () {
      final returns = dailyReturns(series([(100, 100), (110, 100)]));
      expect(returns.single, closeTo(0.10, 1e-9));
    });

    test('a market move alongside a deposit is separated out', () {
      // Paid in 50, and the market added another 10 on top.
      final returns = dailyReturns(series([(100, 100), (160, 150)]));
      expect(returns.single, closeTo(0.10, 1e-9));
    });

    test('a single observation yields nothing to measure', () {
      expect(dailyReturns(series([(100, 100)])), isEmpty);
      expect(dailyReturns(const []), isEmpty);
    });

    test('a day starting from zero is skipped rather than dividing by it', () {
      final returns = dailyReturns(series([(0, 0), (100, 100)]));
      expect(returns, isEmpty);
    });
  });

  group('time-weighted index', () {
    test('compounds the market, ignoring contributions', () {
      // +10%, then +10% again, with 10 paid in on the second day:
      // 110 x 1.10 = 121, plus the 10 deposit = 131.
      final index = timeWeightedIndex(
        series([(100, 100), (110, 100), (131, 110)]),
      );

      expect(index.length, 3);
      expect(index[1], closeTo(1.10, 1e-9));
      expect(index[2], closeTo(1.21, 1e-9),
          reason: 'the 10 paid in must not compound as performance');
    });

    test('a total wipeout does not erase the index permanently', () {
      final index = timeWeightedIndex(series([(100, 100), (0, 100)]));
      expect(index.last, greaterThan(0));
    });
  });

  group('drawdown', () {
    test('measures peak to trough, not start to end', () {
      final m = computeRiskMetrics(series([
        (100, 100),
        (150, 100), // peak
        (75, 100), // trough, -50% from peak
        (120, 100),
      ]));

      expect(m.maxDrawdown, closeTo(0.5, 1e-9));
      expect(m.peakDate, DateTime(2026, 1, 3));
      expect(m.troughDate, DateTime(2026, 1, 4));
    });

    test('paying more money in does not paper over a fall', () {
      // Value returns to its old level only because capital was added.
      final m = computeRiskMetrics(series([
        (100, 100),
        (50, 100), // halved
        (100, 150), // back to 100, but 50 of that is new money
      ]));

      expect(m.maxDrawdown, closeTo(0.5, 1e-9));
      expect(m.currentDrawdown, closeTo(0.5, 1e-9),
          reason: 'still 50% below the peak in market terms');
    });

    test('a portfolio only ever rising has no drawdown', () {
      final m = computeRiskMetrics(
        series([(100, 100), (110, 100), (120, 100)]),
      );
      expect(m.maxDrawdown, 0);
      expect(m.currentDrawdown, 0);
      expect(m.peakDate, isNull);
    });

    test('current drawdown is measured against the all-time peak', () {
      final m = computeRiskMetrics(series([
        (100, 100),
        (200, 100),
        (150, 100),
      ]));
      expect(m.currentDrawdown, closeTo(0.25, 1e-9));
    });
  });

  group('volatility', () {
    test('a flat portfolio has none', () {
      final m = computeRiskMetrics(
        series([(100, 100), (100, 100), (100, 100), (100, 100)]),
      );
      expect(m.dailyVolatility, closeTo(0, 1e-12));
      expect(m.annualisedVolatility, closeTo(0, 1e-12));
    });

    test('is annualised over 365 days, not 252', () {
      // Crypto does not close at the weekend.
      final m = computeRiskMetrics(series([
        (100, 100),
        (110, 100),
        (99, 100),
        (115, 100),
      ]));

      expect(m.annualisedVolatility,
          closeTo(m.dailyVolatility * 19.104, 0.01));
    });

    test('reports the best and worst single days', () {
      final m = computeRiskMetrics(series([
        (100, 100),
        (120, 100), // +20%
        (60, 100), // -50%
        (66, 100), // +10%
      ]));

      expect(m.bestDay, closeTo(0.20, 1e-9));
      expect(m.worstDay, closeTo(-0.50, 1e-9));
    });
  });

  group('reliability', () {
    test('a short history is flagged rather than presented as fact', () {
      final m = computeRiskMetrics(
        series([(100, 100), (110, 100), (105, 100)]),
      );
      expect(m.hasData, isTrue);
      expect(m.isReliable, isFalse, reason: 'two returns prove nothing');
    });

    test('a month of readings is enough to stand behind', () {
      final rows = [for (var i = 0; i < 30; i++) (100.0 + i, 100.0)];
      final m = computeRiskMetrics(series(rows));

      expect(m.observations, 29);
      expect(m.isReliable, isTrue);
    });

    test('an empty history is neutral, not an error', () {
      final m = computeRiskMetrics(const []);
      expect(m.hasData, isFalse);
      expect(m.maxDrawdown, 0);
      expect(m.annualisedVolatility, 0);
    });
  });
}
