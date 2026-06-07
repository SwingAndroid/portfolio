import 'package:equatable/equatable.dart';
import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/market_data.dart';
import '../../../domain/entities/price_point.dart';
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
  final List<PricePoint>? priceHistory;
  final int chartDays;
  final bool chartLoading;

  const CryptoDetailLoaded(
    this.crypto, {
    this.marketData,
    this.priceHistory,
    this.chartDays = 90,
    this.chartLoading = false,
  });

  CryptoDetailLoaded copyWith({
    CryptoEntity? crypto,
    MarketData? marketData,
    List<PricePoint>? priceHistory,
    int? chartDays,
    bool? chartLoading,
  }) {
    return CryptoDetailLoaded(
      crypto ?? this.crypto,
      marketData: marketData ?? this.marketData,
      priceHistory: priceHistory ?? this.priceHistory,
      chartDays: chartDays ?? this.chartDays,
      chartLoading: chartLoading ?? this.chartLoading,
    );
  }

  @override
  List<Object?> get props =>
      [crypto, marketData, priceHistory, chartDays, chartLoading];
}

class CryptoDetailError extends CryptoDetailState {
  final String message;
  const CryptoDetailError(this.message);
  @override
  List<Object?> get props => [message];
}
