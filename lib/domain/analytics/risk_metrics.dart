import 'dart:math' as math;

import '../entities/value_snapshot.dart';

/// How the portfolio behaved, with contributions stripped out.
class RiskMetrics {
  /// Deepest peak-to-trough fall, as a positive fraction (0.42 = −42%).
  final double maxDrawdown;
  final DateTime? peakDate;
  final DateTime? troughDate;

  /// How far below the all-time peak the portfolio sits today.
  final double currentDrawdown;

  /// Standard deviation of daily returns, and the same scaled to a year.
  final double dailyVolatility;
  final double annualisedVolatility;

  final double bestDay;
  final double worstDay;

  /// Daily returns actually used. Fewer than about 20 and the figures are
  /// indicative at best.
  final int observations;

  const RiskMetrics({
    this.maxDrawdown = 0,
    this.peakDate,
    this.troughDate,
    this.currentDrawdown = 0,
    this.dailyVolatility = 0,
    this.annualisedVolatility = 0,
    this.bestDay = 0,
    this.worstDay = 0,
    this.observations = 0,
  });

  static const empty = RiskMetrics();

  /// Below this the numbers are too thin to present as fact.
  bool get isReliable => observations >= 20;

  bool get hasData => observations > 0;
}

/// Daily returns with contributions and withdrawals removed.
///
/// The naive `(value − previous) / previous` counts a deposit as a gain: on a
/// portfolio built by DCA that turns every purchase into a spike and makes
/// volatility and drawdown meaningless. Subtracting the change in capital
/// engaged leaves only what the market did.
///
/// Contributions are treated as arriving at the end of the day, so the day's
/// move is measured against the balance that actually rode it. At daily
/// granularity the alternative — assuming money lands at the open — differs
/// only in the second decimal, and this way a same-day deposit can never
/// dilute the return it did not participate in.
List<double> dailyReturns(List<ValueSnapshot> points) {
  if (points.length < 2) return const [];

  final ordered = [...points]..sort((a, b) => a.date.compareTo(b.date));
  final out = <double>[];

  for (var i = 1; i < ordered.length; i++) {
    final prev = ordered[i - 1];
    final curr = ordered[i];
    if (prev.value <= 0) continue;

    final contribution = curr.invested - prev.invested;
    final marketMove = curr.value - prev.value - contribution;
    out.add(marketMove / prev.value);
  }

  return out;
}

/// Growth of one unit, compounding the contribution-free daily returns.
///
/// Drawdown has to be measured on this rather than on raw value: paying more
/// money in would otherwise look like a recovery, hiding the fall it was
/// paid into.
List<double> timeWeightedIndex(List<ValueSnapshot> points) {
  final returns = dailyReturns(points);
  if (returns.isEmpty) return const [];

  final index = <double>[1.0];
  for (final r in returns) {
    // A return of -100% or worse would zero the index permanently; clamp just
    // above so one bad reading cannot erase the whole history.
    final safe = r <= -0.9999 ? -0.9999 : r;
    index.add(index.last * (1 + safe));
  }
  return index;
}

RiskMetrics computeRiskMetrics(List<ValueSnapshot> points) {
  final returns = dailyReturns(points);
  if (returns.isEmpty) return RiskMetrics.empty;

  final ordered = [...points]..sort((a, b) => a.date.compareTo(b.date));
  final index = timeWeightedIndex(points);

  // ── Drawdown, walked forward against the running peak ─────────────────────
  var peak = index.first;
  var peakAt = 0;
  var worstFall = 0.0;
  var worstPeakAt = 0;
  var worstTroughAt = 0;

  for (var i = 1; i < index.length; i++) {
    if (index[i] > peak) {
      peak = index[i];
      peakAt = i;
      continue;
    }
    final fall = (peak - index[i]) / peak;
    if (fall > worstFall) {
      worstFall = fall;
      worstPeakAt = peakAt;
      worstTroughAt = i;
    }
  }

  final allTimePeak = index.reduce(math.max);
  final current = index.last;
  final currentFall =
      allTimePeak > 0 ? (allTimePeak - current) / allTimePeak : 0.0;

  // ── Dispersion ────────────────────────────────────────────────────────────
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance = returns.length < 2
      ? 0.0
      : returns.fold<double>(
              0, (s, r) => s + (r - mean) * (r - mean)) /
          (returns.length - 1);
  final daily = math.sqrt(variance);

  // Index positions map back to snapshots offset by one: index[0] is the day
  // before the first return.
  DateTime? dateAt(int i) =>
      i >= 0 && i < ordered.length ? ordered[i].date : null;

  return RiskMetrics(
    maxDrawdown: worstFall,
    peakDate: worstFall > 0 ? dateAt(worstPeakAt) : null,
    troughDate: worstFall > 0 ? dateAt(worstTroughAt) : null,
    currentDrawdown: currentFall,
    dailyVolatility: daily,
    // 365 rather than 252: crypto does not close at the weekend.
    annualisedVolatility: daily * math.sqrt(365),
    bestDay: returns.reduce(math.max),
    worstDay: returns.reduce(math.min),
    observations: returns.length,
  );
}
