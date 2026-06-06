import '../repositories/crypto_repository.dart';

class GetCryptoPriceUsecase {
  final CryptoRepository repository;
  GetCryptoPriceUsecase(this.repository);

  Future<double> call(String coinId) => repository.getCryptoPrice(coinId);
}
