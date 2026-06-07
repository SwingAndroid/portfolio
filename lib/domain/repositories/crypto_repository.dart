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
}
