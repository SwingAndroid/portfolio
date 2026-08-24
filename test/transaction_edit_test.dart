import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/sync/sync_status.dart';
import 'package:crypto_portfolio/data/datasources/cloud/sync_service.dart';
import 'package:crypto_portfolio/data/repositories/crypto_repository_impl.dart';
import 'package:crypto_portfolio/domain/analytics/cost_basis_ledger.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

import 'fakes.dart';

TransactionEntity tx(
  String id,
  TransactionType type,
  double qty,
  double price, {
  double fee = 0,
  DateTime? date,
}) =>
    TransactionEntity(
      id: id,
      cryptoId: 'c1',
      type: type,
      quantity: qty,
      pricePerCoin: price,
      date: date ?? DateTime(2026, 1, 1),
      fee: fee,
    );

void main() {
  late MemLocal local;
  late FakeCloud cloud;
  late CryptoRepositoryImpl repo;

  setUp(() {
    local = MemLocal();
    cloud = FakeCloud();
    repo = CryptoRepositoryImpl(
      localDatasource: local,
      remoteDatasource: OfflineRemote(),
      cloudDatasource: cloud,
      syncStatus: SyncStatus(),
    );
  });

  const btc = CryptoEntity(
    id: 'c1',
    coinId: 'bitcoin',
    name: 'Bitcoin',
    symbol: 'BTC',
    transactions: [],
  );

  group('editing a transaction', () {
    test('reusing the id replaces the row instead of duplicating it', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));
      await repo.addTransaction(tx('t1', TransactionType.buy, 2, 150));

      expect(local.txs.length, 1, reason: 'same id, same row');
      expect(cloud.transactions.length, 1, reason: 'upsert, not insert');
    });

    test('the stored values are the edited ones', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));
      await repo.addTransaction(
        tx('t1', TransactionType.buy, 2, 150, fee: 3),
      );

      final stored = local.txs['t1']!.toEntity();
      expect(stored.quantity, 2);
      expect(stored.pricePerCoin, 150);
      expect(stored.fee, 3);
      expect(cloud.transactions['t1']!['quantity'], 2);
      expect(cloud.transactions['t1']!['price_per_coin'], 150);
    });

    test('an edit leaves no tombstone behind', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));
      await repo.addTransaction(tx('t1', TransactionType.buy, 2, 100));

      expect(local.tombstones, isEmpty,
          reason: 'nothing was deleted, so nothing may be resurrected later');
    });

    test('correcting a typo moves the P&L to the right answer', () async {
      // Entered 1000 instead of 100 per coin.
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 1000));

      var ledger = CostBasisLedger.fromTransactions(
          local.txs.values.map((m) => m.toEntity()).toList());
      expect(ledger.remainingCost, closeTo(1000, 1e-9));

      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));

      ledger = CostBasisLedger.fromTransactions(
          local.txs.values.map((m) => m.toEntity()).toList());
      expect(ledger.remainingCost, closeTo(100, 1e-9));
      expect(ledger.remainingQuantity, closeTo(1, 1e-9),
          reason: 'one row, not two');
    });
  });

  group('reclassifying a transfer as income', () {
    test('changing the type rewrites the same row', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.transferIn, 10, 0));
      await repo.addTransaction(tx('t1', TransactionType.reward, 10, 3));

      expect(local.txs.length, 1);
      expect(local.txs['t1']!.toEntity().type, TransactionType.reward);
      expect(cloud.transactions['t1']!['type'], 'reward');
    });

    test('income appears and the basis follows the value at receipt', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.transferIn, 10, 0));

      var ledger = CostBasisLedger.fromTransactions(
          local.txs.values.map((m) => m.toEntity()).toList());
      expect(ledger.income, 0);
      expect(ledger.remainingCost, 0);

      await repo.addTransaction(tx('t1', TransactionType.reward, 10, 3));

      ledger = CostBasisLedger.fromTransactions(
          local.txs.values.map((m) => m.toEntity()).toList());
      expect(ledger.income, closeTo(30, 1e-9));
      expect(ledger.remainingCost, closeTo(30, 1e-9));
      expect(ledger.remainingQuantity, closeTo(10, 1e-9),
          reason: 'the holding itself never changed');
    });

    test('holdings are untouched by a relabel', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.transferIn, 10, 0));
      final before = CostBasisLedger.fromTransactions(
              local.txs.values.map((m) => m.toEntity()).toList())
          .remainingQuantity;

      await repo.addTransaction(tx('t1', TransactionType.reward, 10, 0));
      final after = CostBasisLedger.fromTransactions(
              local.txs.values.map((m) => m.toEntity()).toList())
          .remainingQuantity;

      expect(after, closeTo(before, 1e-9));
    });
  });

  group('editing offline', () {
    test('the change is kept locally and reported, not lost', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));

      cloud.offline = true;
      await repo.addTransaction(tx('t1', TransactionType.buy, 5, 100));

      expect(local.txs['t1']!.toEntity().quantity, 5,
          reason: 'the edit survives on the device');
      expect(cloud.transactions['t1']!['quantity'], 1,
          reason: 'the cloud still holds the old value');
    });

    test('an edit made offline is pushed once the cloud is reachable',
        () async {
      // Comparing ids alone dropped this silently: the row already existed
      // upstream, so nothing was ever re-sent.
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));

      cloud.offline = true;
      await repo.addTransaction(tx('t1', TransactionType.buy, 5, 100));
      cloud.offline = false;

      final report = await SyncService(
        cloudDataSource: cloud,
        localDataSource: local,
      ).pushLocalChanges();

      expect(report.ok, isTrue, reason: '${report.error}');
      expect(report.pushedTransactions, 1);
      expect(cloud.transactions['t1']!['quantity'], 5);
      expect(cloud.transactions.length, 1, reason: 'replaced, not duplicated');
    });

    test('an unchanged row is not re-sent', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));
      cloud.calls.clear();

      final report = await SyncService(
        cloudDataSource: cloud,
        localDataSource: local,
      ).pushLocalChanges();

      expect(report.pushedTransactions, 0,
          reason: 'content comparison must not turn into a full re-upload');
      expect(cloud.calls.where((c) => c.startsWith('upsertTransactions')),
          isEmpty);
    });

    test('logging out refuses while an offline edit is still local', () async {
      await repo.addCrypto(btc);
      await repo.addTransaction(tx('t1', TransactionType.buy, 1, 100));

      cloud.offline = true;
      await repo.addTransaction(tx('t1', TransactionType.buy, 5, 100));
      cloud.offline = false;

      final sync =
          SyncService(cloudDataSource: cloud, localDataSource: local);
      expect(() => sync.clearLocal(), throwsA(isA<UnsyncedDataException>()),
          reason: 'a correction the cloud never got is unsynced data');
    });
  });
}
