import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/market_data.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/usecases/add_transaction_usecase.dart';
import '../../../domain/usecases/delete_transaction_usecase.dart';
import '../../../domain/repositories/crypto_repository.dart';
import 'crypto_detail_state.dart';

class CryptoDetailCubit extends Cubit<CryptoDetailState> {
  final CryptoRepository repository;
  final AddTransactionUsecase addTransaction;
  final DeleteTransactionUsecase deleteTransaction;

  /// Coin ids we have already tried to repair, so a failed lookup can never
  /// loop. Scoped to this cubit, so reopening the page retries once more.
  final Set<String> _repairAttempted = {};

  /// Carries the old coin id across the reload that follows a repair.
  String? _repairedFrom;

  CryptoDetailCubit({
    required this.repository,
    required this.addTransaction,
    required this.deleteTransaction,
  }) : super(const CryptoDetailInitial());

  Future<void> loadCrypto(String cryptoId) async {
    emit(const CryptoDetailLoading());
    try {
      final crypto = await repository.getCryptoById(cryptoId);
      if (crypto == null) {
        emit(const CryptoDetailError('Crypto not found'));
        return;
      }
      emit(CryptoDetailLoaded(
        crypto,
        chartLoading: true,
        repairedFromCoinId: _repairedFrom,
      ));
      // Market data and price history load in parallel; neither may break
      // the page, but both now report failure instead of vanishing.
      _loadMarketData(crypto);
      loadChart(crypto.coinId, 90);
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }

  /// Re-runs the `/coins/{id}` request. Wired to the Entry Signal retry.
  Future<void> retryMarketData() async {
    final current = state;
    if (current is! CryptoDetailLoaded) return;
    emit(current.copyWith(clearMarketDataError: true));
    await _loadMarketData(current.crypto);
  }

  /// Re-runs the price-history request for the currently selected range.
  Future<void> retryChart() async {
    final current = state;
    if (current is! CryptoDetailLoaded) return;
    await loadChart(current.crypto.coinId, current.chartDays);
  }

  Future<void> _loadMarketData(CryptoEntity crypto) async {
    try {
      final details = await repository.getCoinDetails(crypto.coinId);
      final md = details == null ? null : MarketData.fromCoinDetails(details);
      final current = state;
      if (current is! CryptoDetailLoaded) return;
      if (md == null) {
        emit(current.copyWith(marketDataError: DetailFailure.network));
        return;
      }
      emit(current.copyWith(marketData: md, clearMarketDataError: true));
    } on CoinNotFoundException {
      if (await _repairCoinId(crypto)) return; // reload already under way
      _failMarketData(DetailFailure.coinNotFound);
    } catch (_) {
      _failMarketData(DetailFailure.network);
    }
  }

  /// Loads price history for the given range (days) and updates the chart.
  Future<void> loadChart(String coinId, int days) async {
    final current = state;
    if (current is! CryptoDetailLoaded) return;
    emit(current.copyWith(
      chartDays: days,
      chartLoading: true,
      clearChartError: true,
    ));
    try {
      final history = await repository.getMarketChart(coinId, days: days);
      final now = state;
      if (now is! CryptoDetailLoaded) return;
      emit(now.copyWith(
        priceHistory: history,
        chartDays: days,
        chartLoading: false,
        clearChartError: true,
      ));
    } on CoinNotFoundException {
      final crypto = _currentCrypto();
      if (crypto != null && await _repairCoinId(crypto)) return;
      _failChart(DetailFailure.coinNotFound);
    } catch (_) {
      _failChart(DetailFailure.network);
    }
  }

  /// A stored coin id stopped resolving upstream — CoinGecko renames ids
  /// (e.g. `mantra-dao` → `mantra`) while the old one keeps working on
  /// `/simple/price`, so the coin still shows a price but every detail
  /// request 404s. Look the coin up again by symbol/name and persist the
  /// correction so this heals permanently.
  Future<bool> _repairCoinId(CryptoEntity crypto) async {
    if (!_repairAttempted.add(crypto.coinId)) return false;
    try {
      final newId = await repository.resolveCoinId(
        symbol: crypto.symbol,
        name: crypto.name,
      );
      if (newId == null || newId == crypto.coinId) return false;
      await repository.updateCoinId(crypto.id, newId);
      _repairedFrom = crypto.coinId;
      await loadCrypto(crypto.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  CryptoEntity? _currentCrypto() {
    final s = state;
    return s is CryptoDetailLoaded ? s.crypto : null;
  }

  void _failMarketData(DetailFailure failure) {
    final s = state;
    if (s is CryptoDetailLoaded) emit(s.copyWith(marketDataError: failure));
  }

  void _failChart(DetailFailure failure) {
    final s = state;
    if (s is CryptoDetailLoaded) {
      emit(s.copyWith(chartLoading: false, chartError: failure));
    }
  }

  Future<void> addNewTransaction(TransactionEntity transaction) async {
    try {
      await addTransaction(transaction);
      final crypto = _currentCrypto();
      if (crypto != null) await loadCrypto(crypto.id);
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }

  Future<void> removeTransaction(String transactionId) async {
    try {
      await deleteTransaction(transactionId);
      final crypto = _currentCrypto();
      if (crypto != null) await loadCrypto(crypto.id);
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }
}
