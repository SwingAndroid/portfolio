import 'package:equatable/equatable.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/market_data.dart';
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
  final MarketData? marketData;

  const CryptoDetailLoaded(this.crypto, {this.marketData});

  CryptoDetailLoaded copyWith({CryptoEntity? crypto, MarketData? marketData}) {
    return CryptoDetailLoaded(
      crypto ?? this.crypto,
      marketData: marketData ?? this.marketData,
    );
  }

  @override
  List<Object?> get props => [crypto, marketData];
}

class CryptoDetailError extends CryptoDetailState {
  final String message;
  const CryptoDetailError(this.message);
  @override
  List<Object?> get props => [message];
}
