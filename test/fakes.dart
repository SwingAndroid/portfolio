import 'package:crypto_portfolio/data/datasources/cloud/supabase_datasource.dart';
import 'package:crypto_portfolio/data/datasources/local/crypto_local_datasource.dart';
import 'package:crypto_portfolio/data/datasources/remote/crypto_remote_datasource.dart';
import 'package:crypto_portfolio/data/models/crypto_model.dart';
import 'package:crypto_portfolio/data/models/transaction_model.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/price_quote.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

/// Shared in-memory doubles. The cloud fake enforces the same foreign-key rule
/// as Postgres, so a wrong write order fails the test rather than passing.

class MemLocal implements CryptoLocalDatasource {
  final Map<String, CryptoModel> cryptos = {};
  final Map<String, TransactionModel> txs = {};
  final Map<String, String> tombstones = {};
  String? owner;

  @override
  Future<List<CryptoModel>> getCryptos() async => cryptos.values.toList();

  @override
  Future<void> saveCrypto(CryptoEntity c) async =>
      cryptos[c.id] = CryptoModel.fromEntity(c);

  @override
  Future<void> deleteCrypto(String id) async {
    cryptos.remove(id);
    txs.removeWhere((_, t) => t.cryptoId == id);
  }

  @override
  Future<List<TransactionModel>> getTransactionsForCrypto(String id) async =>
      txs.values.where((t) => t.cryptoId == id).toList();

  @override
  Future<List<TransactionModel>> getAllTransactions() async =>
      txs.values.toList();

  @override
  Future<void> saveTransaction(TransactionEntity t) async =>
      txs[t.id] = TransactionModel.fromEntity(t);

  @override
  Future<void> deleteTransaction(String id) async => txs.remove(id);

  @override
  Future<void> recordPendingDelete(String id, String kind) async =>
      tombstones[id] = kind;

  @override
  Future<Map<String, String>> getPendingDeletes() async => Map.of(tombstones);

  @override
  Future<void> clearPendingDelete(String id) async => tombstones.remove(id);

  @override
  Future<String?> getOwnerUserId() async => owner;

  @override
  Future<void> setOwnerUserId(String userId) async => owner = userId;

  @override
  Future<void> clearOwnerUserId() async => owner = null;

  bool firstSyncDone = false;

  @override
  Future<bool> isFirstSyncDone() async => firstSyncDone;

  @override
  Future<void> markFirstSyncDone() async => firstSyncDone = true;
}

class OfflineRemote implements CryptoRemoteDatasource {
  @override
  Future<Map<String, PriceQuote>> getMultiplePrices(List<String> ids) async => {};
  @override
  Future<double> getCryptoPrice(String coinId) async => 0.0;
  @override
  Future<List<Map<String, dynamic>>> searchCoins(String q) async => [];
  @override
  Future<Map<String, dynamic>?> getCoinDetails(String id) async => null;
  @override
  Future<List<PricePoint>> getMarketChart(String id, {int days = 90}) async =>
      [];
  @override
  Future<String?> resolveCoinId(
          {required String symbol, required String name}) async =>
      null;
  @override
  Future<List<String>> getCoinCategories(String id) async => const [];
}

class FakeCloud implements SupabaseDataSource {
  FakeCloud({this.offline = false});
  bool offline;

  final Map<String, Map<String, dynamic>> cryptos = {};
  final Map<String, Map<String, dynamic>> transactions = {};

  /// Order of operations, so foreign-key ordering can be asserted.
  final List<String> calls = [];
  final List<int> batchSizes = [];

  void guard() {
    if (offline) throw Exception('SocketException: no connection');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCryptos() async {
    guard();
    return cryptos.values.toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    guard();
    return transactions.values.toList();
  }

  @override
  Future<void> upsertCrypto(CryptoEntity c) async {
    guard();
    calls.add('upsertCrypto');
    cryptos[c.id] = {
      'id': c.id,
      'coin_id': c.coinId,
      'name': c.name,
      'symbol': c.symbol,
      'image_url': c.imageUrl,
    };
  }

  @override
  Future<void> upsertCryptos(List<CryptoEntity> list) async {
    guard();
    if (list.isEmpty) return;
    calls.add('upsertCryptos');
    batchSizes.add(list.length);
    for (final c in list) {
      await putCryptoRow(c);
    }
  }

  Future<void> putCryptoRow(CryptoEntity c) async {
    cryptos[c.id] = {
      'id': c.id,
      'coin_id': c.coinId,
      'name': c.name,
      'symbol': c.symbol,
      'image_url': c.imageUrl,
    };
  }

  @override
  Future<void> upsertTransaction(TransactionEntity t) async {
    guard();
    calls.add('upsertTransaction');
    putTxRow(t);
  }

  @override
  Future<void> upsertTransactions(List<TransactionEntity> list) async {
    guard();
    if (list.isEmpty) return;
    calls.add('upsertTransactions');
    batchSizes.add(list.length);
    // A transaction must never be written before the coin it references.
    for (final t in list) {
      if (!cryptos.containsKey(t.cryptoId)) {
        throw Exception('FK violation: crypto ${t.cryptoId} not in cloud');
      }
      putTxRow(t);
    }
  }

  void putTxRow(TransactionEntity t) {
    transactions[t.id] = {
      'id': t.id,
      'crypto_id': t.cryptoId,
      'type': t.type.name,
      'quantity': t.quantity,
      'price_per_coin': t.pricePerCoin,
      'date': t.date.toUtc().toIso8601String(),
      'note': t.note,
    };
  }

  @override
  Future<void> deleteCrypto(String id) async {
    guard();
    calls.add('deleteCrypto');
    cryptos.remove(id);
    transactions.removeWhere((_, t) => t['crypto_id'] == id);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    guard();
    calls.add('deleteTransaction');
    transactions.remove(id);
  }

  @override
  Future<void> deleteAllUserData() async => guard();
}

