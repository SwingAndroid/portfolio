import 'package:flutter_bloc/flutter_bloc.dart';
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

  CryptoDetailCubit({
    required this.repository,
    required this.addTransaction,
    required this.deleteTransaction,
  }) : super(const CryptoDetailInitial());

  Future<void> loadCrypto(String cryptoId) async {
    emit(const CryptoDetailLoading());
    try {
      final crypto = await repository.getCryptoById(cryptoId);
      if (crypto != null) {
        emit(CryptoDetailLoaded(crypto));
        // Fetch richer market data (ATH, trends) in the background for the
        // Entry Signal. Never let this break the page if the API is down.
        _loadMarketData(crypto.coinId);
      } else {
        emit(const CryptoDetailError('Crypto not found'));
      }
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }

  Future<void> _loadMarketData(String coinId) async {
    try {
      final details = await repository.getCoinDetails(coinId);
      if (details == null) return;
      final md = MarketData.fromCoinDetails(details);
      if (md == null) return;
      final current = state;
      if (current is CryptoDetailLoaded) {
        emit(current.copyWith(marketData: md));
      }
    } catch (_) {
      // Entry Signal degrades gracefully to cost-basis-only.
    }
  }

  Future<void> addNewTransaction(TransactionEntity transaction) async {
    try {
      await addTransaction(transaction);
      if (state is CryptoDetailLoaded) {
        final current = (state as CryptoDetailLoaded).crypto;
        await loadCrypto(current.id);
      }
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }

  Future<void> removeTransaction(String transactionId) async {
    try {
      await deleteTransaction(transactionId);
      if (state is CryptoDetailLoaded) {
        final current = (state as CryptoDetailLoaded).crypto;
        await loadCrypto(current.id);
      }
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
    }
  }
}
