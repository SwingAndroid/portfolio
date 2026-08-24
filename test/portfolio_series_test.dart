import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/datasources/local/value_history_store.dart';
import 'package:crypto_portfolio/data/services/portfolio_history_service.dart';
import 'package:crypto_portfolio/domain/analytics/portfolio_series.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';

// ── Doubles ──────────────────────────────────────────────────────────────────

class MemHistory implements ValueHistoryStore {
  final Map<String, ValueSnapshot> rows = {};

  @override
  Future<void> record(ValueSnapshot s) async => rows[s.key] = s;

  @override
  Future<List<ValueSnapshot>> all() async =>
      rows.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<List<ValueSnapshot>> since(DateTime from) async {
    final cutoff = DateTime(from.year, from.month, from.day);
    return (await all()).where((s) => !s.date.isBefore(cutoff)).toList();
  }

  @override
  Future<void> clear() async => rows.clear();
}

class FakeChartRepo implements CryptoRepository {
  FakeChartRepo({this.pricePerDay = 100, this.fails = false});

  final double pricePerDay;
  bool fails;
  final List<String> chartCalls = [];

  /// Days back from [anchor] that the fake will serve.
  DateTime anchor = DateTime(2026, 8, 24);
  int coverDays = 365;

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    chartCalls.add(coinId);
    if (fails) throw Exception('rate limited');
    final out = <PricePoint>[];
    for (var i = coverDays - 1; i >= 0; i--) {
      out.add(PricePoint(anchor.subtract(Duration(days: i)), pricePerDay));
    }
    return out;
  }

  // ── Unused here ───────────────────────────────────────────────────────────
  @override
  Future<void> addCrypto(CryptoEntity c) async {}
  @override
  Future<void> addTransaction(TransactionEntity t) async {}
  @override
  Future<void> deleteCrypto(String id) async {}
  @override
  Future<void> deleteTransaction(String id) async {}
  @override
  Future<Map<String, dynamic>?> getCoinDetails(String id) async => null;
  @override
  Future<CryptoEntity?> getCryptoById(String id) async => null;
  @override
  Future<double> getCryptoPrice(String id) async => 0;
  @override
  Future<List<CryptoEntity>> getPortfolio() async => [];
  @override
  Future<String?> resolveCoinId(
          {required String symbol, required String name}) async =>
      null;
  @override
  Future<List<Map<String, dynamic>>> searchCoins(String q) async => [];
  @override
  Future<void> updateCoinId(String cryptoId, String newCoinId) async {}
}

TransactionEntity buy(String id, double qty, double price, DateTime date,
        {double fee = 0}) =>
    TransactionEntity(
      id: id,
      cryptoId: 'c1',
      type: TransactionType.buy,
      quantity: qty,
      pricePerCoin: price,
      date: date,
      fee: fee,
    );

CryptoEntity coin(List<TransactionEntity> txs, {String id = 'c1'}) =>
    CryptoEntity(
      id: id,
      coinId: id == 'c1' ? 'bitcoin' : 'ethereum',
      name: id,
      symbol: id.toUpperCase(),
      transactions: txs,
    );

