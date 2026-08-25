import '../entities/crypto_entity.dart';
import '../entities/transaction_entity.dart';
import '../entities/price_point.dart';

abstract class CryptoRepository {
  Future<List<CryptoEntity>> getPortfolio();
  Future<CryptoEntity?> getCryptoById(String id);
  Future<void> addCrypto(CryptoEntity crypto);
  Future<void> deleteCrypto(String cryptoId);
  Future<void> addTransaction(TransactionEntity transaction);
  Future<void> deleteTransaction(String transactionId);
  Future<double> getCryptoPrice(String coinId);
  Future<List<Map<String, dynamic>>> searchCoins(String query);
  Future<Map<String, dynamic>?> getCoinDetails(String coinId);
  Future<List<PricePoint>> getMarketChart(String coinId, {int days});

  /// Looks up the current CoinGecko id for a coin whose stored id no longer
  /// resolves. Returns null when no confident match is found.
  Future<String?> resolveCoinId({required String symbol, required String name});

  /// Persists a corrected [newCoinId] for the given portfolio entry, locally
  /// and in the cloud.
  Future<void> updateCoinId(String cryptoId, String newCoinId);

  /// Sector labels for a coin.
  Future<List<String>> getCoinCategories(String coinId);
}
