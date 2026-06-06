import 'package:flutter_bloc/flutter_bloc.dart';
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
      } else {
        emit(const CryptoDetailError('Crypto not found'));
      }
    } catch (e) {
      emit(CryptoDetailError(e.toString()));
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
