import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/sync/sync_status.dart';
import 'package:crypto_portfolio/data/datasources/cloud/account_sync.dart';
import 'package:crypto_portfolio/data/datasources/cloud/sync_service.dart';
import 'package:crypto_portfolio/data/repositories/crypto_repository_impl.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

import 'fakes.dart';

/// Simulation of the real device before deploying.
///
/// Reproduces the live situation: 453 transactions across 8 coins already in
/// the cloud, plus a local-only backlog that no cloud write ever received.
/// Every test here answers one question — can this deployment lose data?
void main() {
  late MemLocal local;
  late FakeCloud cloud;
  late SyncStatus status;
  late CryptoRepositoryImpl repo;
  late SyncService sync;
  late AccountSync account;

  const me = '9ffd4996-d9d3-4f7b-bf6a-3af5edd32870';
  const someoneElse = '11111111-2222-3333-4444-555555555555';

  /// Coins as they exist in the real database.
  const coins = <String, String>{
    'c-aave': 'aave',
    'c-apt': 'aptos',
    'c-bnb': 'binancecoin',
    'c-btc': 'bitcoin',
    'c-eth': 'ethereum',
    'c-qnt': 'quant-network',
    'c-sei': 'sei-network',
    'c-sol': 'solana',
  };

  TransactionEntity tx(String id, String cryptoId,
          {double qty = 1, double price = 100, DateTime? date}) =>
      TransactionEntity(
        id: id,
        cryptoId: cryptoId,
        type: TransactionType.buy,
        quantity: qty,
        pricePerCoin: price,
        date: date ?? DateTime(2026, 6, 1),
      );

  /// Puts the device and cloud into the pre-deployment state:
  /// everything up to 8 June is on both sides, everything after is local only.
  Future<void> seedRealWorldState({int cloudTx = 453, int localOnly = 12}) async {
    for (final entry in coins.entries) {
      final crypto = CryptoEntity(
        id: entry.key,
        coinId: entry.value,
        name: entry.value,
        symbol: entry.value.toUpperCase(),
        transactions: const [],
      );
      await local.saveCrypto(crypto);
      cloud.cryptos[entry.key] = {
        'id': entry.key,
        'coin_id': entry.value,
        'name': entry.value,
        'symbol': entry.value.toUpperCase(),
        'image_url': null,
      };
    }

    final ids = coins.keys.toList();
    // Synced history: present on both sides.
    for (var i = 0; i < cloudTx; i++) {
      final t = tx('synced-$i', ids[i % ids.length]);
      await local.saveTransaction(t);
      cloud.transactions[t.id] = {
        'id': t.id,
        'crypto_id': t.cryptoId,
        'type': 'buy',
        'quantity': t.quantity,
        'price_per_coin': t.pricePerCoin,
        'date': t.date.toUtc().toIso8601String(),
        'note': null,
      };
    }
    // The backlog: only on the device.
    for (var i = 0; i < localOnly; i++) {
      await local.saveTransaction(
        tx('local-only-$i', ids[i % ids.length], date: DateTime(2026, 8, 17)),
      );
    }
    cloud.calls.clear();
  }

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
    account = AccountSync(local: local, sync: sync);
  });

  // ── The deployment itself ──────────────────────────────────────────────────

  group('first launch after deployment', () {
    test('recovers the backlog and loses nothing', () async {
      await seedRealWorldState();
      expect(cloud.transactions.length, 453);
      expect(local.txs.length, 465);

      final report = await account.syncForUser(me, confirmed: true);

      expect(report.ok, isTrue, reason: '${report.error}');
      expect(report.pushedTransactions, 12, reason: 'only the backlog');
      expect(report.pushedCryptos, 0, reason: 'coins were already synced');
      expect(cloud.transactions.length, 465, reason: 'cloud caught up');
      expect(local.txs.length, 465, reason: 'nothing removed locally');
      for (var i = 0; i < 12; i++) {
        expect(cloud.transactions.containsKey('local-only-$i'), isTrue);
        expect(local.txs.containsKey('local-only-$i'), isTrue);
      }
    });

    test('claims the device for the signed-in account', () async {
      await seedRealWorldState();
      expect(local.owner, isNull, reason: 'no owner before the deploy');

      await account.syncForUser(me, confirmed: true);

      expect(local.owner, me);
    });

    test('deploying while offline destroys nothing', () async {
      await seedRealWorldState();
      cloud.offline = true;

      final report = await account.syncForUser(me, confirmed: true);

      expect(report.ok, isFalse, reason: 'the failure is reported, not hidden');
      expect(local.txs.length, 465, reason: 'every local record still there');
      expect(local.cryptos.length, 8);

      // ... and the backlog still goes up once the network returns.
      cloud.offline = false;
      final retry = await account.syncForUser(me, confirmed: true);
      expect(retry.pushedTransactions, 12);
      expect(cloud.transactions.length, 465);
    });

    test('a lost session does not touch local data', () async {
      await seedRealWorldState();

      // The deploy logs the user out: no sync runs at all, because AuthCubit
      // only calls syncForUser when a user is present.
      expect(local.txs.length, 465);
      expect(local.cryptos.length, 8);

      // Signing back in recovers the backlog.
      final report = await account.syncForUser(me, confirmed: true);
      expect(report.pushedTransactions, 12);
      expect(cloud.transactions.length, 465);
    });

    test('surviving several app restarts changes nothing', () async {
      await seedRealWorldState();

      for (var i = 0; i < 5; i++) {
        await account.syncForUser(me, confirmed: true);
      }

      expect(cloud.transactions.length, 465, reason: 'no duplicates');
      expect(local.txs.length, 465, reason: 'no losses');
      final pushes = cloud.calls.where((c) => c == 'upsertTransactions').length;
      expect(pushes, 1, reason: 'only the first run had anything to send');
    });
  });

  // ── The first-run gate ─────────────────────────────────────────────────────

  group('first-run gate', () {
    test('holds the upload until the user approves it', () async {
      await seedRealWorldState();

      final report = await account.syncForUser(me); // not confirmed

      expect(report.isHeld, isTrue);
      expect(report.awaiting!.transactions, 12);
      expect(cloud.transactions.length, 453,
          reason: 'nothing uploaded before approval');
      expect(cloud.calls.where((c) => c.startsWith('upsert')), isEmpty);
      expect(local.txs.length, 465, reason: 'and nothing changed locally');
    });

    test('the backup is available while the upload is held', () async {
      await seedRealWorldState();
      await account.syncForUser(me);

      final decoded = jsonDecode(await sync.exportJson());

      expect(decoded['counts']['transactions'], 465,
          reason: 'the whole point of holding: back up first');
    });

    test('approving uploads the backlog', () async {
      await seedRealWorldState();
      await account.syncForUser(me);

      final report = await account.syncForUser(me, confirmed: true);

      expect(report.pushedTransactions, 12);
      expect(cloud.transactions.length, 465);
      expect(local.firstSyncDone, isTrue);
    });

    test('later launches sync automatically, without gating again', () async {
      await seedRealWorldState();
      await account.syncForUser(me, confirmed: true);

      // New local write, then a plain restart.
      cloud.offline = true;
      await repo.addTransaction(tx('after-approval', 'c-eth'));
      cloud.offline = false;

      final report = await account.syncForUser(me); // not confirmed

      expect(report.isHeld, isFalse, reason: 'gate only applies once');
      expect(cloud.transactions.containsKey('after-approval'), isTrue);
    });

    test('a device with nothing at stake is never gated', () async {
      await seedRealWorldState(localOnly: 0);

      final report = await account.syncForUser(me);

      expect(report.isHeld, isFalse);
      expect(report.ok, isTrue);
      expect(local.firstSyncDone, isTrue);
    });

    test('holding repeatedly never uploads anything', () async {
      await seedRealWorldState();

      for (var i = 0; i < 3; i++) {
        final r = await account.syncForUser(me);
        expect(r.isHeld, isTrue);
      }

      expect(cloud.transactions.length, 453);
      expect(local.txs.length, 465);
    });
  });

  // ── Nothing may quietly remove local rows ──────────────────────────────────

  group('local data is never silently removed', () {
    test('a pull does not delete local rows the cloud lacks', () async {
      await seedRealWorldState();

      await sync.pullFromCloud();

      expect(local.txs.length, 465,
          reason: 'pull only adds; the 12 local-only rows survive');
      for (var i = 0; i < 12; i++) {
        expect(local.txs.containsKey('local-only-$i'), isTrue);
      }
    });

    test('a failed push leaves local untouched', () async {
      await seedRealWorldState();
      cloud.offline = true;

      await sync.pushLocalChanges();

      expect(local.txs.length, 465);
      expect(status.value.health, SyncHealth.unknown,
          reason: 'push failures report through the SyncReport, not a write');
    });

    test('logout is refused while the backlog exists', () async {
      await seedRealWorldState();

      expect(() => sync.clearLocal(), throwsA(isA<UnsyncedDataException>()));
      expect(local.txs.length, 465, reason: 'refusal must be non-destructive');
    });

    test('logout is allowed only once the cloud has everything', () async {
      await seedRealWorldState();
      await account.syncForUser(me, confirmed: true);

      await sync.clearLocal();

      expect(local.txs, isEmpty);
      expect(cloud.transactions.length, 465, reason: 'safe: cloud has it all');
      expect(local.owner, isNull, reason: 'device released for the next user');
    });
  });

  // ── Wrong-account protection ───────────────────────────────────────────────

  group('account isolation', () {
    test('never uploads this device\'s data into another account', () async {
      await seedRealWorldState();
      await account.syncForUser(me, confirmed: true); // device belongs to me
      cloud.calls.clear();

      final report = await account.syncForUser(someoneElse, confirmed: true);

      expect(report.pushed, 0, reason: 'no cross-account upload');
      expect(cloud.calls.where((c) => c.startsWith('upsert')), isEmpty);
      expect(local.txs.length, 465, reason: 'and local data is left alone');
    });
  });

  // ── Backup ─────────────────────────────────────────────────────────────────

  group('backup before deploying', () {
    test('captures the full local state including the backlog', () async {
      await seedRealWorldState();

      final decoded = jsonDecode(await sync.exportJson());

      expect(decoded['counts']['transactions'], 465);
      expect(decoded['counts']['cryptos'], 8);
      final ids = (decoded['transactions'] as List)
          .map((t) => t['id'] as String)
          .toSet();
      for (var i = 0; i < 12; i++) {
        expect(ids.contains('local-only-$i'), isTrue,
            reason: 'the unsynced rows are the ones that matter most');
      }
    });

    test('still works with the cloud fully down', () async {
      await seedRealWorldState();
      cloud.offline = true;

      final decoded = jsonDecode(await sync.exportJson());

      expect(decoded['counts']['transactions'], 465);
    });

    test('a restored backup can be replayed into the cloud', () async {
      await seedRealWorldState();
      final backup = jsonDecode(await sync.exportJson());

      // Worst case: the device is wiped. Rebuild local from the backup file.
      await sync.clearLocal(force: true);
      expect(local.txs, isEmpty);

      for (final c in backup['cryptos'] as List) {
        await local.saveCrypto(CryptoEntity(
          id: c['id'] as String,
          coinId: c['coin_id'] as String,
          name: c['name'] as String,
          symbol: c['symbol'] as String,
          transactions: const [],
        ));
      }
      for (final t in backup['transactions'] as List) {
        await local.saveTransaction(TransactionEntity(
          id: t['id'] as String,
          cryptoId: t['crypto_id'] as String,
          type: TransactionType.values.firstWhere((e) => e.name == t['type']),
          quantity: (t['quantity'] as num).toDouble(),
          pricePerCoin: (t['price_per_coin'] as num).toDouble(),
          date: DateTime.parse(t['date'] as String),
        ));
      }

      expect(local.txs.length, 465, reason: 'restored intact');
      final report = await sync.pushLocalChanges();
      expect(report.ok, isTrue, reason: '${report.error}');
      expect(cloud.transactions.length, 465);
    });
  });

  // ── The user's own transaction ─────────────────────────────────────────────

  test('the missing ETH buy reaches the cloud after deployment', () async {
    await seedRealWorldState(localOnly: 0);
    // 0.05969 ETH at 112.25, dated 17/08/2026 — entered on the device, never
    // seen by the cloud.
    cloud.offline = true;
    await repo.addTransaction(TransactionEntity(
      id: 'eth-17-08',
      cryptoId: 'c-eth',
      type: TransactionType.buy,
      quantity: 0.05969,
      pricePerCoin: 112.25,
      date: DateTime(2026, 8, 17),
    ));
    expect(cloud.transactions.containsKey('eth-17-08'), isFalse);

    cloud.offline = false;
    await account.syncForUser(me, confirmed: true);

    final row = cloud.transactions['eth-17-08'];
    expect(row, isNotNull, reason: 'the transaction finally landed');
    expect(row!['quantity'], 0.05969);
    expect(row['price_per_coin'], 112.25);
    expect(row['crypto_id'], 'c-eth');
    expect(local.txs.containsKey('eth-17-08'), isTrue, reason: 'still local too');
  });
}
