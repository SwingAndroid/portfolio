import 'package:dio/dio.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/entities/price_point.dart';
import '../../../domain/entities/price_quote.dart';

abstract class CryptoRemoteDatasource {
  Future<double> getCryptoPrice(String coinId);
  Future<List<Map<String, dynamic>>> searchCoins(String query);
  Future<Map<String, dynamic>?> getCoinDetails(String coinId);
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> coinIds);
  Future<List<PricePoint>> getMarketChart(String coinId, {int days});
  Future<String?> resolveCoinId({required String symbol, required String name});

  /// Sector labels for a coin, e.g. "Layer 1 (L1)", "Decentralized Finance".
  Future<List<String>> getCoinCategories(String coinId);
}

/// A value with the moment it was fetched, so staleness can be judged.
class _Cached<T> {
  final T value;
  final DateTime at;
  const _Cached(this.value, this.at);

  bool isFreshAt(DateTime now, Duration ttl) =>
      now.difference(at) < ttl;
}

class CryptoRemoteDatasourceImpl implements CryptoRemoteDatasource {
  final Dio dio;

  CryptoRemoteDatasourceImpl({required this.dio});

  /// CoinGecko allows 30 calls a minute for the whole device, shared between
  /// the portfolio view, the value chart and every coin page. Reusing a quote
  /// for a few minutes is the difference between browsing freely and being
  /// throttled halfway through. `priceCacheDuration` was declared from the
  /// start and never wired up.
  final Map<String, _Cached<PriceQuote>> _quotes = {};
  final Map<String, _Cached<List<PricePoint>>> _charts = {};

  Duration get _ttl => AppConstants.priceCacheDuration;

  /// Translates a Dio error into one of our typed exceptions so callers can
  /// distinguish a renamed/removed coin from a transient network problem.
  Never _rethrowAs(Object error, String coinId) {
    if (error is DioException && error.response?.statusCode == 404) {
      throw CoinNotFoundException(coinId);
    }
    throw RemoteException(
      error is DioException ? (error.message ?? 'Request failed') : '$error',
    );
  }

  // ── Price lookups stay lenient ────────────────────────────────────────────
  // These feed the portfolio list, which must keep rendering even when a
  // single coin misbehaves. A price of 0 is a survivable degradation.

