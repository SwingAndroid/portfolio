import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/price_point.dart';
import '../../domain/repositories/crypto_repository.dart';
import '../datasources/local/crypto_local_datasource.dart';
import '../datasources/remote/crypto_remote_datasource.dart';
import '../datasources/cloud/supabase_datasource.dart';

class CryptoRepositoryImpl implements CryptoRepository {
  final CryptoLocalDatasource localDatasource;
  final CryptoRemoteDatasource remoteDatasource;
  final SupabaseDataSource? cloudDatasource;

  CryptoRepositoryImpl({
    required this.localDatasource,
    required this.remoteDatasource,
    this.cloudDatasource,
  });

  @override
  Future<List<CryptoEntity>> getPortfolio() async {
    final cryptoModels = await localDatasource.getCryptos();
    if (cryptoModels.isEmpty) return [];

    final coinIds = cryptoModels.map((c) => c.coinId).toList();
    Map<String, double> prices = {};

    try {
      prices = await remoteDatasource.getMultiplePrices(coinIds);
    } catch (_) {}

    final entities = <CryptoEntity>[];
    for (final model in cryptoModels) {
      final txModels = await localDatasource.getTransactionsForCrypto(model.id);
      final transactions = txModels.map((t) => t.toEntity()).toList();
      entities.add(model.toEntity(
        transactions: transactions,
        currentPrice: prices[model.coinId] ?? 0.0,
        priceChangePercent24h: 0.0,
      ));
    }
    return entities;
  }

  @override
  Future<CryptoEntity?> getCryptoById(String id) async {
    final cryptoModels = await localDatasource.getCryptos();
    final model = cryptoModels.where((c) => c.id == id).firstOrNull;
    if (model == null) return null;

    final txModels = await localDatasource.getTransactionsForCrypto(id);
    final transactions = txModels.map((t) => t.toEntity()).toList();
    final price = await remoteDatasource.getCryptoPrice(model.coinId);

    return model.toEntity(transactions: transactions, currentPrice: price);
  }

  @override
  Future<void> addCrypto(CryptoEntity crypto) async {
    await localDatasource.saveCrypto(crypto);
    try {
      await cloudDatasource?.upsertCrypto(crypto);
    } catch (_) {}
  }

  @override
  Future<void> deleteCrypto(String cryptoId) async {
    await localDatasource.deleteCrypto(cryptoId);
    try {
      await cloudDatasource?.deleteCrypto(cryptoId);
    } catch (_) {}
  }

  @override
  Future<void> addTransaction(TransactionEntity transaction) async {
    await localDatasource.saveTransaction(transaction);
    try {
      await cloudDatasource?.upsertTransaction(transaction);
    } catch (_) {}
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await localDatasource.deleteTransaction(transactionId);
    try {
      await cloudDatasource?.deleteTransaction(transactionId);
    } catch (_) {}
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
}
