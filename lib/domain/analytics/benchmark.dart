import 'xirr.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// What the same money would have become in a single asset.
class BenchmarkOutcome {
  /// Ticker of the yardstick, e.g. BTC.
  final String symbol;

  final DateTime from;
  final DateTime to;

  /// Value both portfolios started the window with.
  final double startValue;

  /// What the real portfolio is worth now.
  final double actualValue;

  /// What the yardstick would be worth, having received the same flows.
  final double benchmarkValue;

  /// Net money added during the window: positive means more went in than came
  /// out.
  final double netContributed;

  final int flowCount;

  /// Annualised rates over the window. Null when the flows cannot define one.
  final double? actualRate;
  final double? benchmarkRate;

  /// True when withdrawals emptied the yardstick before the window closed, so
  /// the comparison stopped being meaningful.
  final bool exhausted;

  const BenchmarkOutcome({
    required this.symbol,
    required this.from,
    required this.to,
    required this.startValue,
    required this.actualValue,
    required this.benchmarkValue,
    required this.netContributed,
    required this.flowCount,
    this.actualRate,
    this.benchmarkRate,
    this.exhausted = false,
  });

  /// Money ahead of (or behind) the yardstick.
  double get difference => actualValue - benchmarkValue;

  /// Difference as a share of what the yardstick reached.
  double get differencePercent =>
      benchmarkValue > 0 ? (difference / benchmarkValue) * 100 : 0;

  bool get aheadOfBenchmark => difference >= 0;

  /// Gap between the two annualised rates, in percentage points.
  double? get rateGap {
    final a = actualRate;
    final b = benchmarkRate;
    if (a == null || b == null) return null;
    return (a - b) * 100;
  }
}

/// Runs the portfolio's own cash flows through a single asset instead.
///
/// Both start the window holding [startValue], so the comparison measures the
/// period rather than the lifetime — otherwise everything bought before the
/// window would simply be missing from one side. Every contribution and
/// withdrawal then lands on the same day in both, and only the choice of what
/// to hold differs.
///
/// [priceAt] must return the benchmark's price on a given day, or null when
/// that day is not covered.
BenchmarkOutcome? simulateBenchmark({
  required String symbol,
  required DateTime from,
  required DateTime to,
  required double startValue,
  required double actualValue,
  required List<CashFlow> flows,
  required double? Function(DateTime day) priceAt,
}) {
  final startPrice = priceAt(from);
  final endPrice = priceAt(to);
  if (startPrice == null || endPrice == null) return null;
  if (startPrice <= 0 || endPrice <= 0) return null;

  var units = startValue / startPrice;
  var netContributed = 0.0;
  var exhausted = false;

  // Strictly after the opening day. The starting value already reflects every
  // transaction up to and including it, so counting those again as flows would
  // apply them twice — inflating the yardstick by the size of that day's
  // trading and quietly making the portfolio look worse than it was.
  final start = _day(from);
  final end = _day(to);
  final inWindow = flows
      .where((f) {
        final day = _day(f.date);
        return day.isAfter(start) && !day.isAfter(end);
      })
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (final flow in inWindow) {
    final price = priceAt(flow.date);
    if (price == null || price <= 0) continue;

    // A buy is money leaving the pocket (negative), so the yardstick acquires
    // units; a sale is the reverse. One expression covers both.
    units -= flow.amount / price;
    netContributed -= flow.amount;

    if (units < 0) {
      // Withdrawals outran what the yardstick held. Holding a negative
      // position would invent leverage nobody took.
      units = 0;
      exhausted = true;
    }
  }

  final benchmarkValue = units * endPrice;

  // Both rates are measured on identical flows, so only the closing value
  // differs — which is the whole point of the comparison.
  final opening = CashFlow(from, -startValue);
  final actualRate = computeXirr([
    opening,
    ...inWindow,
    if (actualValue > 0) CashFlow(to, actualValue),
  ]);
  final benchmarkRate = computeXirr([
    opening,
    ...inWindow,
    if (benchmarkValue > 0) CashFlow(to, benchmarkValue),
  ]);

  return BenchmarkOutcome(
    symbol: symbol,
    from: from,
    to: to,
    startValue: startValue,
    actualValue: actualValue,
    benchmarkValue: benchmarkValue,
    netContributed: netContributed,
    flowCount: inWindow.length,
    actualRate: actualRate,
    benchmarkRate: benchmarkRate,
    exhausted: exhausted,
  );
}
