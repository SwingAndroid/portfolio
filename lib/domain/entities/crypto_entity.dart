import 'package:equatable/equatable.dart';
import 'transaction_entity.dart'; // also imports TransactionType

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
      return t.type.addsHoldings ? sum + t.quantity : sum - t.quantity;
    });
  }

  double get holdingsValue => totalHoldings * currentPrice;

  double get totalCost {
    return transactions.fold(0.0, (sum, t) {
      if (t.type.addsHoldings) return sum + (t.quantity * t.pricePerCoin);
      return sum - (t.quantity * t.pricePerCoin);
    });
  }

  double get totalBought {
    return transactions
        .where((t) => t.type.addsHoldings)
        .fold(0.0, (sum, t) => sum + (t.quantity * t.pricePerCoin));
  }

  double get totalProceeds {
    return transactions
        .where((t) => t.type.removesHoldings)
        .fold(0.0, (sum, t) => sum + (t.quantity * t.pricePerCoin));
  }

  double get totalBoughtQuantity {
    return transactions
        .where((t) => t.type.addsHoldings)
        .fold(0.0, (sum, t) => sum + t.quantity);
  }

  /// (Total cost − Total proceeds) / Current holdings
  double get averageNetCost {
    if (totalHoldings <= 0) return 0;
    return (totalBought - totalProceeds) / totalHoldings;
  }

  // ── Realized / Unrealized P&L ─────────────────────────────────────────────

  /// Weighted-average price paid across actual buy transactions (no transfers).
  double get avgBuyPrice {
    final buys = transactions.where((t) => t.type == TransactionType.buy);
    final totalQty = buys.fold(0.0, (s, t) => s + t.quantity);
    if (totalQty == 0) return 0;
    final totalSpent = buys.fold(0.0, (s, t) => s + t.quantity * t.pricePerCoin);
    return totalSpent / totalQty;
  }

  /// Total quantity sold across all sell transactions.
  double get totalSoldQuantity {
    return transactions
        .where((t) => t.type == TransactionType.sell)
        .fold(0.0, (s, t) => s + t.quantity);
  }

  /// Profit/loss already locked in from completed sell transactions.
  /// realizedPnl = proceeds − (soldQty × avgBuyPrice)
  double get realizedPnl {
    if (avgBuyPrice == 0) return 0;
    return totalProceeds - (totalSoldQuantity * avgBuyPrice);
  }

  double get realizedPnlPercent {
    final cost = totalSoldQuantity * avgBuyPrice;
    if (cost == 0) return 0;
    return (realizedPnl / cost) * 100;
  }

  /// Paper gain/loss on holdings still held.
  /// unrealizedPnl = currentValue − (holdingsQty × avgBuyPrice)
  double get unrealizedPnl {
    if (currentPrice == 0 || avgBuyPrice == 0) return 0;
    return holdingsValue - (totalHoldings * avgBuyPrice);
  }

  double get unrealizedPnlPercent {
    final cost = totalHoldings * avgBuyPrice;
    if (cost == 0) return 0;
    return (unrealizedPnl / cost) * 100;
  }

  /// Lowest price paid across all buy transactions (transfers excluded).
  double get minBuyPrice {
    final prices = transactions
        .where((t) => t.type == TransactionType.buy && t.pricePerCoin > 0)
        .map((t) => t.pricePerCoin)
        .toList();
    if (prices.isEmpty) return 0;
    return prices.reduce((a, b) => a < b ? a : b);
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
