import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/crypto_repository.dart';
import '../datasources/local/crypto_local_datasource.dart';
import '../datasources/remote/crypto_remote_datasource.dart';

class CryptoRepositoryImpl implements CryptoRepository {
  final CryptoLocalDatasource localDatasource;
  final CryptoRemoteDatasource remoteDatasource;

  CryptoRepositoryImpl({required this.localDatasource, required this.remoteDatasource});

  @override
  Future<List<CryptoEntity>> getPortfolio() async {
    final cryptoModels = await localDatasource.getCryptos();
    if (cryptoModels.isEmpty) return [];

    final coinIds = cryptoModels.map((c) => c.coinId).toList();

    Map<String, double> prices = {};
    Map<String, double> changes = {};

    try {
      final response = await remoteDatasource.getMultiplePrices(coinIds);
      prices = response;
    } catch (_) {}

    final entities = <CryptoEntity>[];
    for (final model in cryptoModels) {
      final txModels = await localDatasource.getTransactionsForCrypto(model.id);
      final transactions = txModels.map((t) => t.toEntity()).toList();
      entities.add(model.toEntity(
        transactions: transactions,
        currentPrice: prices[model.coinId] ?? 0.0,
        priceChangePercent24h: changes[model.coinId] ?? 0.0,
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

    return model.toEntity(
      transactions: transactions,
      currentPrice: price,
    );
  }

  @override
  Future<void> addCrypto(CryptoEntity crypto) => localDatasource.saveCrypto(crypto);

  @override
  Future<void> deleteCrypto(String cryptoId) => localDatasource.deleteCrypto(cryptoId);

  @override
  Future<void> addTransaction(TransactionEntity transaction) =>
      localDatasource.saveTransaction(transaction);

  @override
  Future<void> deleteTransaction(String transactionId) =>
      localDatasource.deleteTransaction(transactionId);

  @override
  Future<double> getCryptoPrice(String coinId) => remoteDatasource.getCryptoPrice(coinId);

  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) =>
      remoteDatasource.searchCoins(query);

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) =>
      remoteDatasource.getCoinDetails(coinId);
}