  @override
  Future<double> getCryptoPrice(String coinId) async {
    // The portfolio list fetches every price in one call moments earlier;
    // asking again per coin page was pure waste.
    final cached = _quotes[coinId];
    if (cached != null && cached.isFreshAt(DateTime.now(), _ttl)) {
      return cached.value.price;
    }

    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': coinId,
        'vs_currencies': 'usd',
        'include_24hr_change': true,
      });
      final data = response.data as Map<String, dynamic>;
      final row = data[coinId];
      if (row is! Map) return 0.0;
      final quote = PriceQuote(
        price: (row['usd'] as num?)?.toDouble() ?? 0.0,
        change24h: (row['usd_24h_change'] as num?)?.toDouble() ?? 0.0,
      );
      _quotes[coinId] = _Cached(quote, DateTime.now());
      return quote.price;
    } catch (_) {
      // A stale price beats no price at all.
      return cached?.value.price ?? 0.0;
    }
  }

  @override
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> coinIds) async {
    if (coinIds.isEmpty) return {};

    final now = DateTime.now();
    final fresh = <String, PriceQuote>{};
    final stale = <String>[];
    for (final id in coinIds) {
      final hit = _quotes[id];
      if (hit != null && hit.isFreshAt(now, _ttl)) {
        fresh[id] = hit.value;
      } else {
        stale.add(id);
      }
    }
    if (stale.isEmpty) return fresh;

    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': stale.join(','),
        'vs_currencies': 'usd',
        'include_24hr_change': true,
      });
      final data = response.data as Map<String, dynamic>;
      final fetchedAt = DateTime.now();
      final result = <String, PriceQuote>{...fresh};
      for (final id in stale) {
        final row = data[id];
        if (row is! Map) continue;
        final quote = PriceQuote(
          price: (row['usd'] as num?)?.toDouble() ?? 0.0,
          change24h: (row['usd_24h_change'] as num?)?.toDouble() ?? 0.0,
        );
        _quotes[id] = _Cached(quote, fetchedAt);
        result[id] = quote;
      }
      return result;
    } catch (_) {
      // Serve whatever is cached rather than collapsing every price to zero.
      return {
        ...fresh,
        for (final id in stale)
          if (_quotes[id] != null) id: _quotes[id]!.value,
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) async {
    try {
      final response = await dio.get('/search', queryParameters: {'query': query});
      final coins = (response.data['coins'] as List?) ?? [];
      return coins.take(20).map((c) => Map<String, dynamic>.from(c)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Detail endpoints report failure ───────────────────────────────────────
  // The Entry Signal and Price History cards are built from these. Swallowing
  // errors here made both cards silently disappear with no way to tell why.

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) async {
    try {
      final response = await dio.get('/coins/$coinId', queryParameters: {
        'localization': false,
        'tickers': false,
        'market_data': true,
        'community_data': false,
        'developer_data': false,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      _rethrowAs(e, coinId);
    }
  }

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    // Charts are the heaviest calls; navigating back to a coin within the
    // window should not spend another one.
    final key = '$coinId:$days';
    final cached = _charts[key];
    if (cached != null && cached.isFreshAt(DateTime.now(), _ttl)) {
      return cached.value;
    }

    try {
      // CoinGecko defaults to hourly granularity below a year, which is
      // ~2160 points and 220KB for a 90-day range — far more than a chart a
      // few hundred pixels wide can show, and enough to time out on a slow
      // connection. Daily is ~9KB for the same range.
      final response =
          await dio.get('/coins/$coinId/market_chart', queryParameters: {
        'vs_currency': 'usd',
        'days': days,
        if (days >= 90) 'interval': 'daily',
      });
      final prices = (response.data['prices'] as List?) ?? [];
      final points = prices.map((p) {
        final pair = p as List;
        return PricePoint(
          DateTime.fromMillisecondsSinceEpoch((pair[0] as num).toInt()),
          (pair[1] as num).toDouble(),
        );
      }).toList();
      _charts[key] = _Cached(points, DateTime.now());
      return points;
    } catch (e) {
      _rethrowAs(e, coinId);
    }
  }

  @override
  Future<List<String>> getCoinCategories(String coinId) async {
    // market_data is skipped: this response is only wanted for its labels, and
    // the slimmer payload is kinder to the shared request budget.
    try {
      final response = await dio.get('/coins/$coinId', queryParameters: {
        'localization': false,
        'tickers': false,
        'market_data': false,
        'community_data': false,
        'developer_data': false,
      });
      final raw = response.data['categories'];
      if (raw is! List) return const [];
      return raw.whereType<String>().toList();
    } catch (e) {
      _rethrowAs(e, coinId);
    }
  }

  /// Finds the current CoinGecko id for a coin whose stored id no longer
  /// resolves. Matches on exact symbol first, then falls back to an exact
  /// name match — both case-insensitive.
  @override
  Future<String?> resolveCoinId({
    required String symbol,
    required String name,
  }) async {
    final candidates = await searchCoins(symbol.isNotEmpty ? symbol : name);
    if (candidates.isEmpty) return null;

    final wantSymbol = symbol.toLowerCase();
    final wantName = name.toLowerCase();

    for (final c in candidates) {
      if ((c['symbol'] as String? ?? '').toLowerCase() == wantSymbol) {
        return c['id'] as String?;
      }
    }
    for (final c in candidates) {
      if ((c['name'] as String? ?? '').toLowerCase() == wantName) {
        return c['id'] as String?;
      }
    }
    return null;
  }
}
