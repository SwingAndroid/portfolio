import '../../domain/analytics/benchmark.dart';
import '../../domain/analytics/portfolio_series.dart';
import '../../domain/analytics/xirr.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/repositories/crypto_repository.dart';
import 'portfolio_history_service.dart';

/// A yardstick to measure the portfolio against.
class BenchmarkAsset {
  final String coinId;
  final String symbol;

  const BenchmarkAsset(this.coinId, this.symbol);

  static const bitcoin = BenchmarkAsset('bitcoin', 'BTC');
  static const ethereum = BenchmarkAsset('ethereum', 'ETH');
  static const defaults = [bitcoin, ethereum];
}

class BenchmarkComparison {
  final List<BenchmarkOutcome> outcomes;

  /// Share of the portfolio's lifetime contributions that fall inside the
  /// comparable window — the rest predates what any free price API will serve.
  final double windowCoverage;

  final Object? error;

  const BenchmarkComparison({
    required this.outcomes,
    this.windowCoverage = 0,
    this.error,
  });

  static const empty = BenchmarkComparison(outcomes: []);

  bool get hasData => outcomes.isNotEmpty;
}

/// Answers the one question the portfolio's own numbers cannot: would simply
/// holding a single asset have done better?
///
/// Both sides start the window holding the same value and receive identical
/// flows on identical dates, so the only difference is what was held. Anything
/// before the window is excluded from both rather than counted for one —
/// otherwise the comparison would flatter whichever side had the head start.
class BenchmarkService {
  final CryptoRepository repository;
  final PortfolioHistoryService history;

  BenchmarkService({required this.repository, required this.history});

  static const int windowDays = PortfolioHistoryService.maxReconstructableDays;

  Future<BenchmarkComparison> compare({
    required List<CryptoEntity> cryptos,
    List<BenchmarkAsset> against = BenchmarkAsset.defaults,
    DateTime? now,
  }) async {
    if (cryptos.isEmpty) return BenchmarkComparison.empty;

    final actualValue =
        cryptos.fold<double>(0, (s, c) => s + c.holdingsValue);
    if (actualValue <= 0) return BenchmarkComparison.empty;

    // The value curve gives the opening stake, and is already cached.
    final series =
        await history.load(cryptos: cryptos, days: windowDays, now: now);
    if (series.points.length < 2) {
      return BenchmarkComparison(
        outcomes: const [],
        error: series.backfillError,
      );
    }

    final from = series.points.first.date;
    final to = series.points.last.date;
    final startValue = series.points.first.value;
    if (startValue <= 0) return BenchmarkComparison.empty;

    // Transaction flows only: passing a zero valuation suppresses the closing
    // entry, which each side supplies for itself.
    final flows = cashFlowsFor(cryptos, valuationOverride: 0);
    final coverage = _coverage(flows, from);

    final outcomes = <BenchmarkOutcome>[];
    Object? failure;

    for (final asset in against) {
      try {
        final chart =
            await repository.getMarketChart(asset.coinId, days: windowDays);
        if (chart.isEmpty) continue;

        final index = DailyPriceIndex()
          ..add(asset.coinId, chart.map((p) => (time: p.time, price: p.price)));

        final outcome = simulateBenchmark(
          symbol: asset.symbol,
          from: from,
          to: to,
          startValue: startValue,
          actualValue: actualValue,
          flows: flows,
          priceAt: (day) => index.priceAt(asset.coinId, day),
        );
        if (outcome != null) outcomes.add(outcome);
      } catch (e) {
        // One unavailable yardstick must not remove the others.
        failure ??= e;
      }
    }

    return BenchmarkComparison(
      outcomes: outcomes,
      windowCoverage: coverage,
      error: failure ?? series.backfillError,
    );
  }

  /// How much of the money ever put in falls inside the window.
  ///
  /// Reported rather than hidden: a comparison covering two thirds of the
  /// capital is useful, but only if its limits are visible.
  static double _coverage(List<CashFlow> flows, DateTime from) {
    var total = 0.0;
    var inside = 0.0;
    for (final flow in flows) {
      if (flow.amount >= 0) continue; // contributions only
      final amount = -flow.amount;
      total += amount;
      // Matches the simulation: the opening day is already in the start value.
      if (flow.date.isAfter(from)) inside += amount;
    }
    return total <= 0 ? 0 : inside / total;
  }
}
