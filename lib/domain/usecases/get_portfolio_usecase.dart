import '../entities/crypto_entity.dart';
import '../repositories/crypto_repository.dart';

class GetPortfolioUsecase {
  final CryptoRepository repository;
  GetPortfolioUsecase(this.repository);

  Future<List<CryptoEntity>> call() => repository.getPortfolio();
}
