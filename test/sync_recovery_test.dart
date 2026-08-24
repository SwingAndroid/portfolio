import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/sync/sync_status.dart';
import 'package:crypto_portfolio/data/datasources/cloud/sync_service.dart';
import 'package:crypto_portfolio/data/datasources/local/crypto_local_datasource.dart';

import 'fakes.dart';
import 'package:crypto_portfolio/data/repositories/crypto_repository_impl.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

void main() {
  late MemLocal local;
  late FakeCloud cloud;
  late SyncStatus status;
  late CryptoRepositoryImpl repo;
  late SyncService sync;

  setUp(() {
    local = MemLocal();
    cloud = FakeCloud();
    status = SyncStatus();
    repo = CryptoRepositoryImpl(
      localDatasource: local,
      remoteDatasource: OfflineRemote(),
      cloudDatasource: cloud,
      syncStatus: status,
    );
    sync = SyncService(cloudDataSource: cloud, localDataSource: local);
  });

  const btc = CryptoEntity(
    id: 'c1',
    coinId: 'bitcoin',
    name: 'Bitcoin',
    symbol: 'BTC',
    transactions: [],
  );

  TransactionEntity buy(String id, {String crypto = 'c1', double qty = 1}) =>
      TransactionEntity(
        id: id,
        cryptoId: crypto,
        type: TransactionType.buy,
        quantity: qty,
        pricePerCoin: 50000,
        date: DateTime(2026, 8, 17),
      );

  // ── 1. Recovering the backlog ──────────────────────────────────────────────

  group('backlog recovery', () {
    test('uploads every local record the cloud is missing', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      for (var i = 0; i < 5; i++) {
        await repo.addTransaction(buy('t$i'));
      }
      expect(cloud.transactions, isEmpty);

      cloud.offline = false;
      final report = await sync.pushLocalChanges();

      expect(report.ok, isTrue, reason: '${report.error}');
      expect(report.pushedCryptos, 1);
      expect(report.pushedTransactions, 5);
      expect(cloud.transactions.length, 5);
      expect(cloud.cryptos.length, 1);
    });

    test('writes cryptos before transactions (foreign key order)', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await repo.addTransaction(buy('t1'));
      cloud.offline = false;

      // The fake throws on FK violation, so a wrong order fails the report.
      final report = await sync.pushLocalChanges();

      expect(report.ok, isTrue, reason: '${report.error}');
      expect(cloud.calls.indexOf('upsertCryptos'),
          lessThan(cloud.calls.indexOf('upsertTransactions')));
    });

    test('is idempotent — a second push uploads nothing', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await repo.addTransaction(buy('t1'));
      cloud.offline = false;

      await sync.pushLocalChanges();
      final second = await sync.pushLocalChanges();

      expect(second.pushed, 0);
      expect(cloud.transactions.length, 1, reason: 'no duplicates');
    });

    test('batches a large backlog instead of one request per row', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      for (var i = 0; i < 453; i++) {
        await repo.addTransaction(buy('t$i'));
      }
      cloud.offline = false;

      final report = await sync.pushLocalChanges();

      expect(report.pushedTransactions, 453);
      expect(cloud.transactions.length, 453);
      final txBatches = cloud.calls.where((c) => c == 'upsertTransactions');
      expect(txBatches.length, 3, reason: '453 rows in batches of 200');
      expect(cloud.batchSizes, containsAll([200, 200, 53]));
    });

    test('a failed push is reported, never silently swallowed', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);

      final report = await sync.pushLocalChanges();

      expect(report.ok, isFalse);
      expect(report.error, isNotNull);
      expect(status.value.health, SyncHealth.failing,
          reason: 'the write failure surfaced through SyncStatus');
      expect(status.value.lastError, isNotNull);
    });
  });

  // ── 2. Deletes no longer come back ─────────────────────────────────────────

  group('offline deletes', () {
    setUp(() async {
      cloud.cryptos['c1'] = {
        'id': 'c1',
        'coin_id': 'bitcoin',
        'name': 'Bitcoin',
        'symbol': 'BTC',
        'image_url': null,
      };
      cloud.transactions['t1'] = {
        'id': 't1',
        'crypto_id': 'c1',
        'type': 'buy',
        'quantity': 1.0,
        'price_per_coin': 50000.0,
        'date': '2026-08-17T00:00:00Z',
        'note': null,
      };
      await local.saveCrypto(btc);
      await local.saveTransaction(buy('t1'));
    });

    test('a delete made offline is not resurrected by the next pull', () async {
      cloud.offline = true;
      await repo.deleteTransaction('t1');
      expect(local.tombstones['t1'], PendingDeleteKind.transaction);

      cloud.offline = false;
      await sync.pullFromCloud();

      expect(local.txs.containsKey('t1'), isFalse,
          reason: 'the tombstone blocks the resurrect');
    });

    test('the delete is replayed to the cloud once reachable', () async {
      cloud.offline = true;
      await repo.deleteTransaction('t1');

      cloud.offline = false;
      final report = await sync.pushLocalChanges();

      expect(report.deletedRemotely, 1);
      expect(cloud.transactions.containsKey('t1'), isFalse);
      expect(local.tombstones, isEmpty, reason: 'tombstone cleared on success');
    });

    test('the tombstone survives a failed replay', () async {
      cloud.offline = true;
      await repo.deleteTransaction('t1');
      await sync.pushLocalChanges(); // still offline, fails

      expect(local.tombstones.containsKey('t1'), isTrue,
          reason: 'must be retried later, not forgotten');
    });

    test('an online delete leaves no tombstone behind', () async {
      await repo.deleteTransaction('t1');
      expect(local.tombstones, isEmpty);
      expect(cloud.transactions.containsKey('t1'), isFalse);
    });
  });

  // ── 3. Logout can no longer destroy unsynced data ──────────────────────────

  group('destructive guards', () {
    test('clearLocal refuses while local-only data exists', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await repo.addTransaction(buy('t1'));
      cloud.offline = false;

      expect(
        () => sync.clearLocal(),
        throwsA(isA<UnsyncedDataException>()),
      );
      expect(local.txs, isNotEmpty, reason: 'data untouched after refusal');
    });

    test('clearLocal proceeds once everything is synced', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await repo.addTransaction(buy('t1'));
      cloud.offline = false;
      await sync.pushLocalChanges();

      await sync.clearLocal();

      expect(local.cryptos, isEmpty);
      expect(local.txs, isEmpty);
      expect(cloud.transactions.length, 1,
          reason: 'safe to clear: the cloud still has it');
    });

    test('findUnsynced assumes the worst when the cloud is unreachable',
        () async {
      await local.saveCrypto(btc);
      await local.saveTransaction(buy('t1'));
      cloud.offline = true;

      final unsynced = await sync.findUnsynced();

      expect(unsynced, isNotNull,
          reason: 'never report all-clear without proof');
      expect(unsynced!.total, 2);
    });

    test('force bypasses the guard for a deliberate wipe', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await sync.clearLocal(force: true);
      expect(local.cryptos, isEmpty);
    });
  });

  // ── 4. Backup ──────────────────────────────────────────────────────────────

  group('export', () {
    test('contains every local record, including unsynced ones', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      await repo.addTransaction(buy('t1', qty: 0.05969));

      final decoded = jsonDecode(await sync.exportJson());

      expect(decoded['format'], 'crypto_portfolio.backup');
      expect(decoded['counts']['cryptos'], 1);
      expect(decoded['counts']['transactions'], 1);
      expect(decoded['cryptos'].single['coin_id'], 'bitcoin');
      final tx = decoded['transactions'].single;
      expect(tx['quantity'], 0.05969);
      expect(tx['type'], 'buy');
      expect(tx['id'], 't1');
    });

    test('works with the cloud completely unreachable', () async {
      cloud.offline = true;
      await repo.addCrypto(btc);
      final decoded = jsonDecode(await sync.exportJson());
      expect(decoded['counts']['cryptos'], 1);
    });
  });
}
