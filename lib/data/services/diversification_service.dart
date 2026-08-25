import '../../domain/analytics/diversification.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/repositories/crypto_repository.dart';
import '../datasources/local/category_store.dart';

/// Everything the diversification card needs, plus what could not be gathered.
class DiversificationResult {
  final DiversificationReport report;
  final List<SectorWeight> sectors;

  /// Non-null when part of the data could not be fetched; what is present is
  /// still shown rather than blanking the card.
  final Object? error;

  const DiversificationResult({
    required this.report,
    required this.sectors,
    this.error,
  });

  static const empty =
      DiversificationResult(report: DiversificationReport.empty, sectors: []);

  bool get hasAnything => report.hasData || sectors.isNotEmpty;
}

/// Gathers price history and sector labels, then measures how much the mix
/// actually offsets itself.
class DiversificationService {
  final CryptoRepository repository;
  final CategoryStore categories;

  DiversificationService({required this.repository, required this.categories});

  /// A year of daily prices: long enough for correlation to mean something,
  /// and the ceiling the free CoinGecko tier serves anyway.
  static const int windowDays = 365;

  /// Spacing between the category calls, which are only made on a cache miss.
  /// The device shares 30 requests a minute across everything.
  static const Duration _spacing = Duration(milliseconds: 300);

  Future<DiversificationResult> load(List<CryptoEntity> cryptos) async {
    final held = cryptos
        .where((c) => c.totalHoldings > 0 && c.currentPrice > 0)
        .toList();
    if (held.length < 2) return DiversificationResult.empty;

    final totalValue =
        held.fold<double>(0, (s, c) => s + c.holdingsValue);
    if (totalValue <= 0) return DiversificationResult.empty;

    Object? failure;

    // ── Returns ─────────────────────────────────────────────────────────────
    final series = <CoinSeries>[];
    for (final crypto in held) {
      try {
        final chart = await repository.getMarketChart(
          crypto.coinId,
          days: windowDays,
        );
        final returns = returnsFromPrices(chart);
        if (returns.length < 2) continue;
        series.add(CoinSeries(
          coinId: crypto.coinId,
          symbol: crypto.symbol,
          weight: crypto.holdingsValue / totalValue,
          returns: returns,
        ));
      } catch (e) {
        // One unreachable coin must not cost the whole picture.
        failure ??= e;
      }
    }

    // ── Sectors ─────────────────────────────────────────────────────────────
    final byCoin = <String, List<String>>{};
    final symbols = <String, String>{};
    final values = <String, double>{};
    var fetchedThisRun = false;

    for (final crypto in held) {
      symbols[crypto.coinId] = crypto.symbol;
      values[crypto.coinId] = crypto.holdingsValue;

      var cached = await categories.get(crypto.coinId);
      if (cached == null) {
        try {
          if (fetchedThisRun) await Future<void>.delayed(_spacing);
          fetchedThisRun = true;
          cached = await repository.getCoinCategories(crypto.coinId);
          await categories.put(crypto.coinId, cached);
        } catch (e) {
          failure ??= e;
          continue;
        }
      }
      byCoin[crypto.coinId] = cached;
    }

    return DiversificationResult(
      report: buildDiversificationReport(series),
      sectors: sectorAllocation(
        categoriesByCoinId: byCoin,
        valueByCoinId: values,
        symbolByCoinId: symbols,
      ),
      error: failure,
    );
  }
}
