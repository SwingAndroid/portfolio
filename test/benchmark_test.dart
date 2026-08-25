import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/benchmark.dart';
import 'package:crypto_portfolio/domain/analytics/xirr.dart';

final from = DateTime(2025, 8, 24);
final to = DateTime(2026, 8, 24);

/// A price that doubles linearly across the window, so expectations are
/// arithmetic rather than guesswork.
double? doubling(DateTime day) {
  final span = to.difference(from).inDays;
  final elapsed = day.difference(from).inDays;
  if (elapsed < 0 || elapsed > span) return null;
  return 100 * (1 + elapsed / span);
}

double? flat(DateTime day) {
  if (day.isBefore(from) || day.isAfter(to)) return null;
  return 100;
}

BenchmarkOutcome? run({
  double startValue = 1000,
  double actualValue = 1000,
  List<CashFlow> flows = const [],
  double? Function(DateTime)? prices,
}) =>
    simulateBenchmark(
      symbol: 'BTC',
      from: from,
      to: to,
      startValue: startValue,
      actualValue: actualValue,
      flows: flows,
      priceAt: prices ?? flat,
    );

void main() {
  group('the yardstick', () {
    test('a flat market returns exactly what went in', () {
      final result = run(startValue: 1000, actualValue: 1200)!;
      expect(result.benchmarkValue, closeTo(1000, 1e-9));
      expect(result.actualValue, 1200);
      expect(result.difference, closeTo(200, 1e-9));
      expect(result.aheadOfBenchmark, isTrue);
    });

    test('a doubling market doubles the opening stake', () {
      final result = run(prices: doubling, startValue: 1000)!;
      expect(result.benchmarkValue, closeTo(2000, 1e-6));
    });

    test('a contribution buys units at that day s price', () {
      // 1000 in at the start, then 600 more at the midpoint where the price
      // is 150: 10 units + 4 units = 14, worth 200 each at the close.
      final mid = from.add(Duration(days: to.difference(from).inDays ~/ 2));
      final result = run(
        prices: doubling,
        startValue: 1000,
        flows: [CashFlow(mid, -600)],
      )!;

      expect(result.benchmarkValue, closeTo(2800, 1.0));
      expect(result.netContributed, closeTo(600, 1e-9));
      expect(result.flowCount, 1);
    });

    test('a withdrawal sells units at that day s price', () {
      final mid = from.add(Duration(days: to.difference(from).inDays ~/ 2));
      final result = run(
        prices: doubling,
        startValue: 1000,
        flows: [CashFlow(mid, 300)],
      )!;

      // 10 units, less 300/150 = 2, leaves 8 worth 200 each.
      expect(result.benchmarkValue, closeTo(1600, 1.0));
      expect(result.netContributed, closeTo(-300, 1e-9));
    });

    test('flows outside the window are ignored', () {
      final result = run(
        flows: [
          CashFlow(from.subtract(const Duration(days: 30)), -5000),
          CashFlow(to.add(const Duration(days: 30)), -5000),
          // The opening day itself is already inside the starting value.
          CashFlow(from, -5000),
        ],
      )!;

      expect(result.flowCount, 0,
          reason: 'the window is the comparison, not the lifetime');
      expect(result.benchmarkValue, closeTo(1000, 1e-9));
    });

    test('withdrawing more than the yardstick holds is capped, not negative',
        () {
      // Selling into a flat market beyond the opening stake would otherwise
      // leave a short position nobody took.
      final result = run(
        startValue: 1000,
        flows: [CashFlow(from.add(const Duration(days: 10)), 5000)],
      )!;

      expect(result.benchmarkValue, 0);
      expect(result.exhausted, isTrue);
    });

    test('a day the yardstick has no price for is skipped, not guessed', () {
      final gap = from.add(const Duration(days: 100));
      final result = simulateBenchmark(
        symbol: 'BTC',
        from: from,
        to: to,
        startValue: 1000,
        actualValue: 1000,
        flows: [CashFlow(gap, -500)],
        priceAt: (d) => d == gap ? null : flat(d),
      )!;

      expect(result.benchmarkValue, closeTo(1000, 1e-9),
          reason: 'the contribution bought nothing rather than an invented '
              'number of units');
    });

    test('no price at either end means no comparison at all', () {
      expect(
        simulateBenchmark(
          symbol: 'BTC',
          from: from,
          to: to,
          startValue: 1000,
          actualValue: 1000,
          flows: const [],
          priceAt: (_) => null,
        ),
        isNull,
      );
    });
  });

  group('the verdict', () {
    test('beating the yardstick reads as ahead', () {
      final result = run(startValue: 1000, actualValue: 1500)!;
      expect(result.aheadOfBenchmark, isTrue);
      expect(result.differencePercent, closeTo(50, 1e-9));
    });

    test('trailing it reads as behind', () {
      final result = run(prices: doubling, startValue: 1000, actualValue: 1200)!;
      expect(result.aheadOfBenchmark, isFalse);
      expect(result.difference, closeTo(-800, 1e-6));
    });

    test('both rates are measured on identical flows', () {
      // Only the closing value differs, which is the whole point: the timing
      // of every contribution is held constant between the two.
      final mid = from.add(const Duration(days: 180));
      final result = run(
        startValue: 1000,
        actualValue: 2000,
        flows: [CashFlow(mid, -500)],
      )!;

      expect(result.actualRate, isNotNull);
      expect(result.benchmarkRate, isNotNull);
      expect(result.actualRate!, greaterThan(result.benchmarkRate!));
      expect(result.rateGap!, greaterThan(0));
    });

    test('an equal outcome shows no gap', () {
      final result = run(startValue: 1000, actualValue: 1000)!;
      expect(result.difference, closeTo(0, 1e-9));
      expect(result.rateGap!, closeTo(0, 1e-6));
    });

    test('a real loss against a rising yardstick is stated plainly', () {
      // The situation this exists to reveal: the portfolio fell while simply
      // holding the benchmark would have grown.
      final result = run(prices: doubling, startValue: 1000, actualValue: 700)!;

      expect(result.aheadOfBenchmark, isFalse);
      expect(result.benchmarkValue, closeTo(2000, 1e-6));
      expect(result.differencePercent, closeTo(-65, 0.1));
      expect(result.actualRate!, lessThan(0));
      expect(result.benchmarkRate!, greaterThan(0));
    });

    test('a portfolio worth exactly nothing has no rate to report', () {
      // Losing everything is a rate of exactly -100%, which is the point the
      // discounting formula cannot express. Reporting nothing is honest;
      // inventing a number next to it would not be.
      final result = run(startValue: 1000, actualValue: 0)!;

      expect(result.actualRate, isNull);
      expect(result.actualValue, 0);
      expect(result.difference, closeTo(-1000, 1e-9),
          reason: 'the money comparison still works');
      expect(result.rateGap, isNull);
    });

    test('a near-total loss does report a rate', () {
      final result = run(startValue: 1000, actualValue: 1)!;
      expect(result.actualRate, isNotNull);
      expect(result.actualRate!, lessThan(-0.9));
    });
  });

  group('window bookkeeping', () {
    test('reports the period it actually measured', () {
      final result = run()!;
      expect(result.from, from);
      expect(result.to, to);
      expect(result.symbol, 'BTC');
    });

    test('net contribution nets deposits against withdrawals', () {
      final result = run(
        flows: [
          CashFlow(from.add(const Duration(days: 10)), -1000),
          CashFlow(from.add(const Duration(days: 20)), 400),
        ],
      )!;

      expect(result.netContributed, closeTo(600, 1e-9));
      expect(result.flowCount, 2);
    });

    test('flows arriving out of order are handled chronologically', () {
      final late = CashFlow(from.add(const Duration(days: 200)), -100);
      final early = CashFlow(from.add(const Duration(days: 10)), -100);

      final ordered = run(prices: doubling, flows: [early, late])!;
      final shuffled = run(prices: doubling, flows: [late, early])!;

      expect(shuffled.benchmarkValue,
          closeTo(ordered.benchmarkValue, 1e-9));
    });
  });
}
