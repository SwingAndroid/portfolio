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

/// Why a detail request failed. Drives the message shown on the card.
enum DetailFailure {
  /// CoinGecko no longer knows this coin id and we could not find a
  /// replacement — the entry needs to be re-added.
  coinNotFound,

  /// Network error, timeout, rate limit or server error. Worth retrying.
  network,
}

class CryptoDetailLoaded extends CryptoDetailState {
  final CryptoEntity crypto;
  final MarketData? marketData;
  final List<PricePoint>? priceHistory;
  final int chartDays;
  final bool chartLoading;

  /// Set when the price-history request failed, so the card can say so
  /// instead of silently removing itself.
  final DetailFailure? chartError;

  /// Set when the `/coins/{id}` market-data request failed. The Entry Signal
  /// falls back to cost-basis-only scoring when this is non-null.
  final DetailFailure? marketDataError;

  /// Non-null after a stale coin id was detected and corrected — holds the
  /// previous id so the UI can explain what happened.
  final String? repairedFromCoinId;

  const CryptoDetailLoaded(
    this.crypto, {
    this.marketData,
    this.priceHistory,
    this.chartDays = 90,
    this.chartLoading = false,
    this.chartError,
    this.marketDataError,
    this.repairedFromCoinId,
  });

  CryptoDetailLoaded copyWith({
    CryptoEntity? crypto,
    MarketData? marketData,
    List<PricePoint>? priceHistory,
    int? chartDays,
    bool? chartLoading,
    DetailFailure? chartError,
    DetailFailure? marketDataError,
    String? repairedFromCoinId,
    bool clearChartError = false,
    bool clearMarketDataError = false,
  }) {
    return CryptoDetailLoaded(
      crypto ?? this.crypto,
      marketData: marketData ?? this.marketData,
      priceHistory: priceHistory ?? this.priceHistory,
      chartDays: chartDays ?? this.chartDays,
      chartLoading: chartLoading ?? this.chartLoading,
      chartError: clearChartError ? null : (chartError ?? this.chartError),
      marketDataError: clearMarketDataError
          ? null
          : (marketDataError ?? this.marketDataError),
      repairedFromCoinId: repairedFromCoinId ?? this.repairedFromCoinId,
    );
  }

  @override
  List<Object?> get props => [
        crypto,
        marketData,
        priceHistory,
        chartDays,
        chartLoading,
        chartError,
        marketDataError,
        repairedFromCoinId,
      ];
}

class CryptoDetailError extends CryptoDetailState {
  final String message;
  const CryptoDetailError(this.message);
  @override
  List<Object?> get props => [message];
}
