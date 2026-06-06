import 'package:equatable/equatable.dart';
import '../../../domain/entities/crypto_entity.dart';

abstract class PortfolioState extends Equatable {
  const PortfolioState();
  @override
  List<Object?> get props => [];
}

class PortfolioInitial extends PortfolioState {
  const PortfolioInitial();
}

class PortfolioLoading extends PortfolioState {
  const PortfolioLoading();
}

class PortfolioLoaded extends PortfolioState {
  final List<CryptoEntity> cryptos;
  final bool isRefreshing;

  const PortfolioLoaded({required this.cryptos, this.isRefreshing = false});

  double get totalValue => cryptos.fold(0, (sum, c) => sum + c.holdingsValue);
  double get totalCost => cryptos.fold(0, (sum, c) => sum + c.totalCost);
  double get totalProfitLoss => totalValue - totalCost;
  double get totalProfitLossPercent {
    if (totalCost == 0) return 0;
    return (totalProfitLoss / totalCost) * 100;
  }

  PortfolioLoaded copyWith({List<CryptoEntity>? cryptos, bool? isRefreshing}) {
    return PortfolioLoaded(
      cryptos: cryptos ?? this.cryptos,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }

  @override
  List<Object?> get props => [cryptos, isRefreshing];
}

class PortfolioError extends PortfolioState {
  final String message;
  const PortfolioError(this.message);
  @override
  List<Object?> get props => [message];
}
