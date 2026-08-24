import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';

abstract class SupabaseDataSource {
  Future<List<Map<String, dynamic>>> fetchCryptos();
  Future<List<Map<String, dynamic>>> fetchTransactions();
  Future<void> upsertCrypto(CryptoEntity crypto);
  Future<void> upsertCryptos(List<CryptoEntity> cryptos);
  Future<void> deleteCrypto(String cryptoId);
  Future<void> upsertTransaction(TransactionEntity transaction);
  Future<void> upsertTransactions(List<TransactionEntity> transactions);
  Future<void> deleteTransaction(String transactionId);
  Future<void> deleteAllUserData();
}

class SupabaseDataSourceImpl implements SupabaseDataSource {
  final SupabaseClient _client;

  SupabaseDataSourceImpl(this._client);

  String get _userId {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('User not authenticated');
    return uid;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCryptos() async {
    final response = await _client
        .from('cryptos')
        .select()
        .eq('user_id', _userId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response as List);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    final response = await _client
        .from('transactions')
        .select()
        .eq('user_id', _userId)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Map<String, dynamic> _cryptoRow(CryptoEntity c, String uid) => {
        'id': c.id,
        'user_id': uid,
        'coin_id': c.coinId,
        'name': c.name,
        'symbol': c.symbol,
        'image_url': c.imageUrl,
      };

  Map<String, dynamic> _transactionRow(TransactionEntity t, String uid) => {
        'id': t.id,
        'user_id': uid,
        'crypto_id': t.cryptoId,
        'type': t.type.name,
        'quantity': t.quantity,
        'price_per_coin': t.pricePerCoin,
        'date': t.date.toUtc().toIso8601String(),
        'note': t.note,
        // Null rather than 0 so an unrecorded fee stays distinguishable from
        // a genuinely free transaction.
        'fee': t.fee == 0 ? null : t.fee,
      };

  @override
  Future<void> upsertCrypto(CryptoEntity crypto) async {
    await _client.from('cryptos').upsert(_cryptoRow(crypto, _userId));
  }

  @override
  Future<void> upsertCryptos(List<CryptoEntity> cryptos) async {
    if (cryptos.isEmpty) return;
    final uid = _userId;
    await _client
        .from('cryptos')
        .upsert([for (final c in cryptos) _cryptoRow(c, uid)]);
  }

  @override
  Future<void> deleteCrypto(String cryptoId) async {
    await _client
        .from('cryptos')
        .delete()
        .eq('id', cryptoId)
        .eq('user_id', _userId);
  }

  @override
  Future<void> upsertTransaction(TransactionEntity transaction) async {
    await _client
        .from('transactions')
        .upsert(_transactionRow(transaction, _userId));
  }

  @override
  Future<void> upsertTransactions(List<TransactionEntity> transactions) async {
    if (transactions.isEmpty) return;
    final uid = _userId;
    await _client
        .from('transactions')
        .upsert([for (final t in transactions) _transactionRow(t, uid)]);
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await _client
        .from('transactions')
        .delete()
        .eq('id', transactionId)
        .eq('user_id', _userId);
  }

  @override
  Future<void> deleteAllUserData() async {
    await _client.from('cryptos').delete().eq('user_id', _userId);
  }
}
