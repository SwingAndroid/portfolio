import 'dart:convert';

import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../local/crypto_local_datasource.dart';
import 'supabase_datasource.dart';

/// Raised when local data would be destroyed while it still has changes the
/// cloud has never seen.
class UnsyncedDataException implements Exception {
  final int cryptos;
  final int transactions;
  const UnsyncedDataException(this.cryptos, this.transactions);

  int get total => cryptos + transactions;

  @override
  String toString() =>
      'UnsyncedDataException($cryptos cryptos, $transactions transactions)';
}

/// Outcome of a push. Everything is reported rather than swallowed, so the UI
/// can tell the difference between "nothing to do" and "it failed again".
class SyncReport {
  final int pushedCryptos;
  final int pushedTransactions;
  final int deletedRemotely;
  final Object? error;

  /// Set when the push was deliberately held back: this device has a backlog
  /// and the user has not yet approved the first upload.
  final UnsyncedDataException? awaiting;

  const SyncReport({
    this.pushedCryptos = 0,
    this.pushedTransactions = 0,
    this.deletedRemotely = 0,
    this.error,
    this.awaiting,
  });

  bool get ok => error == null;
  bool get isHeld => awaiting != null;
  int get pushed => pushedCryptos + pushedTransactions;

  @override
  String toString() => ok
      ? 'SyncReport(+$pushedCryptos cryptos, +$pushedTransactions tx, '
          '-$deletedRemotely deleted)'
      : 'SyncReport(FAILED: $error)';
}

class SyncService {
  final SupabaseDataSource cloudDataSource;
  final CryptoLocalDatasource localDataSource;

  SyncService({required this.cloudDataSource, required this.localDataSource});

  /// Upserts are sent in batches so recovering a large backlog costs a couple
  /// of requests instead of one per row.
  static const int _batchSize = 200;

  // ── Backup ────────────────────────────────────────────────────────────────

