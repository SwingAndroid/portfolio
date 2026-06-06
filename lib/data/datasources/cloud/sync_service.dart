import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../local/crypto_local_datasource.dart';
import 'supabase_datasource.dart';

class SyncService {
  final SupabaseDataSource cloudDataSource;
  final CryptoLocalDatasource localDataSource;

  SyncService({required this.cloudDataSource, required this.localDataSource});

  /// Pull all data from Supabase and store in Hive.
  /// Called once after login.
  Future<void> pullFromCloud() async {
    try {
      final cloudCryptos = await cloudDataSource.fetchCryptos();
      final cloudTransactions = await cloudDataSource.fetchTransactions();

      for (final c in cloudCryptos) {
        final entity = CryptoEntity(
          id: c['id'] as String,
          coinId: c['coin_id'] as String,
          name: c['name'] as String,
          symbol: c['symbol'] as String,
          imageUrl: c['image_url'] as String?,
          transactions: const [],
        );
        await localDataSource.saveCrypto(entity);
      }

      for (final t in cloudTransactions) {
        final entity = TransactionEntity(
          id: t['id'] as String,
          cryptoId: t['crypto_id'] as String,
          type: t['type'] == 'buy' ? TransactionType.buy : TransactionType.sell,
          quantity: (t['quantity'] as num).toDouble(),
          pricePerCoin: (t['price_per_coin'] as num).toDouble(),
          date: DateTime.parse(t['date'] as String).toLocal(),
          note: t['note'] as String?,
        );
        await localDataSource.saveTransaction(entity);
      }
    } catch (e) {
      // Silently fail — local data is still usable offline
    }
  }

  /// Clear all local Hive data (called on logout).
  Future<void> clearLocal() async {
    final cryptos = await localDataSource.getCryptos();
    for (final c in cryptos) {
      await localDataSource.deleteCrypto(c.id);
    }
  }
}
