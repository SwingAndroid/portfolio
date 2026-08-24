import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/datasources/local/value_history_store.dart';
import 'package:crypto_portfolio/data/services/portfolio_history_service.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';
import 'package:crypto_portfolio/presentation/bloc/history/portfolio_history_cubit.dart';
import 'package:crypto_portfolio/presentation/bloc/history/portfolio_history_state.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';

class _NullStore implements ValueHistoryStore {
  @override
  Future<List<ValueSnapshot>> all() async => [];
  @override
  Future<void> clear() async {}
  @override
  Future<void> record(ValueSnapshot s) async {}
  @override
  Future<List<ValueSnapshot>> since(DateTime from) async => [];
}

class _NullRepo implements CryptoRepository {
  @override
  Future<List<PricePoint>> getMarketChart(String id, {int days = 90}) async => [];
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

/// Counts how often the network-facing service is actually entered.
class CountingService extends PortfolioHistoryService {
  CountingService() : super(repository: _NullRepo(), store: _NullStore());

  int calls = 0;
  bool fail = false;

  @override
  Future<PortfolioHistory> load({
    required List<CryptoEntity> cryptos,
    required int days,
    DateTime? now,
  }) async {
    calls++;
    return PortfolioHistory(
      points: [
        ValueSnapshot(date: DateTime(2026, 8, 23), value: 100, invested: 90),
        ValueSnapshot(date: DateTime(2026, 8, 24), value: 110, invested: 90),
      ],
      backfillError: fail ? Exception('rate limited') : null,
    );
  }
}

void main() {
  late CountingService service;
  late PortfolioHistoryCubit cubit;

  final cryptos = [
    const CryptoEntity(
      id: 'c1',
      coinId: 'bitcoin',
      name: 'Bitcoin',
      symbol: 'BTC',
      transactions: [],
    )
  ];

  setUp(() {
    service = CountingService();
    cubit = PortfolioHistoryCubit(service: service);
  });

  tearDown(() => cubit.close());

  test('a successful window is assembled once, not on every visit', () async {
    await cubit.load(cryptos, days: 90);
    await cubit.load(cryptos, days: 90);
    await cubit.load(cryptos, days: 90);

    expect(service.calls, 1, reason: 'the window is cached for the session');
    expect(cubit.state, isA<PortfolioHistoryLoaded>());
  });

  test('switching range fetches that window, then caches it too', () async {
    await cubit.load(cryptos, days: 90);
    await cubit.load(cryptos, days: 30);
    await cubit.load(cryptos, days: 30);

    expect(service.calls, 2);
  });

  test('a failure earns a cooldown instead of retrying every visit', () async {
    // Rebuilding a year costs one call per coin against a 30-per-minute
    // budget. Retrying on each page visit pinned the app at the limit and
    // starved the coin pages.
    service.fail = true;
    await cubit.load(cryptos, days: 90);
    expect(service.calls, 1);

    await cubit.load(cryptos, days: 90);
    await cubit.load(cryptos, days: 90);

    expect(service.calls, 1, reason: 'no hammering while cooling down');
  });

  test('the card still shows what was recorded while cooling down', () async {
    service.fail = true;
    await cubit.load(cryptos, days: 90);

    final state = cubit.state as PortfolioHistoryLoaded;
    expect(state.history.backfillError, isNotNull);
    expect(state.isDrawable, isTrue,
        reason: 'degraded, not blank — live-recorded days still draw');
  });

  test('an explicit retry overrides the cooldown', () async {
    service.fail = true;
    await cubit.load(cryptos, days: 90);
    await cubit.load(cryptos, days: 90, force: true);

    expect(service.calls, 2, reason: 'the user asked, so we ask');
  });

  test('recovering clears the cooldown and caches the window', () async {
    service.fail = true;
    await cubit.load(cryptos, days: 90);

    service.fail = false;
    await cubit.load(cryptos, days: 90, force: true);
    expect(service.calls, 2);

    await cubit.load(cryptos, days: 90);
    expect(service.calls, 2, reason: 'now cached like any healthy window');
  });

  test('invalidate lets a fresh attempt through', () async {
    await cubit.load(cryptos, days: 90);
    cubit.invalidate();
    await cubit.load(cryptos, days: 90);

    expect(service.calls, 2);
  });

  test('never lingers on the initial state once load is called', () async {
    expect(cubit.state, isA<PortfolioHistoryInitial>());
    await cubit.load(cryptos, days: 90);
    expect(cubit.state, isA<PortfolioHistoryLoaded>(),
        reason: 'initial renders as a spinner, so it must not be terminal');
  });
}
