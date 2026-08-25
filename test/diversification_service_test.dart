import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:crypto_portfolio/data/datasources/local/category_store.dart';
import 'package:crypto_portfolio/data/services/diversification_service.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';

class MemCategories implements CategoryStore {
  final Map<String, List<String>> rows = {};

  @override
  Future<List<String>?> get(String coinId) async => rows[coinId];

  @override
  Future<void> put(String coinId, List<String> categories) async =>
      rows[coinId] = categories;
}

class FakeRepo implements CryptoRepository {
  FakeRepo({this.chartFails = const {}, this.categoryFails = const {}});

  final Set<String> chartFails;
  final Set<String> categoryFails;
  final List<String> chartCalls = [];
  final List<String> categoryCalls = [];

  /// Phase offset per coin, so correlation is controllable.
  final Map<String, double> phase = {};

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    chartCalls.add(coinId);
    if (chartFails.contains(coinId)) throw Exception('chart down: $coinId');
    final p = phase[coinId] ?? 0;
    var price = 100.0;
    final out = <PricePoint>[];
    for (var i = 0; i < 120; i++) {
      price *= 1 + 0.05 * math.sin((i + p) / 3);
      out.add(PricePoint(DateTime(2026, 1, 1).add(Duration(days: i)), price));
    }
    return out;
  }

  @override
  Future<List<String>> getCoinCategories(String coinId) async {
    categoryCalls.add(coinId);
    if (categoryFails.contains(coinId)) throw Exception('down: $coinId');
    return switch (coinId) {
      'ethereum' => ['Layer 1 (L1)', 'Smart Contract Platform', 'GMCI Index'],
      'solana' => ['Layer 1 (L1)', 'Smart Contract Platform'],
      'aave' => ['Decentralized Finance (DeFi)', 'Coinbase 50 Index'],
      _ => const [],
    };
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

CryptoEntity coin(String coinId, String symbol, double qty, double price) =>
    CryptoEntity(
      id: coinId,
      coinId: coinId,
      name: symbol,
      symbol: symbol,
      currentPrice: price,
      transactions: [
        TransactionEntity(
          id: '$coinId-1',
          cryptoId: coinId,
          type: TransactionType.buy,
          quantity: qty,
          pricePerCoin: price,
          date: DateTime(2026, 1, 1),
        ),
      ],
    );

void main() {
  late MemCategories store;
  late FakeRepo repo;
  late DiversificationService service;

  setUp(() {
    store = MemCategories();
    repo = FakeRepo();
    service = DiversificationService(repository: repo, categories: store);
  });

  final portfolio = [
    coin('ethereum', 'ETH', 2, 2000),
    coin('solana', 'SOL', 10, 100),
    coin('aave', 'AAVE', 5, 100),
  ];

  test('measures correlation and weights sectors by value', () async {
    repo.phase.addAll({'ethereum': 0, 'solana': 0, 'aave': 5});

    final result = await service.load(portfolio);

    expect(result.report.hasData, isTrue);
    expect(result.report.coins.length, 3);
    expect(result.error, isNull);

    // ETH and SOL share a phase, so they must read as the same bet.
    expect(result.report.matrix['ETH']!['SOL'], closeTo(1.0, 1e-6));

    // ETH is 4000 of 5500 = 72.7%, plus SOL 1000 -> L1 is 90.9%.
    final l1 = result.sectors.firstWhere((s) => s.sector == 'Layer 1 (L1)');
    expect(l1.weight, closeTo(5000 / 5500, 1e-6));
    expect(l1.symbols, ['ETH', 'SOL']);
  });

  test('index memberships never reach the sector list', () async {
    final result = await service.load(portfolio);
    expect(result.sectors.any((s) => s.sector.contains('Index')), isFalse);
  });

  test('sectors are fetched once, then read from the store', () async {
    await service.load(portfolio);
    expect(repo.categoryCalls.length, 3);

    repo.categoryCalls.clear();
    await service.load(portfolio);

    expect(repo.categoryCalls, isEmpty,
        reason: 'one request per coin per month, not per visit');
  });

  test('a coin whose chart fails drops out without losing the rest', () async {
    repo = FakeRepo(chartFails: {'solana'});
    service = DiversificationService(repository: repo, categories: store);

    final result = await service.load(portfolio);

    expect(result.error, isNotNull, reason: 'the failure is reported');
    expect(result.report.coins.map((c) => c.symbol), ['ETH', 'AAVE']);
    expect(result.sectors, isNotEmpty, reason: 'sectors still came through');
  });

  test('a failed category lookup still leaves the correlation intact', () async {
    repo = FakeRepo(categoryFails: {'aave'});
    service = DiversificationService(repository: repo, categories: store);

    final result = await service.load(portfolio);

    expect(result.report.hasData, isTrue);
    expect(result.sectors.any((s) => s.symbols.contains('AAVE')), isFalse);
    expect(result.error, isNotNull);
  });

  test('coins that are sold off or unpriced are skipped', () async {
    final result = await service.load([
      ...portfolio,
      coin('bitcoin', 'BTC', 0, 70000), // nothing held
      coin('quant-network', 'QNT', 5, 0), // no price
    ]);

    expect(result.report.coins.map((c) => c.symbol), ['ETH', 'SOL', 'AAVE']);
    expect(repo.chartCalls, isNot(contains('bitcoin')));
    expect(repo.chartCalls, isNot(contains('quant-network')));
  });

  test('a single holding cannot be diversified, and costs no requests',
      () async {
    final result = await service.load([coin('ethereum', 'ETH', 1, 2000)]);

    expect(result.hasAnything, isFalse);
    expect(repo.chartCalls, isEmpty);
    expect(repo.categoryCalls, isEmpty);
  });

  test('an empty portfolio is neutral', () async {
    final result = await service.load([]);
    expect(result.hasAnything, isFalse);
    expect(result.error, isNull);
  });

  group('category store', () {
    late Box<String> box;

    setUpAll(() {
      final dir = Directory('${Directory.systemTemp.path}/hive_category_store');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      Hive.init(dir.path);
    });

    setUp(() async {
      box = await Hive.openBox<String>('cats');
      await box.clear();
    });

    tearDown(() async => box.close());

    test('round-trips the labels', () async {
      final store = CategoryStoreImpl(box);
      await store.put('ethereum', ['Layer 1 (L1)', 'Smart Contract Platform']);
      expect(await store.get('ethereum'),
          ['Layer 1 (L1)', 'Smart Contract Platform']);
    });

    test('an entry past its TTL counts as a miss so labels can refresh',
        () async {
      final store = CategoryStoreImpl(box);
      // Written by hand with an old stamp, as a month-old cache would be.
      await box.put('ethereum',
          '{"c":["Layer 1 (L1)"],"at":"2020-01-01T00:00:00.000"}');
      expect(await store.get('ethereum'), isNull);
    });

    test('a corrupt row is a miss, not a crash', () async {
      final store = CategoryStoreImpl(box);
      await box.put('eth', 'not json at all');
      expect(await store.get('eth'), isNull);
    });

    test('an unknown coin is simply absent', () async {
      expect(await CategoryStoreImpl(box).get('nope'), isNull);
    });
  });
}

