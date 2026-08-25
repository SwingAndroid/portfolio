import 'dart:math' as math;

import '../entities/price_point.dart';

/// One position's daily returns and its share of the portfolio.
class CoinSeries {
  final String coinId;
  final String symbol;

  /// Share of portfolio value, 0..1.
  final double weight;

  final List<double> returns;

  const CoinSeries({
    required this.coinId,
    required this.symbol,
    required this.weight,
    required this.returns,
  });
}

class CorrelationPair {
  final String a;
  final String b;
  final double value;

  const CorrelationPair(this.a, this.b, this.value);
}

/// How much the portfolio's spread of holdings actually reduces its swings.
///
/// A donut with eight slices says nothing about whether those eight move
/// together. Holding several names that rise and fall in step is one position
/// wearing several labels, and only correlation shows it.
class DiversificationReport {
  final List<CoinSeries> coins;

  /// Symbol → symbol → correlation of daily returns.
  final Map<String, Map<String, double>> matrix;

  final double averageCorrelation;
  final CorrelationPair? strongest;
  final CorrelationPair? weakest;

  /// Annualised standard deviation of the blended portfolio.
  final double portfolioVolatility;

  /// What the volatility would be with no offsetting at all — the weighted
  /// average of each holding's own volatility.
  final double weightedAverageVolatility;

  final int observations;

  const DiversificationReport({
    required this.coins,
    required this.matrix,
    required this.averageCorrelation,
    required this.portfolioVolatility,
    required this.weightedAverageVolatility,
    required this.observations,
    this.strongest,
    this.weakest,
  });

  static const empty = DiversificationReport(
    coins: [],
    matrix: {},
    averageCorrelation: 0,
    portfolioVolatility: 0,
    weightedAverageVolatility: 0,
    observations: 0,
  );

  /// Fraction of volatility the mix removes, 0..1.
  ///
  /// Zero means the holdings move as one and the spread buys nothing.
  double get benefit {
    if (weightedAverageVolatility <= 0) return 0;
    final reduction = 1 - portfolioVolatility / weightedAverageVolatility;
    return reduction < 0 ? 0 : reduction;
  }

  bool get hasData => coins.length >= 2 && observations > 1;

  /// Below this the figures are indicative rather than solid.
  bool get isReliable => observations >= 60;
}

/// Daily returns from a price series, oldest first.
List<double> returnsFromPrices(List<PricePoint> points) {
  if (points.length < 2) return const [];
  final ordered = [...points]..sort((a, b) => a.time.compareTo(b.time));
  final out = <double>[];
  for (var i = 1; i < ordered.length; i++) {
    final prev = ordered[i - 1].price;
    if (prev <= 0) continue;
    out.add((ordered[i].price - prev) / prev);
  }
  return out;
}

double _mean(List<double> x) =>
    x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;

double _stdDev(List<double> x) {
  if (x.length < 2) return 0;
  final m = _mean(x);
  final variance =
      x.fold<double>(0, (s, v) => s + (v - m) * (v - m)) / (x.length - 1);
  return math.sqrt(variance);
}

/// Pearson correlation. Returns 0 when either series never moves, since an
/// unchanging series has no relationship to express.
double correlation(List<double> a, List<double> b) {
  final n = math.min(a.length, b.length);
  if (n < 2) return 0;
  final x = a.sublist(a.length - n);
  final y = b.sublist(b.length - n);

  final mx = _mean(x);
  final my = _mean(y);
  var num = 0.0, dx = 0.0, dy = 0.0;
  for (var i = 0; i < n; i++) {
    final ax = x[i] - mx;
    final by = y[i] - my;
    num += ax * by;
    dx += ax * ax;
    dy += by * by;
  }
  if (dx == 0 || dy == 0) return 0;
  return num / math.sqrt(dx * dy);
}

/// 365 rather than 252: crypto does not close at the weekend.
const double _tradingDaysPerYear = 365;

