import '../repositories/crypto_repository.dart';

class DeleteTransactionUsecase {
  final CryptoRepository repository;
  DeleteTransactionUsecase(this.repository);

  Future<void> call(String transactionId) => repository.deleteTransaction(transactionId);
}
