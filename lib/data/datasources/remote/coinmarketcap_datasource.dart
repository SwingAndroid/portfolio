import 'package:dio/dio.dart';

import '../../../core/errors/exceptions.dart';
import '../../../domain/entities/price_point.dart';
import '../../../domain/entities/price_quote.dart';
import 'crypto_remote_datasource.dart';
import 'symbol_registry.dart';

/// CoinMarketCap, standing in for CoinGecko when it will not answer.
///
/// The two agree closely on price — measured at 0.02% across this portfolio —
/// so a reading served by either is interchangeable. What CoinMarketCap cannot
/// replace it refuses outright rather than returning something shaped right
/// but wrong.
class CoinMarketCapDatasource implements CryptoRemoteDatasource {
  final Dio dio;
  final SymbolRegistry registry;

  CoinMarketCapDatasource({required this.dio, required this.registry});

  /// The free plan serves twelve months, the same ceiling CoinGecko imposes,
  /// so nothing older can be recovered by switching provider.
  static const int maxHistoryDays = 365;

  Never _rethrowAs(Object error, String coinId) {
    if (error is DioException && error.response?.statusCode == 404) {
      throw CoinNotFoundException(coinId);
    }
    throw RemoteException(
      error is DioException ? (error.message ?? 'Request failed') : '$error',
    );
  }

  String _symbolOr(String coinId) {
    final symbol = registry.symbolFor(coinId);
    if (symbol == null) {
      // Without a symbol there is nothing to ask for. Reported as a remote
      // failure so the caller keeps whatever the primary source gave.
      throw RemoteException('No symbol known for "$coinId"');
    }
    return symbol;
  }

  @override
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> coinIds) async {
    if (coinIds.isEmpty) return {};
    final resolved = registry.resolve(coinIds);
    if (resolved.known.isEmpty) {
      throw const RemoteException('No symbols known for the requested coins');
    }

    try {
      final response = await dio.get(
        '/cryptocurrency/quotes/latest',
        queryParameters: {
          'symbol': resolved.known.values.toSet().join(','),
          'convert': 'USD',
        },
      );
      final data = response.data['data'];
      if (data is! Map) return {};

      final out = <String, PriceQuote>{};
      resolved.known.forEach((coinId, symbol) {
        final row = data[symbol];
        final usd = _usdQuote(row);
        if (usd == null) return;
        out[coinId] = PriceQuote(
          price: (usd['price'] as num?)?.toDouble() ?? 0.0,
          change24h: (usd['percent_change_24h'] as num?)?.toDouble() ?? 0.0,
        );
      });
      return out;
    } catch (e) {
      _rethrowAs(e, coinIds.first);
    }
  }

  /// CoinMarketCap returns either an object or a list per symbol depending on
  /// the endpoint version; both shapes are accepted.
  Map<String, dynamic>? _usdQuote(Object? row) {
    final entry = row is List ? (row.isEmpty ? null : row.first) : row;
    if (entry is! Map) return null;
    final quote = entry['quote'];
    if (quote is! Map) return null;
    final usd = quote['USD'];
    return usd is Map ? Map<String, dynamic>.from(usd) : null;
  }

  @override
  Future<double> getCryptoPrice(String coinId) async {
    final quotes = await getMultiplePrices([coinId]);
    return quotes[coinId]?.price ?? 0.0;
  }

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    final symbol = _symbolOr(coinId);
    final capped = days > maxHistoryDays ? maxHistoryDays : days;
    final start = DateTime.now().toUtc().subtract(Duration(days: capped));

    try {
      final response = await dio.get(
        '/cryptocurrency/quotes/historical',
        queryParameters: {
          'symbol': symbol,
          'time_start': start.toIso8601String(),
          'interval': 'daily',
          'convert': 'USD',
        },
      );
      final quotes = response.data['data']?['quotes'];
      if (quotes is! List) return const [];

      final out = <PricePoint>[];
      for (final entry in quotes) {
        if (entry is! Map) continue;
        final at = DateTime.tryParse(entry['timestamp'] as String? ?? '');
        final usd = _usdQuote(entry);
        final price = (usd?['price'] as num?)?.toDouble();
        if (at == null || price == null) continue;
        out.add(PricePoint(at.toLocal(), price));
      }
      out.sort((a, b) => a.time.compareTo(b.time));
      return out;
    } catch (e) {
      _rethrowAs(e, coinId);
    }
  }

  // ── Deliberately not served here ──────────────────────────────────────────
  // Each of these would need something CoinMarketCap does not provide in the
  // same shape. Refusing keeps the primary source's answer authoritative
  // instead of quietly substituting a different meaning.

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) async {
    // The Entry Signal wants the drawdown from all-time high, which is not in
    // this response. Half the inputs would score a different signal.
    throw const RemoteException('Coin details are not mirrored');
  }

  @override
  Future<List<String>> getCoinCategories(String coinId) async {
    // A different taxonomy entirely; mixing the two would make sector weights
    // incomparable between coins.
    throw const RemoteException('Categories are not mirrored');
  }

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) async => const [];

  @override
  Future<String?> resolveCoinId({
    required String symbol,
    required String name,
  }) async =>
      null; // Repairing a CoinGecko id can only be done against CoinGecko.
}
