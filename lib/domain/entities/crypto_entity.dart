import 'package:equatable/equatable.dart';
import '../analytics/cost_basis_ledger.dart';
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

  /// Capital engaged: everything paid in, less everything taken out.
  ///
  /// Fees count, because they were paid. Rewards do not, because they were
  /// not — see [TransactionEntity.capitalIn].
  double get totalCost {
    return transactions.fold(0.0, (sum, t) {
      if (t.type.addsHoldings) return sum + t.capitalIn;
      return sum - t.netProceeds;
    });
  }

  /// Value of everything received as staking or airdrop income.
  double get incomeReceived => ledger.income;

  double get totalBought {
    return transactions
        .where((t) => t.type.addsHoldings)
        .fold(0.0, (sum, t) => sum + (t.quantity * t.pricePerCoin));
  }

  /// Cash actually received from sales. Transfers out move coins without
  /// selling them, so they are not proceeds.
  double get totalProceeds => ledger.proceeds;

  double get totalBoughtQuantity {
    return transactions
        .where((t) => t.type.addsHoldings)
        .fold(0.0, (sum, t) => sum + t.quantity);
  }

  /// Average cost of a unit still held, transfers included — so a coin
  /// received for nothing genuinely pulls it down.
  double get averageNetCost => ledger.avgCost;

  // ── Realized / Unrealized P&L ─────────────────────────────────────────────

  /// Chronological cost-basis walk. Every P&L figure derives from this so a
  /// past sale is settled at the average that applied on its own date and
  /// stays put afterwards.
  CostBasisLedger get ledger => CostBasisLedger.fromTransactions(transactions);

  /// Weighted-average price paid across actual buy transactions (no transfers).
  ///
  /// Deliberately distinct from [averageNetCost]: this answers "what do I
  /// normally pay for this coin", which is what the Entry Signal compares
  /// today's price against, and what the chart draws as your cost line.
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

  /// Profit/loss locked in by completed sales. Once a sale has happened this
  /// number no longer moves, whatever you buy afterwards.
  double get realizedPnl => ledger.realizedPnl;

  double get realizedPnlPercent => ledger.realizedPnlPercent;

  /// Paper gain/loss on the units still held, against their actual basis.
  double get unrealizedPnl {
    if (currentPrice == 0) return 0;
    return ledger.unrealizedPnl(currentPrice);
  }

  double get unrealizedPnlPercent {
    if (currentPrice == 0) return 0;
    return ledger.unrealizedPnlPercent(currentPrice);
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
