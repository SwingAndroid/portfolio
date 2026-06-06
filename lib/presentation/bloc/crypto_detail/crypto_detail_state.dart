import 'package:equatable/equatable.dart';
import '../../../domain/entities/crypto_entity.dart';
abstract class CryptoDetailState extends Equatable {
  const CryptoDetailState();
  @override
  List<Object?> get props => [];
}

class CryptoDetailInitial extends CryptoDetailState {
  const CryptoDetailInitial();
}

class CryptoDetailLoading extends CryptoDetailState {
  const CryptoDetailLoading();
}

class CryptoDetailLoaded extends CryptoDetailState {
  final CryptoEntity crypto;

  const CryptoDetailLoaded(this.crypto);

  @override
  List<Object?> get props => [crypto];
}

class CryptoDetailError extends CryptoDetailState {
  final String message;
  const CryptoDetailError(this.message);
  @override
  List<Object?> get props => [message];
}
