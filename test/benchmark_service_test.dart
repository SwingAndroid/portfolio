import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/datasources/local/value_history_store.dart';
import 'package:crypto_portfolio/data/services/benchmark_service.dart';
import 'package:crypto_portfolio/data/services/portfolio_history_service.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';

final today = DateTime(2026, 8, 24);
final windowStart = today.subtract(const Duration(days: 364));

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

class FakeRepo implements CryptoRepository {
  FakeRepo({this.failing = const {}, this.growth = const {}});

  final Set<String> failing;

  /// Multiplier applied across the window, e.g. 2.0 doubles.
  final Map<String, double> growth;
  final List<String> chartCalls = [];

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    chartCalls.add(coinId);
    if (failing.contains(coinId)) throw Exception('no data: $coinId');
    final factor = growth[coinId] ?? 1.0;
    return [
      for (var i = 0; i <= 364; i++)
        PricePoint(
          windowStart.add(Duration(days: i)),
          100 * (1 + (factor - 1) * i / 364),
        )
    ];
  }

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
  Future<List<String>> getCoinCategories(String id) async => const [];
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
  Future<void> updateCoinId(String a, String b) async {}
}

CryptoEntity holding({
  required double qty,
  required double price,
  required List<TransactionEntity> txs,
}) =>
    CryptoEntity(
      id: 'c1',
      coinId: 'aave',
      name: 'Aave',
      symbol: 'AAVE',
      currentPrice: price,
      transactions: txs,
    );

TransactionEntity buy(double qty, double price, DateTime date) =>
    TransactionEntity(
      id: 'tx-${date.millisecondsSinceEpoch}',
      cryptoId: 'c1',
      type: TransactionType.buy,
      quantity: qty,
      pricePerCoin: price,
      date: date,
    );

void main() {
  late MemHistory store;
  late FakeRepo repo;
  late BenchmarkService service;

  /// A recorded curve, so the service does not have to rebuild one.
  void seedCurve({required double start, required double end}) {
    for (var i = 0; i <= 364; i++) {
      final day = windowStart.add(Duration(days: i));
      store.rows[ValueSnapshot.keyFor(day)] = ValueSnapshot(
        date: day,
        value: start + (end - start) * i / 364,
        invested: 1000,
      );
    }
  }

  setUp(() {
    store = MemHistory();
    repo = FakeRepo(growth: {'bitcoin': 2.0, 'ethereum': 1.5});
    service = BenchmarkService(
      repository: repo,
      history: PortfolioHistoryService(repository: repo, store: store),
    );
  });

  test('compares against every default yardstick', () async {
    seedCurve(start: 1000, end: 1200);

    final result = await service.compare(
      cryptos: [holding(qty: 10, price: 120, txs: [buy(10, 100, windowStart)])],
      now: today,
    );

    expect(result.hasData, isTrue);
    expect(result.outcomes.map((o) => o.symbol), ['BTC', 'ETH']);
  });

  test('a doubling yardstick doubles the opening stake', () async {
    seedCurve(start: 1000, end: 1200);

    final result = await service.compare(
      cryptos: [holding(qty: 10, price: 120, txs: [buy(10, 100, windowStart)])],
      now: today,
    );

    final btc = result.outcomes.firstWhere((o) => o.symbol == 'BTC');
    // No contributions inside the window, so the stake simply rides the price.
    expect(btc.startValue, closeTo(1000, 1e-6));
    expect(btc.benchmarkValue, closeTo(2000, 5));
    expect(btc.aheadOfBenchmark, isFalse,
        reason: 'the portfolio reached 1200 against 2000');
  });

  test('beating the yardstick is reported as ahead', () async {
    seedCurve(start: 1000, end: 3000);

    final result = await service.compare(
      cryptos: [holding(qty: 10, price: 300, txs: [buy(10, 100, windowStart)])],
      now: today,
    );

    final btc = result.outcomes.firstWhere((o) => o.symbol == 'BTC');
    expect(btc.aheadOfBenchmark, isTrue);
    expect(btc.difference, greaterThan(0));
    expect(btc.rateGap!, greaterThan(0));
  });

  test('reports how much of lifetime capital the window covers', () async {
    seedCurve(start: 1000, end: 1200);

    final result = await service.compare(
      cryptos: [
        holding(qty: 20, price: 120, txs: [
          // Half the money went in years before any price API will serve.
          buy(10, 100, DateTime(2022, 3, 15)),
          buy(10, 100, windowStart.add(const Duration(days: 30))),
        ])
      ],
      now: today,
    );

    expect(result.windowCoverage, closeTo(0.5, 1e-6),
        reason: 'the limit must be visible, not hidden');
  });

  test('one unavailable yardstick does not remove the other', () async {
    repo = FakeRepo(failing: {'ethereum'}, growth: {'bitcoin': 2.0});
    service = BenchmarkService(
      repository: repo,
      history: PortfolioHistoryService(repository: repo, store: store),
    );
    seedCurve(start: 1000, end: 1200);

    final result = await service.compare(
      cryptos: [holding(qty: 10, price: 120, txs: [buy(10, 100, windowStart)])],
      now: today,
    );

    expect(result.outcomes.map((o) => o.symbol), ['BTC']);
    expect(result.error, isNotNull);
  });

  test('an empty portfolio needs no comparison and no requests', () async {
    final result = await service.compare(cryptos: []);
    expect(result.hasData, isFalse);
    expect(repo.chartCalls, isEmpty);
  });

  test('a portfolio with no value yields nothing', () async {
    final result = await service.compare(
      cryptos: [holding(qty: 0, price: 0, txs: [])],
      now: today,
    );
    expect(result.hasData, isFalse);
  });

  test('too little history to span a period is refused', () async {
    // Only one recorded day, and the coin's own chart is unavailable so the
    // curve cannot be rebuilt to fill the rest.
    repo = FakeRepo(failing: {'aave', 'bitcoin', 'ethereum'});
    service = BenchmarkService(
      repository: repo,
      history: PortfolioHistoryService(repository: repo, store: store),
    );
    store.rows[ValueSnapshot.keyFor(today)] =
        ValueSnapshot(date: today, value: 1000, invested: 1000);

    final result = await service.compare(
      cryptos: [holding(qty: 10, price: 120, txs: [buy(10, 100, today)])],
      now: today,
    );

    expect(result.hasData, isFalse,
        reason: 'comparing a period needs a period');
  });
}
