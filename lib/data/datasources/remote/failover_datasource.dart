import '../../../core/errors/exceptions.dart';
import '../../../domain/entities/price_point.dart';
import '../../../domain/entities/price_quote.dart';
import 'crypto_remote_datasource.dart';

/// Tries the primary source, then the backup.
///
/// CoinGecko allows 30 requests a minute for the whole device, shared between
/// the portfolio, the value chart and every coin page — enough to run out
/// mid-session. CoinMarketCap allows 50 a minute on a separate budget, and the
/// two agree on price to within a rounding error.
///
/// The backup is only consulted for failures it could actually fix. A coin
/// CoinGecko has never heard of will not appear at CoinMarketCap either, so
/// [CoinNotFoundException] passes straight through rather than spending a
/// second request to be told the same thing.
class FailoverRemoteDatasource implements CryptoRemoteDatasource {
  final CryptoRemoteDatasource primary;
  final CryptoRemoteDatasource? backup;

  /// Records which source answered, for the sync banner and for diagnosis.
  final void Function(bool usedBackup)? onServed;

  FailoverRemoteDatasource({
    required this.primary,
    this.backup,
    this.onServed,
  });

  Future<T> _attempt<T>(
    Future<T> Function(CryptoRemoteDatasource source) call,
  ) async {
    try {
      final result = await call(primary);
      onServed?.call(false);
      return result;
    } on CoinNotFoundException {
      rethrow;
    } catch (primaryFailure) {
      final fallback = backup;
      if (fallback == null) rethrow;
      try {
        final result = await call(fallback);
        onServed?.call(true);
        return result;
      } on CoinNotFoundException {
        rethrow;
      } catch (_) {
        // Both refused. The primary's reason is the more useful one to report,
        // since the backup may simply not mirror this call at all.
        throw primaryFailure;
      }
    }
  }

  @override
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> coinIds) =>
      _attempt((s) => s.getMultiplePrices(coinIds));

  @override
  Future<double> getCryptoPrice(String coinId) =>
      _attempt((s) => s.getCryptoPrice(coinId));

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) =>
      _attempt((s) => s.getMarketChart(coinId, days: days));

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) =>
      _attempt((s) => s.getCoinDetails(coinId));

  @override
  Future<List<String>> getCoinCategories(String coinId) =>
      _attempt((s) => s.getCoinCategories(coinId));

  // Search and id repair only make sense against CoinGecko's own catalogue, so
  // they never fail over.

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) =>
      primary.searchCoins(query);

  @override
  Future<String?> resolveCoinId({
    required String symbol,
    required String name,
  }) =>
      primary.resolveCoinId(symbol: symbol, name: name);
}
