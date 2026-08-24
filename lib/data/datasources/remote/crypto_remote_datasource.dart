import 'package:dio/dio.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/entities/price_point.dart';

abstract class CryptoRemoteDatasource {
  Future<double> getCryptoPrice(String coinId);
  Future<List<Map<String, dynamic>>> searchCoins(String query);
  Future<Map<String, dynamic>?> getCoinDetails(String coinId);
  Future<Map<String, double>> getMultiplePrices(List<String> coinIds);
  Future<List<PricePoint>> getMarketChart(String coinId, {int days});
  Future<String?> resolveCoinId({required String symbol, required String name});
}

class CryptoRemoteDatasourceImpl implements CryptoRemoteDatasource {
  final Dio dio;

  CryptoRemoteDatasourceImpl({required this.dio});

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
    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': coinId,
        'vs_currencies': 'usd',
      });
      final data = response.data as Map<String, dynamic>;
      return (data[coinId]?['usd'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<Map<String, double>> getMultiplePrices(List<String> coinIds) async {
    if (coinIds.isEmpty) return {};
    try {
      final response = await dio.get('/simple/price', queryParameters: {
        'ids': coinIds.join(','),
        'vs_currencies': 'usd',
        'include_24hr_change': true,
      });
      final data = response.data as Map<String, dynamic>;
      final result = <String, double>{};
      for (final id in coinIds) {
        result[id] = (data[id]?['usd'] as num?)?.toDouble() ?? 0.0;
      }
      return result;
    } catch (_) {
      return {};
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
      return prices.map((p) {
        final pair = p as List;
        return PricePoint(
          DateTime.fromMillisecondsSinceEpoch((pair[0] as num).toInt()),
          (pair[1] as num).toDouble(),
        );
      }).toList();
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
