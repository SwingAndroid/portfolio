import '../entities/transaction_entity.dart';

/// Chronological moving-average (AVCO) cost basis for one coin.
///
/// Replaces the previous formula, which computed realized P&L as
/// `proceeds − soldQty × avgBuyPrice` where `avgBuyPrice` averaged **every**
/// buy ever made — including buys placed *after* a sale. That made a realized
/// gain drift every time a new buy was recorded, even though a completed sale
/// is a historical fact that must never move again.
///
/// Here each sale is settled against the average cost as it stood *at that
/// moment*, and the result is locked in.
class CostBasisLedger {
  /// Gains locked in by completed sales. Stable once a sale has happened.
  final double realizedPnl;

  /// Cash received from sales. Transfers out are not sales and are excluded.
  final double proceeds;

  /// Cost basis attributed to the units that were sold.
  final double costOfSold;

  /// Units still held.
  final double remainingQuantity;

  /// Cost basis still tied up in the units held.
  final double remainingCost;

  const CostBasisLedger({
    required this.realizedPnl,
    required this.proceeds,
    required this.costOfSold,
    required this.remainingQuantity,
    required this.remainingCost,
  });

  static const empty = CostBasisLedger(
    realizedPnl: 0,
    proceeds: 0,
    costOfSold: 0,
    remainingQuantity: 0,
    remainingCost: 0,
  );

  /// Average cost of a unit still held. Unlike `avgBuyPrice` this includes
  /// units received as transfers, so a free coin genuinely lowers it.
  double get avgCost =>
      remainingQuantity > 0 ? remainingCost / remainingQuantity : 0;

  double get realizedPnlPercent =>
      costOfSold > 0 ? (realizedPnl / costOfSold) * 100 : 0;

  /// Paper gain on the units still held, given [currentPrice].
  double unrealizedPnl(double currentPrice) {
    if (remainingQuantity <= 0) return 0;
    return remainingQuantity * currentPrice - remainingCost;
  }

  double unrealizedPnlPercent(double currentPrice) {
    if (remainingCost <= 0) return 0;
    return (unrealizedPnl(currentPrice) / remainingCost) * 100;
  }

  factory CostBasisLedger.fromTransactions(List<TransactionEntity> txs) {
    if (txs.isEmpty) return empty;

    // Chronological order is what makes the result stable. Ties break on id so
    // two transactions stamped at the same instant always settle the same way.
    final ordered = [...txs]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    var qty = 0.0;
    var cost = 0.0;
    var realized = 0.0;
    var proceeds = 0.0;
    var costOfSold = 0.0;

    for (final t in ordered) {
      switch (t.type) {
        case TransactionType.buy:
        case TransactionType.transferIn:
          qty += t.quantity;
          // The fee is part of what acquiring these units cost.
          cost += t.grossCost;

        case TransactionType.sell:
          final avg = qty > 0 ? cost / qty : 0.0;
          // Selling more than the ledger holds means the history is
          // incomplete. Relieve only what is actually there rather than
          // letting the basis go negative.
          final relieved = t.quantity < qty ? t.quantity : qty;
          final basis = relieved * avg;

          // Proceeds are what actually landed, after the fee.
          proceeds += t.netProceeds;
          costOfSold += basis;
          realized += t.netProceeds - basis;

          cost -= basis;
          qty -= t.quantity;

        case TransactionType.transferOut:
          // Moving coins elsewhere is not a disposal: it relieves basis but
          // realizes nothing. Counting it as proceeds was the latent bug.
          // Any network fee recorded here is a sunk expense outside the
          // position, so it does not touch the basis of what remains.
          final avg = qty > 0 ? cost / qty : 0.0;
          final relieved = t.quantity < qty ? t.quantity : qty;
          cost -= relieved * avg;
          qty -= t.quantity;
      }
    }

    return CostBasisLedger(
      realizedPnl: realized,
      proceeds: proceeds,
      costOfSold: costOfSold,
      remainingQuantity: qty,
      remainingCost: cost < 0 ? 0 : cost,
    );
  }
}
