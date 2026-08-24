import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/errors/exceptions.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/usecases/add_transaction_usecase.dart';
import 'package:crypto_portfolio/domain/usecases/delete_transaction_usecase.dart';
import 'package:crypto_portfolio/presentation/bloc/crypto_detail/crypto_detail_cubit.dart';
import 'package:crypto_portfolio/presentation/bloc/crypto_detail/crypto_detail_state.dart';

/// Reproduces the `mantra-dao` case: `/simple/price` still resolves the legacy
/// id, but every `/coins/{id}` request 404s.
class _FakeRepository implements CryptoRepository {
  _FakeRepository({
    required this.liveCoinId,
    this.resolvesTo,
    this.networkDown = false,
  });

  /// The only coin id the "API" still answers for.
  final String liveCoinId;

  /// What a `/search` lookup would return, or null when nothing matches.
  final String? resolvesTo;

  final bool networkDown;

  String storedCoinId = 'mantra-dao';
  final List<String> updateCalls = [];
  int detailCalls = 0;

  CryptoEntity get _entity => CryptoEntity(
        id: 'local-uuid',
        coinId: storedCoinId,
        name: 'MANTRA',
        symbol: 'OM',
        transactions: const [],
        currentPrice: 0.0655,
      );

  @override
  Future<CryptoEntity?> getCryptoById(String id) async => _entity;

  @override
  Future<Map<String, dynamic>?> getCoinDetails(String coinId) async {
    detailCalls++;
    if (networkDown) throw const RemoteException('connection failed');
    if (coinId != liveCoinId) throw CoinNotFoundException(coinId);
    return {
      'market_data': {
        'current_price': {'usd': 0.0655},
        'ath_change_percentage': {'usd': -96.5},
        'price_change_percentage_30d': -12.0,
      }
    };
  }

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 90}) async {
    if (networkDown) throw const RemoteException('connection failed');
    if (coinId != liveCoinId) throw CoinNotFoundException(coinId);
    return [PricePoint(DateTime(2026, 1, 1), 0.06)];
  }

  @override
  Future<String?> resolveCoinId({
    required String symbol,
    required String name,
  }) async =>
      resolvesTo;

  @override
  Future<void> updateCoinId(String cryptoId, String newCoinId) async {
    updateCalls.add('$cryptoId->$newCoinId');
    storedCoinId = newCoinId;
  }

  // ── Unused by these tests ────────────────────────────────────────────────
  @override
  Future<void> addCrypto(CryptoEntity crypto) async {}
  @override
  Future<void> addTransaction(TransactionEntity transaction) async {}
  @override
  Future<void> deleteCrypto(String cryptoId) async {}
  @override
  Future<void> deleteTransaction(String transactionId) async {}
  @override
  Future<double> getCryptoPrice(String coinId) async => 0.0655;
  @override
  Future<List<CryptoEntity>> getPortfolio() async => [_entity];
  @override
  Future<List<Map<String, dynamic>>> searchCoins(String query) async => [];
}

CryptoDetailCubit _cubit(_FakeRepository repo) => CryptoDetailCubit(
      repository: repo,
      addTransaction: AddTransactionUsecase(repo),
      deleteTransaction: DeleteTransactionUsecase(repo),
    );

Future<CryptoDetailLoaded> _settle(
  CryptoDetailCubit cubit,
  bool Function(CryptoDetailLoaded) done,
) async {
  final state = await cubit.stream
      .where((s) => s is CryptoDetailLoaded && done(s))
      .cast<CryptoDetailLoaded>()
      .first
      .timeout(const Duration(seconds: 3));
  return state;
}

void main() {
  test('repairs a renamed coin id and reloads with working data', () async {
    final repo = _FakeRepository(liveCoinId: 'mantra', resolvesTo: 'mantra');
    final cubit = _cubit(repo);

    await cubit.loadCrypto('local-uuid');
    final state = await _settle(cubit, (s) => s.marketData != null);

    expect(repo.updateCalls, ['local-uuid->mantra'],
        reason: 'corrected id must be persisted exactly once');
    expect(state.crypto.coinId, 'mantra');
    expect(state.repairedFromCoinId, 'mantra-dao');
    expect(state.marketData, isNotNull);
    expect(state.chartError, isNull);

    await cubit.close();
  });

  test('surfaces coinNotFound when no replacement id can be found', () async {
    final repo = _FakeRepository(liveCoinId: 'mantra', resolvesTo: null);
    final cubit = _cubit(repo);

    await cubit.loadCrypto('local-uuid');
    final state = await _settle(cubit, (s) => s.chartError != null);

    expect(repo.updateCalls, isEmpty);
    expect(state.chartError, DetailFailure.coinNotFound);
    expect(state.chartLoading, isFalse,
        reason: 'card must stop spinning so the message can render');

    await cubit.close();
  });

  test('does not retry the repair in a loop when it keeps failing', () async {
    final repo = _FakeRepository(liveCoinId: 'never', resolvesTo: 'still-bad');
    final cubit = _cubit(repo);

    await cubit.loadCrypto('local-uuid');
    await _settle(cubit, (s) => s.chartError != null);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(repo.updateCalls.length, 1,
        reason: 'one repair attempt, then give up');
    expect(repo.detailCalls, lessThan(6), reason: 'must not spin');

    await cubit.close();
  });

  test('network failure is reportable and clears on retry', () async {
    final repo = _FakeRepository(liveCoinId: 'mantra-dao', networkDown: true);
    final cubit = _cubit(repo);

    await cubit.loadCrypto('local-uuid');
    final failed = await _settle(cubit, (s) => s.chartError != null);
    expect(failed.chartError, DetailFailure.network);
    expect(failed.marketDataError, DetailFailure.network);

    await cubit.close();
  });
}
