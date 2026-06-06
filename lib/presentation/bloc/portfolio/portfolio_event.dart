import 'package:equatable/equatable.dart';
import '../../../domain/entities/crypto_entity.dart';
abstract class PortfolioEvent extends Equatable {
  const PortfolioEvent();
  @override
  List<Object?> get props => [];
}

class LoadPortfolioEvent extends PortfolioEvent {
  const LoadPortfolioEvent();
}

class RefreshPortfolioEvent extends PortfolioEvent {
  const RefreshPortfolioEvent();
}

class AddCryptoEvent extends PortfolioEvent {
  final CryptoEntity crypto;
  const AddCryptoEvent(this.crypto);
  @override
  List<Object?> get props => [crypto];
}

class DeleteCryptoEvent extends PortfolioEvent {
  final String cryptoId;
  const DeleteCryptoEvent(this.cryptoId);
  @override
  List<Object?> get props => [cryptoId];
}
