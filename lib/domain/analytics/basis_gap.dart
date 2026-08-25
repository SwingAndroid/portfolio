import '../entities/crypto_entity.dart';
import '../entities/price_point.dart';
import '../entities/transaction_entity.dart';
import 'price_on_date.dart';

/// Units that entered the portfolio without a recorded price.
///
/// A transfer in or a reward saved with no price sits at zero cost basis: the
/// ledger believes those coins were free. Two things go wrong. Every cent they
/// are later sold for is booked as pure gain, and any income they represented
/// — staking, an airdrop — never appears at all. The portfolio looks more
/// profitable than it was.
///
/// Naming them a "gap" rather than an error is deliberate: a transfer between
/// two wallets you own genuinely has no price of its own, and converting one
/// into income would invent earnings that never happened. Only the owner knows
/// which is which, so this reports and never decides.
class CoinBasisGaps {
  final String cryptoId;
  final String coinId;
  final String symbol;

  /// Everything currently held, gaps included, used to size the problem.
  final double totalHoldings;

  /// The priceless rows, oldest first.
  final List<TransactionEntity> transactions;

  const CoinBasisGaps({
    required this.cryptoId,
    required this.coinId,
    required this.symbol,
    required this.totalHoldings,
    required this.transactions,
  });

  int get count => transactions.length;

  double get quantity => transactions.fold(0.0, (sum, t) => sum + t.quantity);

  /// How much of what you hold rests on no recorded cost, as a percentage.
  double get shareOfHoldings =>
      totalHoldings > 0 ? quantity / totalHoldings * 100 : 0;

  DateTime get earliest => transactions.first.date;
  DateTime get latest => transactions.last.date;
}

/// Whether [t] is a holding recorded without a price.
///
/// A buy at zero is not included: that is a typo in a purchase, not an
/// acquisition whose price was never knowable, and guessing at it would
/// overwrite something the user meant to enter.
bool isBasisGap(TransactionEntity t) =>
    (t.type == TransactionType.transferIn ||
        t.type == TransactionType.reward) &&
    t.pricePerCoin <= 0;

/// Groups every priceless holding by coin, worst coverage first.
List<CoinBasisGaps> findBasisGaps(List<CryptoEntity> cryptos) {
  final out = <CoinBasisGaps>[];

  for (final crypto in cryptos) {
    final gaps = crypto.transactions.where(isBasisGap).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (gaps.isEmpty) continue;

    out.add(CoinBasisGaps(
      cryptoId: crypto.id,
      coinId: crypto.coinId,
      symbol: crypto.symbol,
      totalHoldings: crypto.totalHoldings,
      transactions: gaps,
    ));
  }

  // The coin resting most on unrecorded cost is the one worth fixing first.
  out.sort((a, b) => b.shareOfHoldings.compareTo(a.shareOfHoldings));
  return out;
}

/// A gap paired with the price found for its date.
class ResolvedGap {
  final TransactionEntity transaction;

  /// What the coin was worth that day, or null when the date is out of reach.
  ///
  /// Free price history stops at a year. A gap older than that cannot be
  /// valued and is reported as such rather than quietly filled with something
  /// convenient.
  final double? price;

  const ResolvedGap({required this.transaction, this.price});

  bool get resolvable => price != null && price! > 0;

  /// What this holding was worth when it arrived.
  double get value => resolvable ? transaction.quantity * price! : 0;

  /// The same row rewritten as income booked at the day's price.
  ///
  /// Keeps the id, so saving overwrites the original rather than leaving a
  /// duplicate behind in Hive or in the cloud.
  TransactionEntity get asReward => TransactionEntity(
        id: transaction.id,
        cryptoId: transaction.cryptoId,
        type: TransactionType.reward,
        quantity: transaction.quantity,
        pricePerCoin: price!,
        date: transaction.date,
        note: transaction.note,
        fee: transaction.fee,
        swapId: transaction.swapId,
      );
}

/// Prices every gap from a single price series.
///
/// One chart covers every date, so a coin with forty gaps still costs one
/// request rather than forty.
List<ResolvedGap> resolveGaps(
  List<TransactionEntity> gaps,
  List<PricePoint> chart,
) =>
    [
      for (final t in gaps)
        ResolvedGap(transaction: t, price: priceOnDate(chart, t.date)),
    ];

/// Total income that would be recorded by converting [gaps].
double incomeFrom(Iterable<ResolvedGap> gaps) =>
    gaps.where((g) => g.resolvable).fold(0.0, (sum, g) => sum + g.value);
