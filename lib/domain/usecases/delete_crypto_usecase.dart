import '../repositories/crypto_repository.dart';

class DeleteCryptoUsecase {
  final CryptoRepository repository;
  DeleteCryptoUsecase(this.repository);

  Future<void> call(String cryptoId) => repository.deleteCrypto(cryptoId);
}
