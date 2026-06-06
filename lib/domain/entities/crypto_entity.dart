import 'package:equatable/equatable.dart';
import 'transaction_entity.dart';

class CryptoEntity extends Equatable {
  final String id;
  final String coinId;
  final String name;
  final String symbol;
  final String? imageUrl;
  final List<TransactionEntity> transactions;
  final double currentPrice;
  final double priceChangePercent24h;

  const CryptoEntity({
    required this.id,
    required this.coinId,
    required this.name,
    required this.symbol,
    this.imageUrl,
    required this.transactions,
    this.currentPrice = 0,
    this.priceChangePercent24h = 0,
  });

  double get totalHoldings {
    return transactions.fold(0.0, (sum, t) {
      return t.type == TransactionType.buy ? sum + t.quantity : sum - t.quantity;
    });
  }

  double get holdingsValue => totalHoldings * currentPrice;

  double get totalCost {
    return transactions.fold(0.0, (sum, t) {
      if (t.type == TransactionType.buy) return sum + (t.quantity * t.pricePerCoin);
      return sum - (t.quantity * t.pricePerCoin);
    });
  }

  double get totalBought {
    return transactions
        .where((t) => t.type == TransactionType.buy)
        .fold(0.0, (sum, t) => sum + (t.quantity * t.pricePerCoin));
  }

  double get totalBoughtQuantity {
    return transactions
        .where((t) => t.type == TransactionType.buy)
        .fold(0.0, (sum, t) => sum + t.quantity);
  }

  double get averageNetCost {
    if (totalBoughtQuantity == 0) return 0;
    return totalBought / totalBoughtQuantity;
  }

  double get totalProfitLoss => holdingsValue - totalCost;

  double get totalProfitLossPercent {
    if (totalCost == 0) return 0;
    return (totalProfitLoss / totalCost) * 100;
  }

  CryptoEntity copyWith({
    String? id,
    String? coinId,
    String? name,
    String? symbol,
    String? imageUrl,
    List<TransactionEntity>? transactions,
    double? currentPrice,
    double? priceChangePercent24h,
  }) {
    return CryptoEntity(
      id: id ?? this.id,
      coinId: coinId ?? this.coinId,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      imageUrl: imageUrl ?? this.imageUrl,
      transactions: transactions ?? this.transactions,
      currentPrice: currentPrice ?? this.currentPrice,
      priceChangePercent24h: priceChangePercent24h ?? this.priceChangePercent24h,
    );
  }

  @override
  List<Object?> get props => [id, coinId, name, symbol, imageUrl, transactions, currentPrice, priceChangePercent24h];
}
