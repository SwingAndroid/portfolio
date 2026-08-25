import '../../core/sync/sync_status.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/price_point.dart';
import '../../domain/entities/price_quote.dart';
import '../../domain/repositories/crypto_repository.dart';
import '../datasources/local/crypto_local_datasource.dart';
import '../datasources/remote/crypto_remote_datasource.dart';
import '../datasources/remote/symbol_registry.dart';
import '../datasources/cloud/supabase_datasource.dart';

class CryptoRepositoryImpl implements CryptoRepository {
  final CryptoLocalDatasource localDatasource;
  final CryptoRemoteDatasource remoteDatasource;
  final SupabaseDataSource? cloudDatasource;
  final SyncStatus? syncStatus;

  /// Lets the backup provider translate CoinGecko ids into the tickers it
  /// speaks. Filled from stored coins, which already carry both, so no request
  /// is spent bridging the two id spaces.
  final SymbolRegistry? symbols;

  CryptoRepositoryImpl({
    required this.localDatasource,
    required this.remoteDatasource,
    this.cloudDatasource,
    this.syncStatus,
    this.symbols,
  });

  /// Runs a cloud write without ever failing the user's action — local Hive is
  /// already updated by the time this runs — but reports the outcome instead of
  /// swallowing it. A silent `catch (_) {}` here is what hid 77 days of
  /// unsynced writes.
  Future<void> _cloudWrite(Future<void> Function() write) async {
    final cloud = cloudDatasource;
    if (cloud == null) return;
    try {
      await write();
      syncStatus?.reportSuccess();
    } catch (e) {
      syncStatus?.reportFailure(e);
    }
  }

  @override
  Future<List<CryptoEntity>> getPortfolio() async {
    final cryptoModels = await localDatasource.getCryptos();
    if (cryptoModels.isEmpty) return [];

    symbols?.registerAll({
      for (final c in cryptoModels) c.coinId: c.symbol,
    });

    final coinIds = cryptoModels.map((c) => c.coinId).toList();
    Map<String, PriceQuote> prices = {};

    try {
      prices = await remoteDatasource.getMultiplePrices(coinIds);
    } catch (_) {}

    final entities = <CryptoEntity>[];
    for (final model in cryptoModels) {
      final txModels = await localDatasource.getTransactionsForCrypto(model.id);
      final transactions = txModels.map((t) => t.toEntity()).toList();
      final quote = prices[model.coinId] ?? PriceQuote.zero;
      entities.add(model.toEntity(
        transactions: transactions,
        currentPrice: quote.price,
        priceChangePercent24h: quote.change24h,
      ));
    }
    return entities;
  }

  @override
  Future<CryptoEntity?> getCryptoById(String id) async {
    final cryptoModels = await localDatasource.getCryptos();
    final model = cryptoModels.where((c) => c.id == id).firstOrNull;
    if (model == null) return null;

    symbols?.register(model.coinId, model.symbol);

    final txModels = await localDatasource.getTransactionsForCrypto(id);
    final transactions = txModels.map((t) => t.toEntity()).toList();
    final price = await remoteDatasource.getCryptoPrice(model.coinId);

    return model.toEntity(transactions: transactions, currentPrice: price);
  }

  @override
  Future<void> addCrypto(CryptoEntity crypto) async {
    await localDatasource.saveCrypto(crypto);
    await _cloudWrite(() => cloudDatasource!.upsertCrypto(crypto));
  }

  @override
  Future<void> deleteCrypto(String cryptoId) async {
    await localDatasource.deleteCrypto(cryptoId);
    // Remember the delete up front. If the cloud call succeeds the tombstone is
    // dropped; if it fails it survives, so the next pull cannot resurrect the
    // record.
    await localDatasource.recordPendingDelete(
        cryptoId, PendingDeleteKind.crypto);
    final cloud = cloudDatasource;
    if (cloud == null) return;
    try {
      await cloud.deleteCrypto(cryptoId);
      await localDatasource.clearPendingDelete(cryptoId);
      syncStatus?.reportSuccess();
    } catch (e) {
      syncStatus?.reportFailure(e);
    }
  }

  @override
  Future<void> addTransaction(TransactionEntity transaction) async {
    await localDatasource.saveTransaction(transaction);
    await _cloudWrite(() => cloudDatasource!.upsertTransaction(transaction));
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await localDatasource.deleteTransaction(transactionId);
    await localDatasource.recordPendingDelete(
        transactionId, PendingDeleteKind.transaction);
    final cloud = cloudDatasource;
    if (cloud == null) return;
    try {
      await cloud.deleteTransaction(transactionId);
      await localDatasource.clearPendingDelete(transactionId);
      syncStatus?.reportSuccess();
    } catch (e) {
      syncStatus?.reportFailure(e);
    }
  }

  @override
  Future<double> getCryptoPrice(String coinId) =>
      remoteDatasource.getCryptoPrice(coinId);

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) =>
      remoteDatasource.searchCoins(query);

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) =>
      remoteDatasource.getCoinDetails(coinId);

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) =>
      remoteDatasource.getMarketChart(coinId, days: days);

  @override
  Future<List<String>> getCoinCategories(String coinId) =>
      remoteDatasource.getCoinCategories(coinId);

  @override
  Future<String?> resolveCoinId({
    required String symbol,
    required String name,
  }) =>
      remoteDatasource.resolveCoinId(symbol: symbol, name: name);

  @override
  Future<void> updateCoinId(String cryptoId, String newCoinId) async {
    final models = await localDatasource.getCryptos();
    final model = models.where((c) => c.id == cryptoId).firstOrNull;
    if (model == null) return;

    final updated = model.toEntity().copyWith(coinId: newCoinId);
    await localDatasource.saveCrypto(updated);
    await _cloudWrite(() => cloudDatasource!.upsertCrypto(updated));
  }
}
