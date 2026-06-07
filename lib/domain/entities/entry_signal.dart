/// A single contributing factor to the overall Entry Signal score.
class SignalFactor {
  final String label;
  final String detail;
  final double score; // 0..100 (higher = better moment to add)
  final double weight; // relative importance

  const SignalFactor({
    required this.label,
    required this.detail,
    required this.score,
    required this.weight,
  });
}

enum EntryLevel { strong, good, fair, wait, expensive }

/// DCA "should I add now?" score for a single coin.
///
/// Combines up to three factors, each scored 0..100 where higher means a
/// better moment to buy:
///   * price vs your own average cost (lowering your basis = good)
///   * discount from all-time high (cheaper vs the peak = good)
///   * 30-day price trend (a recent dip = good)
///
/// Only the factors with available data are used; weights are re-normalised
/// so a coin with no market data still gets a score from your cost basis alone.
class EntrySignal {
  final double score; // 0..100
  final List<SignalFactor> factors;

  const EntrySignal(this.score, this.factors);

  bool get hasData => factors.isNotEmpty;

  EntryLevel get level {
    if (score >= 70) return EntryLevel.strong;
    if (score >= 55) return EntryLevel.good;
    if (score >= 45) return EntryLevel.fair;
    if (score >= 30) return EntryLevel.wait;
    return EntryLevel.expensive;
  }

  static double _clamp(double v) => v < 0 ? 0 : (v > 100 ? 100 : v);

  factory EntrySignal.compute({
    required double currentPrice,
    required double avgBuyPrice,
    double? athChangePercent, // negative number, % from ATH
    double? change30d,
  }) {
    final factors = <SignalFactor>[];

    // ── Factor A: price vs your average cost ───────────────────────────────
    if (avgBuyPrice > 0 && currentPrice > 0) {
      // discount > 0 means today is cheaper than your average cost.
      final discount = (avgBuyPrice - currentPrice) / avgBuyPrice * 100;
      final s = _clamp((discount + 20) / 40 * 100); // -20%→0, 0%→50, +20%→100
      factors.add(SignalFactor(
        label: 'vs Your Avg Cost',
        detail: discount >= 0
            ? '${discount.toStringAsFixed(1)}% below your average'
            : '${discount.abs().toStringAsFixed(1)}% above your average',
        score: s,
        weight: 0.45,
      ));
    }

    // ── Factor B: discount from all-time high ──────────────────────────────
    if (athChangePercent != null && athChangePercent < 0) {
      final drawdown = -athChangePercent; // % below ATH
      final s = _clamp(drawdown / 80 * 100); // 0%→0, 80%→100
      factors.add(SignalFactor(
        label: 'Discount from ATH',
        detail: '${drawdown.toStringAsFixed(1)}% below all-time high',
        score: s,
        weight: 0.35,
      ));
    }

    // ── Factor C: 30-day trend ─────────────────────────────────────────────
    if (change30d != null) {
      final s = _clamp((-change30d + 30) / 60 * 100); // +30%→0, 0→50, -30%→100
      factors.add(SignalFactor(
        label: '30-Day Trend',
        detail: change30d <= 0
            ? '${change30d.abs().toStringAsFixed(1)}% down over 30 days'
            : '${change30d.toStringAsFixed(1)}% up over 30 days',
        score: s,
        weight: 0.20,
      ));
    }

    if (factors.isEmpty) return const EntrySignal(0, []);

    final totalWeight = factors.fold(0.0, (s, f) => s + f.weight);
    final weighted =
        factors.fold(0.0, (s, f) => s + f.score * f.weight) / totalWeight;

    return EntrySignal(weighted, factors);
  }
}
