import '../entities/crypto_entity.dart';
import '../repositories/crypto_repository.dart';

class AddCryptoUsecase {
  final CryptoRepository repository;
  AddCryptoUsecase(this.repository);

  Future<void> call(CryptoEntity crypto) => repository.addCrypto(crypto);
}
