import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';

abstract class SupabaseDataSource {
  Future<List<Map<String, dynamic>>> fetchCryptos();
  Future<List<Map<String, dynamic>>> fetchTransactions();
  Future<void> upsertCrypto(CryptoEntity crypto);
  Future<void> deleteCrypto(String cryptoId);
  Future<void> upsertTransaction(TransactionEntity transaction);
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

  @override
  Future<void> upsertCrypto(CryptoEntity crypto) async {
    await _client.from('cryptos').upsert({
      'id': crypto.id,
      'user_id': _userId,
      'coin_id': crypto.coinId,
      'name': crypto.name,
      'symbol': crypto.symbol,
      'image_url': crypto.imageUrl,
    });
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
    await _client.from('transactions').upsert({
      'id': transaction.id,
      'user_id': _userId,
      'crypto_id': transaction.cryptoId,
      'type': transaction.type.name,
      'quantity': transaction.quantity,
      'price_per_coin': transaction.pricePerCoin,
      'date': transaction.date.toUtc().toIso8601String(),
      'note': transaction.note,
    });
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
