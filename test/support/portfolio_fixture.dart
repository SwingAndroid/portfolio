import 'dart:math' as math;

import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

/// A portfolio built to the same shape as a real one in production.
///
/// The counts, the mix of movement types and the date span are copied from a
/// live account; the amounts are generated. Testing against three tidy
/// transactions proves nothing about 454 messy ones, but publishing somebody's
/// financial history to a public repository to get that realism is not a
/// trade worth making.
///
/// Deterministic: the same seed always yields the same portfolio, so a failure
/// can be reproduced exactly.
class PortfolioFixture {
  /// Per coin: total, buys, sells, transfers in. Taken from a real account.
  static const profile = <String, ({
    String coinId,
    int buys,
    int sells,
    int transfers,
  })>{
    'AAVE': (coinId: 'aave', buys: 113, sells: 19, transfers: 0),
    'APT': (coinId: 'aptos', buys: 72, sells: 1, transfers: 17),
    'BNB': (coinId: 'binancecoin', buys: 16, sells: 3, transfers: 13),
    'BTC': (coinId: 'bitcoin', buys: 7, sells: 1, transfers: 8),
    'ETH': (coinId: 'ethereum', buys: 31, sells: 1, transfers: 0),
    'QNT': (coinId: 'quant-network', buys: 35, sells: 7, transfers: 0),
    'SEI': (coinId: 'sei-network', buys: 15, sells: 0, transfers: 37),
    'SOL': (coinId: 'solana', buys: 33, sells: 17, transfers: 8),
  };

  /// Roughly the price scale of each coin, so quantities and totals land in
  /// believable ranges rather than all being order-of-one.
  static const _priceScale = <String, double>{
    'AAVE': 130,
    'APT': 0.6,
    'BNB': 700,
    'BTC': 80000,
    'ETH': 2500,
    'QNT': 65,
    'SEI': 0.05,
    'SOL': 100,
  };

  static final first = DateTime(2022, 3, 15);
  static final last = DateTime(2026, 8, 17);

  static int get transactionCount => profile.values
      .fold(0, (s, p) => s + p.buys + p.sells + p.transfers);

  /// Builds the portfolio. [seed] fixes the amounts.
  static List<CryptoEntity> build({int seed = 42}) {
    final rng = math.Random(seed);
    final span = last.difference(first).inDays;
    final out = <CryptoEntity>[];

    profile.forEach((symbol, spec) {
      final scale = _priceScale[symbol]!;
      final txs = <TransactionEntity>[];
      var n = 0;

      void add(TransactionType type, {required bool priced}) {
        // Buys cluster in the later two thirds, as a position built up over
        // time does; sales scatter.
        final bias = type == TransactionType.buy ? 0.35 : 0.0;
        final at = first.add(Duration(
          days: (span * (bias + rng.nextDouble() * (1 - bias))).round(),
          hours: rng.nextInt(24),
          minutes: rng.nextInt(60),
        ));
        // Price drifts +/-40% around the scale across the history.
        final price = scale * (0.6 + rng.nextDouble() * 0.8);
        final spend = 50 + rng.nextDouble() * 450;

        txs.add(TransactionEntity(
          id: '$symbol-${n++}',
          cryptoId: 'c-$symbol',
          type: type,
          // A transfer carries no price, but its size must still make sense
          // for the coin: eight transfers of "5 units" is pocket change in SEI
          // and several million dollars in BTC.
          quantity: priced ? spend / price : (10 + rng.nextDouble() * 90) / price,
          pricePerCoin: priced ? price : 0,
          date: at,
          fee: rng.nextInt(4) == 0 ? spend * 0.002 : 0,
        ));
      }

      for (var i = 0; i < spec.buys; i++) {
        add(TransactionType.buy, priced: true);
      }
      for (var i = 0; i < spec.transfers; i++) {
        add(TransactionType.transferIn, priced: false);
      }

      // Sales come last, each dated after something was actually acquired and
      // sized against what was held *on that date*. Generating them freely
      // produced a portfolio whose first movement was a sale — which no real
      // account can do, and which leaves the return mathematically unsolvable
      // because the earliest flow is then an inflow.
      if (txs.isNotEmpty) {
        final earliest =
            txs.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);
        final room = last.difference(earliest).inDays;

        for (var i = 0; i < spec.sells; i++) {
          if (room <= 1) break;
          final at = earliest.add(Duration(days: 1 + rng.nextInt(room - 1)));
          final heldThen = txs
              .where((t) => !t.date.isAfter(at))
              .fold<double>(
                0,
                (s, t) => t.type.addsHoldings ? s + t.quantity : s - t.quantity,
              );
          if (heldThen <= 0) continue;

          txs.add(TransactionEntity(
            id: '$symbol-sell-${n++}',
            cryptoId: 'c-$symbol',
            type: TransactionType.sell,
            quantity: heldThen * (0.05 + rng.nextDouble() * 0.25),
            pricePerCoin: scale * (0.6 + rng.nextDouble() * 0.8),
            date: at,
            fee: 0,
          ));
        }
      }

      txs.sort((a, b) => a.date.compareTo(b.date));

      out.add(CryptoEntity(
        id: 'c-$symbol',
        coinId: spec.coinId,
        name: symbol,
        symbol: symbol,
        currentPrice: scale,
        transactions: txs,
      ));
    });

    return out;
  }
}
