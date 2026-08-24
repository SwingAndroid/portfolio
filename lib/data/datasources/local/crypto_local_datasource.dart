import 'package:hive_flutter/hive_flutter.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../models/crypto_model.dart';
import '../../models/transaction_model.dart';

/// What a pending delete refers to. Stored as the value of a `Box<String>`
/// keyed by record id, so no new Hive adapter or typeId is needed — the
/// existing boxes and their typeIds stay untouched.
class PendingDeleteKind {
  static const crypto = 'crypto';
  static const transaction = 'transaction';
}

abstract class CryptoLocalDatasource {
  Future<List<CryptoModel>> getCryptos();
  Future<void> saveCrypto(CryptoEntity crypto);
  Future<void> deleteCrypto(String cryptoId);
  Future<List<TransactionModel>> getTransactionsForCrypto(String cryptoId);
  Future<void> saveTransaction(TransactionEntity transaction);
  Future<void> deleteTransaction(String transactionId);

  /// Every transaction across all coins — needed to reconcile local state
  /// against the cloud.
  Future<List<TransactionModel>> getAllTransactions();

  // ── Tombstones ───────────────────────────────────────────────────────────
  // A delete performed while the cloud is unreachable has to be remembered,
  // otherwise the next pull silently resurrects the record.

  Future<void> recordPendingDelete(String id, String kind);
  Future<Map<String, String>> getPendingDeletes();
  Future<void> clearPendingDelete(String id);

  /// Which account this local store belongs to. Guards against uploading one
  /// user's local data into another user's cloud account.
  Future<String?> getOwnerUserId();
  Future<void> setOwnerUserId(String userId);
  Future<void> clearOwnerUserId();

  /// False until the user has explicitly approved the first cloud sync on this
  /// device, so a backlog is never uploaded before they can back it up.
  Future<bool> isFirstSyncDone();
  Future<void> markFirstSyncDone();
}

/// Keys with this prefix hold metadata, not tombstones.
const String _metaPrefix = '__';
const String _ownerKey = '__owner_user_id';
const String _firstSyncKey = '__first_sync_done';

class CryptoLocalDatasourceImpl implements CryptoLocalDatasource {
  final Box<CryptoModel> cryptoBox;
  final Box<TransactionModel> transactionBox;
  final Box<String> pendingDeleteBox;

  CryptoLocalDatasourceImpl({
    required this.cryptoBox,
    required this.transactionBox,
    required this.pendingDeleteBox,
  });

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
  Future<List<TransactionModel>> getAllTransactions() async {
    return transactionBox.values.toList();
  }

  @override
  Future<void> saveTransaction(TransactionEntity transaction) async {
    await transactionBox.put(transaction.id, TransactionModel.fromEntity(transaction));
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    await transactionBox.delete(transactionId);
  }

  @override
  Future<void> recordPendingDelete(String id, String kind) async {
    await pendingDeleteBox.put(id, kind);
  }

  @override
  Future<Map<String, String>> getPendingDeletes() async {
    return {
      for (final key in pendingDeleteBox.keys)
        if (!(key as String).startsWith(_metaPrefix))
          key: pendingDeleteBox.get(key)!,
    };
  }

  @override
  Future<String?> getOwnerUserId() async => pendingDeleteBox.get(_ownerKey);

  @override
  Future<void> setOwnerUserId(String userId) async =>
      pendingDeleteBox.put(_ownerKey, userId);

  @override
  Future<void> clearOwnerUserId() async => pendingDeleteBox.delete(_ownerKey);

  @override
  Future<bool> isFirstSyncDone() async =>
      pendingDeleteBox.get(_firstSyncKey) == 'true';

  @override
  Future<void> markFirstSyncDone() async =>
      pendingDeleteBox.put(_firstSyncKey, 'true');

  @override
  Future<void> clearPendingDelete(String id) async {
    await pendingDeleteBox.delete(id);
  }
}