  /// Full dump of everything held locally. This is the safety net: local Hive
  /// is the only copy of anything that never reached the cloud.
  Future<String> exportJson() async {
    final cryptos = await localDataSource.getCryptos();
    final transactions = await localDataSource.getAllTransactions();
    final pending = await localDataSource.getPendingDeletes();

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'crypto_portfolio.backup',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'counts': {
        'cryptos': cryptos.length,
        'transactions': transactions.length,
      },
      'cryptos': [
        for (final c in cryptos)
          {
            'id': c.id,
            'coin_id': c.coinId,
            'name': c.name,
            'symbol': c.symbol,
            'image_url': c.imageUrl,
          }
      ],
      'transactions': [
        for (final t in transactions)
          {
            'id': t.id,
            'crypto_id': t.cryptoId,
            'type': TransactionType.values[t.typeIndex].name,
            'quantity': t.quantity,
            'price_per_coin': t.pricePerCoin,
            'date': t.date.toUtc().toIso8601String(),
            'note': t.note,
            'fee': t.fee,
          }
      ],
      'pending_deletes': pending,
    });
  }

  // ── Status ────────────────────────────────────────────────────────────────

  /// Counts local records the cloud does not have. Used to warn before any
  /// destructive action and to drive the sync indicator.
  Future<UnsyncedDataException?> findUnsynced() async {
    try {
      final cloudCryptoIds = {
        for (final c in await cloudDataSource.fetchCryptos()) c['id'] as String
      };
      final cloudTxIds = {
        for (final t in await cloudDataSource.fetchTransactions())
          t['id'] as String
      };

      final localCryptos = await localDataSource.getCryptos();
      final localTx = await localDataSource.getAllTransactions();

      final missingCryptos =
          localCryptos.where((c) => !cloudCryptoIds.contains(c.id)).length;
      final missingTx =
          localTx.where((t) => !cloudTxIds.contains(t.id)).length;

      if (missingCryptos == 0 && missingTx == 0) return null;
      return UnsyncedDataException(missingCryptos, missingTx);
    } catch (_) {
      // Cloud unreachable — we cannot prove anything is synced, so assume the
      // worst rather than risk reporting "all clear".
      final localCryptos = await localDataSource.getCryptos();
      final localTx = await localDataSource.getAllTransactions();
      return UnsyncedDataException(localCryptos.length, localTx.length);
    }
  }

  // ── Push ──────────────────────────────────────────────────────────────────

  /// Sends everything the cloud is missing, plus any deletes made while it was
  /// unreachable.
  ///
  /// This reconciles by comparing ids rather than relying on a change log, so
  /// it also recovers writes made before any outbox existed.
  Future<SyncReport> pushLocalChanges() async {
    try {
      final deleted = await _flushPendingDeletes();

      final cloudCryptoIds = {
        for (final c in await cloudDataSource.fetchCryptos()) c['id'] as String
      };
      final cloudTxIds = {
        for (final t in await cloudDataSource.fetchTransactions())
          t['id'] as String
      };

      // Cryptos first: transactions carry a foreign key to them.
      final missingCryptos = (await localDataSource.getCryptos())
          .where((c) => !cloudCryptoIds.contains(c.id))
          .map((c) => c.toEntity())
          .toList();

      for (final batch in _chunk(missingCryptos)) {
        await cloudDataSource.upsertCryptos(batch);
      }

      final missingTx = (await localDataSource.getAllTransactions())
          .where((t) => !cloudTxIds.contains(t.id))
          .map((t) => t.toEntity())
          .toList();

      for (final batch in _chunk(missingTx)) {
        await cloudDataSource.upsertTransactions(batch);
      }

      return SyncReport(
        pushedCryptos: missingCryptos.length,
        pushedTransactions: missingTx.length,
        deletedRemotely: deleted,
      );
    } catch (e) {
      return SyncReport(error: e);
    }
  }

  Future<int> _flushPendingDeletes() async {
    final pending = await localDataSource.getPendingDeletes();
    var done = 0;
    for (final entry in pending.entries) {
      if (entry.value == PendingDeleteKind.crypto) {
        await cloudDataSource.deleteCrypto(entry.key);
      } else {
        await cloudDataSource.deleteTransaction(entry.key);
      }
      // Only forget the tombstone once the cloud has accepted the delete.
      await localDataSource.clearPendingDelete(entry.key);
      done++;
    }
    return done;
  }

  static Iterable<List<T>> _chunk<T>(List<T> items) sync* {
    for (var i = 0; i < items.length; i += _batchSize) {
      yield items.sublist(
          i, i + _batchSize > items.length ? items.length : i + _batchSize);
    }
  }

  // ── Pull ──────────────────────────────────────────────────────────────────

  /// Pull all data from Supabase and store in Hive.
  ///
  /// Records with a pending delete are skipped, otherwise a delete made while
  /// offline would come straight back on the next refresh.
  Future<void> pullFromCloud() async {
    try {
      final tombstones = await localDataSource.getPendingDeletes();
      final cloudCryptos = await cloudDataSource.fetchCryptos();
      final cloudTransactions = await cloudDataSource.fetchTransactions();

      for (final c in cloudCryptos) {
        final id = c['id'] as String;
        if (tombstones.containsKey(id)) continue;
        await localDataSource.saveCrypto(CryptoEntity(
          id: id,
          coinId: c['coin_id'] as String,
          name: c['name'] as String,
          symbol: c['symbol'] as String,
          imageUrl: c['image_url'] as String?,
          transactions: const [],
        ));
      }

      for (final t in cloudTransactions) {
        final id = t['id'] as String;
        if (tombstones.containsKey(id)) continue;
        if (tombstones[t['crypto_id'] as String] == PendingDeleteKind.crypto) {
          continue;
        }
        await localDataSource.saveTransaction(TransactionEntity(
          id: id,
          cryptoId: t['crypto_id'] as String,
          type: TransactionType.values.firstWhere(
            (e) => e.name == (t['type'] as String),
            orElse: () => TransactionType.buy,
          ),
          quantity: (t['quantity'] as num).toDouble(),
          pricePerCoin: (t['price_per_coin'] as num).toDouble(),
          date: DateTime.parse(t['date'] as String).toLocal(),
          note: t['note'] as String?,
          fee: (t['fee'] as num?)?.toDouble() ?? 0,
        ));
      }
    } catch (e) {
      // Local data stays usable offline; the caller decides whether to surface
      // this. Never let a failed pull take the app down.
    }
  }

  /// Push first, then pull. Ordering matters: uploading local-only records
  /// before pulling means a backlog is never overwritten by server state.
  Future<SyncReport> syncAll() async {
    final report = await pushLocalChanges();
    await pullFromCloud();
    return report;
  }

  // ── Destructive ───────────────────────────────────────────────────────────

  /// Clear all local Hive data (called on logout).
  ///
  /// Refuses to run while local-only data exists, unless [force] is set. This
  /// is the guard that stops a logout from destroying work the cloud never
  /// received.
  Future<void> clearLocal({bool force = false}) async {
    if (!force) {
      final unsynced = await findUnsynced();
      if (unsynced != null) throw unsynced;
    }
    final cryptos = await localDataSource.getCryptos();
    for (final c in cryptos) {
      await localDataSource.deleteCrypto(c.id);
    }
    final leftovers = await localDataSource.getAllTransactions();
    for (final t in leftovers) {
      await localDataSource.deleteTransaction(t.id);
    }
    final pending = await localDataSource.getPendingDeletes();
    for (final id in pending.keys) {
      await localDataSource.clearPendingDelete(id);
    }
    // The device no longer belongs to anyone, so the next account to sign in
    // can claim it and have its own backlog pushed.
    await localDataSource.clearOwnerUserId();
  }
}