void main() {
  // ── The pure series builder ───────────────────────────────────────────────

  group('buildDailySeries', () {
    test('holdings accumulate as the sweep passes each transaction', () {
      final series = buildDailySeries(
        cryptos: [
          coin([
            buy('1', 1, 100, DateTime(2026, 8, 1)),
            buy('2', 1, 100, DateTime(2026, 8, 3)),
          ])
        ],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 4),
        priceAt: (_, __) => 200,
      );

      expect(series.map((s) => s.value).toList(),
          orderedEquals([200.0, 200.0, 400.0, 400.0]));
      expect(series.map((s) => s.invested).toList(),
          orderedEquals([100.0, 100.0, 200.0, 200.0]));
    });

    test('a day with no price for a held coin is omitted, not guessed', () {
      final series = buildDailySeries(
        cryptos: [coin([buy('1', 1, 100, DateTime(2026, 8, 1))])],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 3),
        // The middle day has no sample.
        priceAt: (_, d) => d.day == 2 ? null : 200,
      );

      expect(series.map((s) => s.date.day).toList(), [1, 3],
          reason: 'a wrong point is worse than a missing one');
    });

    test('a sale lowers both holdings and capital engaged', () {
      final series = buildDailySeries(
        cryptos: [
          coin([
            buy('1', 2, 100, DateTime(2026, 8, 1)),
            TransactionEntity(
              id: '2',
              cryptoId: 'c1',
              type: TransactionType.sell,
              quantity: 1,
              pricePerCoin: 150,
              date: DateTime(2026, 8, 3),
            ),
          ])
        ],
        from: DateTime(2026, 8, 2),
        to: DateTime(2026, 8, 3),
        priceAt: (_, __) => 150,
      );

      expect(series.first.value, closeTo(300, 1e-9));
      expect(series.first.invested, closeTo(200, 1e-9));
      expect(series.last.value, closeTo(150, 1e-9));
      expect(series.last.invested, closeTo(50, 1e-9),
          reason: '200 spent, 150 returned');
    });

    test('fees raise the capital engaged line', () {
      final series = buildDailySeries(
        cryptos: [coin([buy('1', 1, 100, DateTime(2026, 8, 1), fee: 7)])],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 1),
        priceAt: (_, __) => 100,
      );

      expect(series.single.invested, closeTo(107, 1e-9));
      expect(series.single.profitLoss, closeTo(-7, 1e-9));
    });

    test('days before anything happened are skipped', () {
      final series = buildDailySeries(
        cryptos: [coin([buy('1', 1, 100, DateTime(2026, 8, 5))])],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 6),
        priceAt: (_, __) => 100,
      );

      expect(series.first.date, DateTime(2026, 8, 5));
      expect(series.length, 2);
    });

    test('several transactions on one day all land that day', () {
      final series = buildDailySeries(
        cryptos: [
          coin([
            buy('1', 1, 100, DateTime(2026, 8, 1, 9)),
            buy('2', 1, 100, DateTime(2026, 8, 1, 14)),
            buy('3', 1, 100, DateTime(2026, 8, 1, 20)),
          ])
        ],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 1),
        priceAt: (_, __) => 100,
      );

      expect(series.single.value, closeTo(300, 1e-9));
    });

    test('an inverted range yields nothing', () {
      expect(
        buildDailySeries(
          cryptos: [coin([buy('1', 1, 100, DateTime(2026, 8, 1))])],
          from: DateTime(2026, 8, 5),
          to: DateTime(2026, 8, 1),
          priceAt: (_, __) => 100,
        ),
        isEmpty,
      );
    });
  });

  // ── Price indexing ────────────────────────────────────────────────────────

  group('DailyPriceIndex', () {
    test('finds an exact day and carries the last price forward', () {
      final index = DailyPriceIndex()
        ..add('bitcoin', [
          (time: DateTime(2026, 8, 1), price: 100.0),
          (time: DateTime(2026, 8, 4), price: 130.0),
        ]);

      expect(index.priceAt('bitcoin', DateTime(2026, 8, 1)), 100);
      expect(index.priceAt('bitcoin', DateTime(2026, 8, 2)), 100,
          reason: 'a missing sample carries forward');
      expect(index.priceAt('bitcoin', DateTime(2026, 8, 4)), 130);
    });

    test('never invents a price before the first sample', () {
      final index = DailyPriceIndex()
        ..add('bitcoin', [(time: DateTime(2026, 8, 10), price: 100.0)]);

      expect(index.priceAt('bitcoin', DateTime(2026, 8, 9)), isNull);
    });

    test('gives up after a week without a sample', () {
      final index = DailyPriceIndex()
        ..add('bitcoin', [(time: DateTime(2026, 8, 1), price: 100.0)]);

      expect(index.priceAt('bitcoin', DateTime(2026, 8, 7)), 100);
      expect(index.priceAt('bitcoin', DateTime(2026, 8, 20)), isNull);
    });

    test('the last sample of a day wins', () {
      final index = DailyPriceIndex()
        ..add('bitcoin', [
          (time: DateTime(2026, 8, 1, 3), price: 100.0),
          (time: DateTime(2026, 8, 1, 23), price: 111.0),
        ]);

      expect(index.priceAt('bitcoin', DateTime(2026, 8, 1)), 111);
    });

    test('an unknown coin has no price', () {
      final index = DailyPriceIndex();
      expect(index.priceAt('nope', DateTime(2026, 8, 1)), isNull);
      expect(index.covers('nope'), isFalse);
    });
  });

  // ── The service that stitches recorded and rebuilt days together ──────────

  group('PortfolioHistoryService', () {
    late MemHistory store;
    late FakeChartRepo repo;
    late PortfolioHistoryService service;
    final today = DateTime(2026, 8, 24);

    setUp(() {
      store = MemHistory();
      repo = FakeChartRepo(pricePerDay: 200);
      service = PortfolioHistoryService(repository: repo, store: store);
    });

    List<CryptoEntity> portfolio() =>
        [coin([buy('1', 1, 100, DateTime(2026, 8, 1))])];

    test('fills gaps from market data and keeps them', () async {
      final result = await service.load(
        cryptos: portfolio(),
        days: 10,
        now: today,
      );

      expect(result.points, isNotEmpty);
      expect(result.reconstructedDays, greaterThan(0));
      expect(result.backfillError, isNull);
      expect(store.rows, isNotEmpty,
          reason: 'rebuilt days are persisted, not recomputed every time');
      expect(result.points.last.value, closeTo(200, 1e-9));
    });

    test('a recorded observation is never overwritten by a rebuild', () async {
      // A real reading of 999 on one day, which market data would price at 200.
      await store.record(
        ValueSnapshot(date: DateTime(2026, 8, 20), value: 999, invested: 100),
      );

      final result = await service.load(
        cryptos: portfolio(),
        days: 10,
        now: today,
      );

      final kept =
          result.points.firstWhere((s) => s.key == '2026-08-20');
      expect(kept.value, 999,
          reason: 'what was actually observed outranks a reconstruction');
    });

    test('skips the network entirely when nothing is missing', () async {
      for (var i = 0; i < 5; i++) {
        await store.record(ValueSnapshot(
          date: today.subtract(Duration(days: i)),
          value: 500,
          invested: 100,
        ));
      }

      final result =
          await service.load(cryptos: portfolio(), days: 5, now: today);

      expect(repo.chartCalls, isEmpty, reason: 'no gap, no fetch');
      expect(result.points.length, 5);
      expect(result.reconstructedDays, 0);
    });

    test('a failed backfill still returns what was recorded', () async {
      await store.record(
        ValueSnapshot(date: DateTime(2026, 8, 23), value: 777, invested: 100),
      );
      repo.fails = true;

      final result =
          await service.load(cryptos: portfolio(), days: 10, now: today);

      expect(result.backfillError, isNotNull);
      expect(result.points.single.value, 777,
          reason: 'the curve degrades, it does not disappear');
    });

    test('does not attempt to rebuild beyond the 365-day ceiling', () async {
      // Ask for three years; only the last year can be reconstructed.
      final result =
          await service.load(cryptos: portfolio(), days: 1095, now: today);

      final oldest = result.points.first.date;
      final horizon = today.subtract(
        const Duration(days: PortfolioHistoryService.maxReconstructableDays - 1),
      );
      expect(oldest.isBefore(horizon), isFalse,
          reason: 'the API cannot serve older data, so none is invented');
    });

    test('an empty portfolio needs no network', () async {
      final result = await service.load(cryptos: [], days: 30, now: today);
      expect(result.points, isEmpty);
      expect(repo.chartCalls, isEmpty);
    });

    test('a coin already sold off is not fetched', () async {
      final soldOut = CryptoEntity(
        id: 'c2',
        coinId: 'ethereum',
        name: 'eth',
        symbol: 'ETH',
        transactions: [
          buy('a', 1, 100, DateTime(2026, 8, 1)),
          TransactionEntity(
            id: 'b',
            cryptoId: 'c2',
            type: TransactionType.sell,
            quantity: 1,
            pricePerCoin: 150,
            date: DateTime(2026, 8, 2),
          ),
        ],
      );

      await service.load(
        cryptos: [...portfolio(), soldOut],
        days: 10,
        now: today,
      );

      expect(repo.chartCalls, ['bitcoin'],
          reason: 'nothing held means nothing to price');
    });
  });

  // ── Capital engaged is recomputed, never trusted from storage ────────────

  group('investedByDay', () {
    test('accumulates as transactions land', () {
      final map = investedByDay(
        cryptos: [
          coin([
            buy('1', 1, 100, DateTime(2026, 8, 2)),
            buy('2', 1, 50, DateTime(2026, 8, 4)),
          ])
        ],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 5),
      );

      expect(map['2026-08-01'], 0);
      expect(map['2026-08-02'], closeTo(100, 1e-9));
      expect(map['2026-08-03'], closeTo(100, 1e-9));
      expect(map['2026-08-04'], closeTo(150, 1e-9));
      expect(map['2026-08-05'], closeTo(150, 1e-9));
    });

    test('carries in everything that happened before the window', () {
      final map = investedByDay(
        cryptos: [coin([buy('1', 1, 900, DateTime(2020, 1, 1))])],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 2),
      );

      expect(map['2026-08-01'], closeTo(900, 1e-9),
          reason: 'the window is a view, not a starting point');
    });

    test('a sale returns capital', () {
      final map = investedByDay(
        cryptos: [
          coin([
            buy('1', 2, 100, DateTime(2026, 8, 1)),
            TransactionEntity(
              id: '2',
              cryptoId: 'c1',
              type: TransactionType.sell,
              quantity: 1,
              pricePerCoin: 150,
              date: DateTime(2026, 8, 3),
            ),
          ])
        ],
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 3),
      );

      expect(map['2026-08-01'], closeTo(200, 1e-9));
      expect(map['2026-08-03'], closeTo(50, 1e-9));
    });
  });

  group('back-dated transactions', () {
    test('correct the capital line of snapshots already stored', () async {
      final store = MemHistory();
      final repo = FakeChartRepo(pricePerDay: 200)..fails = true;
      final service = PortfolioHistoryService(repository: repo, store: store);
      final today = DateTime(2026, 8, 24);

      // A snapshot taken back when only one buy was known.
      await store.record(ValueSnapshot(
          date: DateTime(2026, 8, 20), value: 500, invested: 100));

      // The user later enters a purchase they had forgotten, dated earlier.
      final withBackdated = [
        coin([
          buy('1', 1, 100, DateTime(2026, 8, 1)),
          buy('forgotten', 1, 250, DateTime(2026, 8, 10)),
        ])
      ];

      final result = await service.load(
        cryptos: withBackdated,
        days: 10,
        now: today,
      );

      final point = result.points.firstWhere((s) => s.key == '2026-08-20');
      expect(point.value, 500, reason: 'what the market said is untouched');
      expect(point.invested, closeTo(350, 1e-9),
          reason: 'what was put in is recomputed from current transactions');
    });
  });
}
