import '../../domain/analytics/portfolio_series.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/value_snapshot.dart';
import '../../domain/repositories/crypto_repository.dart';
import '../datasources/local/value_history_store.dart';

/// Result of assembling the value curve, including how much of it is trusted.
class PortfolioHistory {
  final List<ValueSnapshot> points;

  /// Days that had to be rebuilt from market data rather than observed live.
  final int reconstructedDays;

  /// Non-null when backfill could not run; [points] may then be sparse.
  final Object? backfillError;

  const PortfolioHistory({
    required this.points,
    this.reconstructedDays = 0,
    this.backfillError,
  });

  bool get isEmpty => points.isEmpty;
}

/// Assembles the portfolio value curve from what was recorded plus whatever
/// can still be rebuilt.
///
/// CoinGecko caps history at 365 days on every endpoint, so this is a strict
/// division of labour: inside that window a missing day can be reconstructed
/// exactly, because holdings come from local transactions and only prices are
/// remote. Outside it, only the daily snapshot ever knew the value.
class PortfolioHistoryService {
  final CryptoRepository repository;
  final ValueHistoryStore store;

  PortfolioHistoryService({required this.repository, required this.store});

  /// Hard ceiling of the free CoinGecko tier. Verified against market_chart,
  /// market_chart/range and /coins/{id}/history — all refuse beyond this.
  static const int maxReconstructableDays = 365;

  Future<PortfolioHistory> load({
    required List<CryptoEntity> cryptos,
    required int days,
    DateTime? now,
  }) async {
    final today = _day(now ?? DateTime.now());
    final from = today.subtract(Duration(days: days - 1));

    final recorded = await store.since(from);
    final byDay = {for (final s in recorded) s.key: s};

    // Only days inside the reconstructable window are worth chasing.
    final rebuildFrom = _laterOf(
      from,
      today.subtract(const Duration(days: maxReconstructableDays - 1)),
    );
    final missing = _missingDays(byDay, rebuildFrom, today);

    if (missing.isEmpty || cryptos.isEmpty) {
      return PortfolioHistory(
        points: _withFreshInvested(byDay.values, cryptos, from, today),
      );
    }

    try {
      final index = await _fetchPrices(cryptos, days: maxReconstructableDays);

      final rebuilt = buildDailySeries(
        cryptos: cryptos,
        from: rebuildFrom,
        to: today,
        priceAt: index.priceAt,
      );

      var added = 0;
      for (final point in rebuilt) {
        // A recorded snapshot is a real observation and always wins; a rebuilt
        // one only fills a hole.
        if (byDay.containsKey(point.key)) continue;
        byDay[point.key] = point;
        await store.record(point);
        added++;
      }

      return PortfolioHistory(
        points: _withFreshInvested(byDay.values, cryptos, from, today),
        reconstructedDays: added,
      );
    } catch (e) {
      // Backfill is best-effort: return whatever was genuinely recorded rather
      // than failing the whole curve.
      return PortfolioHistory(
        points: _withFreshInvested(byDay.values, cryptos, from, today),
        backfillError: e,
      );
    }
  }

  Future<DailyPriceIndex> _fetchPrices(
    List<CryptoEntity> cryptos, {
    required int days,
  }) async {
    final index = DailyPriceIndex();
    for (final crypto in cryptos) {
      // Coins no longer held contribute nothing to the value line.
      if (crypto.totalHoldings <= 0) continue;
      final chart = await repository.getMarketChart(crypto.coinId, days: days);
      index.add(
        crypto.coinId,
        chart.map((p) => (time: p.time, price: p.price)),
      );
    }
    return index;
  }

  List<DateTime> _missingDays(
    Map<String, ValueSnapshot> have,
    DateTime from,
    DateTime to,
  ) {
    final out = <DateTime>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      if (!have.containsKey(ValueSnapshot.keyFor(d))) out.add(d);
    }
    return out;
  }

  /// Re-derives the capital-engaged line from current transactions.
  ///
  /// A snapshot records what the portfolio was worth that day, which only the
  /// market could tell us. What had been put in is local arithmetic, so it is
  /// recomputed rather than trusted — otherwise a back-dated transaction would
  /// leave every earlier point wrong forever.
  static List<ValueSnapshot> _withFreshInvested(
    Iterable<ValueSnapshot> input,
    List<CryptoEntity> cryptos,
    DateTime from,
    DateTime to,
  ) {
    if (cryptos.isEmpty) return _sorted(input);
    final invested = investedByDay(cryptos: cryptos, from: from, to: to);
    return _sorted([
      for (final s in input)
        ValueSnapshot(
          date: s.date,
          value: s.value,
          invested: invested[s.key] ?? s.invested,
        )
    ]);
  }

  static List<ValueSnapshot> _sorted(Iterable<ValueSnapshot> input) {
    final out = input.toList()..sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _laterOf(DateTime a, DateTime b) =>
      a.isAfter(b) ? a : b;
}