DiversificationReport buildDiversificationReport(List<CoinSeries> coins) {
  final usable = coins.where((c) => c.returns.length > 1).toList();
  if (usable.length < 2) return DiversificationReport.empty;

  // Every series is compared over the same window, so one coin with a short
  // history cannot silently widen another's sample.
  final window =
      usable.map((c) => c.returns.length).reduce(math.min);
  final trimmed = [
    for (final c in usable)
      CoinSeries(
        coinId: c.coinId,
        symbol: c.symbol,
        weight: c.weight,
        returns: c.returns.sublist(c.returns.length - window),
      )
  ];

  final matrix = <String, Map<String, double>>{};
  final pairs = <CorrelationPair>[];
  for (final a in trimmed) {
    matrix[a.symbol] = {};
    for (final b in trimmed) {
      final r = a.symbol == b.symbol ? 1.0 : correlation(a.returns, b.returns);
      matrix[a.symbol]![b.symbol] = r;
    }
  }
  for (var i = 0; i < trimmed.length; i++) {
    for (var j = i + 1; j < trimmed.length; j++) {
      pairs.add(CorrelationPair(
        trimmed[i].symbol,
        trimmed[j].symbol,
        matrix[trimmed[i].symbol]![trimmed[j].symbol]!,
      ));
    }
  }
  pairs.sort((a, b) => a.value.compareTo(b.value));

  // Blend the series by weight to get what the portfolio actually did.
  final blended = <double>[];
  for (var i = 0; i < window; i++) {
    blended.add(
      trimmed.fold<double>(0, (s, c) => s + c.weight * c.returns[i]),
    );
  }

  final portfolioVol = _stdDev(blended) * math.sqrt(_tradingDaysPerYear);
  final weightedVol = trimmed.fold<double>(
    0,
    (s, c) => s + c.weight * _stdDev(c.returns) * math.sqrt(_tradingDaysPerYear),
  );

  return DiversificationReport(
    coins: trimmed,
    matrix: matrix,
    averageCorrelation:
        pairs.isEmpty ? 0 : pairs.fold<double>(0, (s, p) => s + p.value) / pairs.length,
    strongest: pairs.isEmpty ? null : pairs.last,
    weakest: pairs.isEmpty ? null : pairs.first,
    portfolioVolatility: portfolioVol,
    weightedAverageVolatility: weightedVol,
    observations: window,
  );
}

// ── Sectors ──────────────────────────────────────────────────────────────────

class SectorWeight {
  final String sector;

  /// Share of portfolio value, 0..1.
  final double weight;

  final List<String> symbols;

  const SectorWeight({
    required this.sector,
    required this.weight,
    required this.symbols,
  });
}

/// Category labels that describe a listing rather than what a coin does.
///
/// CoinGecko mixes genuine sectors with index memberships and exchange
/// listings — "GMCI Index", "Coinbase 50 Index", "FTX Holdings". Left in they
/// dominate the ranking and say nothing about concentration.
const List<String> _noiseMarkers = [
  'index',
  'portfolio',
  'holdings',
  'listed',
  'ventures',
  'capital',
  'launchpad',
];

bool isMeaningfulSector(String category) {
  final lower = category.toLowerCase();
  return !_noiseMarkers.any(lower.contains);
}

/// Portfolio weight per sector, heaviest first.
///
/// A coin belongs to several sectors at once, so these deliberately do not sum
/// to 100%: each line answers "how much of the book touches this", not "how is
/// it split".
List<SectorWeight> sectorAllocation({
  required Map<String, List<String>> categoriesByCoinId,
  required Map<String, double> valueByCoinId,
  required Map<String, String> symbolByCoinId,
  int limit = 8,
}) {
  final total = valueByCoinId.values.fold<double>(0, (s, v) => s + v);
  if (total <= 0) return const [];

  final bySector = <String, List<String>>{};
  final weights = <String, double>{};

  for (final entry in categoriesByCoinId.entries) {
    final value = valueByCoinId[entry.key] ?? 0;
    if (value <= 0) continue;
    for (final category in entry.value) {
      if (!isMeaningfulSector(category)) continue;
      bySector.putIfAbsent(category, () => []);
      final symbol = symbolByCoinId[entry.key] ?? entry.key;
      if (!bySector[category]!.contains(symbol)) {
        bySector[category]!.add(symbol);
      }
      weights[category] = (weights[category] ?? 0) + value;
    }
  }

  final out = [
    for (final entry in weights.entries)
      SectorWeight(
        sector: entry.key,
        weight: entry.value / total,
        symbols: bySector[entry.key]!..sort(),
      )
  ]..sort((a, b) => b.weight.compareTo(a.weight));

  return out.take(limit).toList();
}
