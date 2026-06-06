import 'package:hive_flutter/hive_flutter.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../models/crypto_model.dart';
import '../../models/transaction_model.dart';

abstract class CryptoLocalDatasource {
  Future<List<CryptoModel>> getCryptos();
  Future<void> saveCrypto(CryptoEntity crypto);
  Future<void> deleteCrypto(String cryptoId);
  Future<List<TransactionModel>> getTransactionsForCrypto(String cryptoId);
  Future<void> saveTransaction(TransactionEntity transaction);
  Future<void> deleteTransaction(String transactionId);
}

class CryptoLocalDatasourceImpl implements CryptoLocalDatasource {
  final Box<CryptoModel> cryptoBox;
  final Box<TransactionModel> transactionBox;

  CryptoLocalDatasourceImpl({required this.cryptoBox, required this.transactionBox});

  @override
  Future<List<CryptoModel>> getCryptos() async {
    return cryptoBox.values.toList();
  }

  @override
  Future<void> saveCrypto(CryptoEntity crypto) async {
    await cryptoBox.put(crypto.id, CryptoModel.fromEntity(crypto));
  }

  @override
  Future<void> deleteCrypto(String cryptoId) async {
    await cryptoBox.delete(cryptoId);
    final txToDelete = transactionBox.values
        .where((t) => t.cryptoId == cryptoId)
        .map((t) => t.id)
        .toList();
    for (final id in txToDelete) {
      await transactionBox.delete(id);
    }
  }

  @override
  Future<List<TransactionModel>> getTransactionsForCrypto(String cryptoId) async {
    return transactionBox.values
        .where((t) => t.cryptoId == cryptoId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<void> saveTransaction(TransactionEntity transaction) async {
    await transactionBox.put(transaction.id, TransactionModel.fromEntity(transaction));
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await transactionBox.delete(transactionId);
  }
}
