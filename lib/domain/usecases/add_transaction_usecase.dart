import '../entities/transaction_entity.dart';
import '../repositories/crypto_repository.dart';

class AddTransactionUsecase {
  final CryptoRepository repository;
  AddTransactionUsecase(this.repository);

  Future<void> call(TransactionEntity transaction) => repository.addTransaction(transaction);
}
