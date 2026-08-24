import 'package:equatable/equatable.dart';
import '../../../domain/analytics/xirr.dart';
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

  PortfolioLoaded({required this.cryptos, this.isRefreshing = false});

  /// Money-weighted annualised return across every dated cash flow.
  ///
  /// `late final` so the solver runs once per state, not on every rebuild:
  /// hundreds of flows through Newton-Raphson is cheap but not free.
  /// Null when the flows cannot define a rate (nothing invested yet, or no
  /// realised value to discount against).
  late final double? moneyWeightedReturn =
      computeXirr(cashFlowsFor(cryptos));

  /// When the tracked history starts — the horizon the return is annualised
  /// over, which the headline percentage silently hides.
  DateTime? get firstTransactionDate {
    DateTime? first;
    for (final c in cryptos) {
      for (final t in c.transactions) {
        if (first == null || t.date.isBefore(first)) first = t.date;
      }
    }
    return first;
  }

  /// Herfindahl index of the allocation (0-10000). Above 2500 is generally
  /// read as a concentrated book.
  double get concentrationIndex {
    if (totalValue <= 0) return 0;
    return cryptos.fold<double>(0, (sum, c) {
      final weight = allocationPercent(c);
      return sum + weight * weight;
    });
  }

  double get totalValue => cryptos.fold(0, (sum, c) => sum + c.holdingsValue);
  double get totalCost  => cryptos.fold(0, (sum, c) => sum + c.totalCost);
  double get totalProfitLoss => totalValue - totalCost;
  double get totalProfitLossPercent {
    if (totalCost == 0) return 0;
    return (totalProfitLoss / totalCost) * 100;
  }

  int get numAssets => cryptos.length;

  double get totalRealizedPnl =>
      cryptos.fold(0, (sum, c) => sum + c.realizedPnl);
  double get totalUnrealizedPnl =>
      cryptos.fold(0, (sum, c) => sum + c.unrealizedPnl);

  CryptoEntity? get bestPerformer {
    if (cryptos.isEmpty) return null;
    return cryptos.reduce((a, b) =>
        a.totalProfitLossPercent > b.totalProfitLossPercent ? a : b);
  }

  CryptoEntity? get worstPerformer {
    if (cryptos.isEmpty) return null;
    return cryptos.reduce((a, b) =>
        a.totalProfitLossPercent < b.totalProfitLossPercent ? a : b);
  }

  double allocationPercent(CryptoEntity c) {
    if (totalValue == 0) return 0;
    return (c.holdingsValue / totalValue) * 100;
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
