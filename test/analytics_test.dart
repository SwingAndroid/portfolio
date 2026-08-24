import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/cost_basis_ledger.dart';
import 'package:crypto_portfolio/domain/analytics/xirr.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

TransactionEntity t(
  String id,
  TransactionType type,
  double qty,
  double price,
  DateTime date,
) =>
    TransactionEntity(
      id: id,
      cryptoId: 'c1',
      type: type,
      quantity: qty,
      pricePerCoin: price,
      date: date,
    );

/// Net present value at [rate] — the invariant a correct XIRR must zero out.
double npvAt(List<CashFlow> flows, double rate) {
  final start =
      flows.map((f) => f.date).reduce((a, b) => a.isBefore(b) ? a : b);
  var total = 0.0;
  for (final f in flows) {
    final years = f.date.difference(start).inSeconds / (365 * 24 * 60 * 60);
    total += f.amount / math.pow(1 + rate, years);
  }
  return total;
}

void main() {
  group('CostBasisLedger', () {
    test('a realized gain does not move when you buy more later', () async {
      // Buy 1 @ 100, sell 1 @ 150 -> a locked-in gain of 50.
      final upToSale = [
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.sell, 1, 150, DateTime(2025, 2, 1)),
      ];
      final before = CostBasisLedger.fromTransactions(upToSale);
      expect(before.realizedPnl, closeTo(50, 1e-9));

      // Months later, buy again at a much higher price. The old sale is
      // history and must not be re-scored. The previous formula recomputed it
      // against the new all-time average and reported a loss instead.
      final after = CostBasisLedger.fromTransactions([
        ...upToSale,
        t('3', TransactionType.buy, 1, 400, DateTime(2025, 6, 1)),
      ]);

      expect(after.realizedPnl, closeTo(50, 1e-9),
          reason: 'a completed sale is a fact; it cannot be rewritten');
      expect(after.remainingQuantity, closeTo(1, 1e-9));
      expect(after.avgCost, closeTo(400, 1e-9));
    });

    test('settles each sale against the average at that moment', () {
      final ledger = CostBasisLedger.fromTransactions([
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.buy, 1, 200, DateTime(2025, 2, 1)),
        // average is now 150
        t('3', TransactionType.sell, 1, 250, DateTime(2025, 3, 1)),
      ]);

      expect(ledger.realizedPnl, closeTo(100, 1e-9)); // 250 - 150
      expect(ledger.costOfSold, closeTo(150, 1e-9));
      expect(ledger.remainingQuantity, closeTo(1, 1e-9));
      expect(ledger.remainingCost, closeTo(150, 1e-9));
      expect(ledger.realizedPnlPercent, closeTo(66.6667, 1e-3));
    });

    test('a transfer out relieves basis but realizes nothing', () {
      final ledger = CostBasisLedger.fromTransactions([
        t('1', TransactionType.buy, 2, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.transferOut, 1, 500, DateTime(2025, 2, 1)),
      ]);

      expect(ledger.realizedPnl, 0,
          reason: 'moving coins out is not a disposal');
      expect(ledger.proceeds, 0, reason: 'and it is not proceeds either');
      expect(ledger.remainingQuantity, closeTo(1, 1e-9));
      expect(ledger.remainingCost, closeTo(100, 1e-9));
    });

    test('a free transfer in lowers the average cost of what is held', () {
      final ledger = CostBasisLedger.fromTransactions([
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.transferIn, 1, 0, DateTime(2025, 2, 1)),
      ]);

      expect(ledger.remainingQuantity, closeTo(2, 1e-9));
      expect(ledger.remainingCost, closeTo(100, 1e-9));
      expect(ledger.avgCost, closeTo(50, 1e-9));
      expect(ledger.unrealizedPnl(100), closeTo(100, 1e-9));
    });

    test('is independent of the order rows arrive in', () {
      final rows = [
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.buy, 1, 200, DateTime(2025, 2, 1)),
        t('3', TransactionType.sell, 1, 250, DateTime(2025, 3, 1)),
        t('4', TransactionType.buy, 1, 300, DateTime(2025, 4, 1)),
      ];
      final forward = CostBasisLedger.fromTransactions(rows);
      final reversed =
          CostBasisLedger.fromTransactions(rows.reversed.toList());

      expect(reversed.realizedPnl, closeTo(forward.realizedPnl, 1e-9));
      expect(reversed.remainingCost, closeTo(forward.remainingCost, 1e-9));
    });

    test('overselling never drives the basis negative', () {
      final ledger = CostBasisLedger.fromTransactions([
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.sell, 5, 200, DateTime(2025, 2, 1)),
      ]);

      expect(ledger.remainingCost, 0);
      expect(ledger.costOfSold, closeTo(100, 1e-9),
          reason: 'only the basis actually held can be relieved');
    });

    test('an empty history is neutral', () {
      final ledger = CostBasisLedger.fromTransactions([]);
      expect(ledger.realizedPnl, 0);
      expect(ledger.avgCost, 0);
      expect(ledger.unrealizedPnl(1000), 0);
    });
  });

  group('XIRR', () {
    test('one year, +10% -> exactly 10%', () {
      final rate = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -1000),
        CashFlow(DateTime(2026, 1, 1), 1100),
      ]);
      expect(rate, isNotNull);
      expect(rate!, closeTo(0.10, 1e-6));
    });

    test('doubling in a year is +100%', () {
      final rate = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -500),
        CashFlow(DateTime(2026, 1, 1), 1000),
      ]);
      expect(rate!, closeTo(1.0, 1e-6));
    });

    test('losing half in a year is -50%', () {
      final rate = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -1000),
        CashFlow(DateTime(2026, 1, 1), 500),
      ]);
      expect(rate!, closeTo(-0.5, 1e-6));
    });

    test('timing changes the answer, unlike a simple return', () {
      // Same money in, same money out, same total gain — but the second
      // contribution arrives much later, so the annualised rate is higher.
      final early = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -1000),
        CashFlow(DateTime(2025, 2, 1), -1000),
        CashFlow(DateTime(2026, 1, 1), 2200),
      ])!;
      final late = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -1000),
        CashFlow(DateTime(2025, 11, 1), -1000),
        CashFlow(DateTime(2026, 1, 1), 2200),
      ])!;

      expect(late, greaterThan(early),
          reason: 'capital deployed for less time earning the same profit '
              'implies a higher rate — the simple % cannot see this');
    });

    test('solves an irregular DCA schedule (NPV back to zero)', () {
      final flows = <CashFlow>[];
      var day = DateTime(2023, 1, 5);
      for (var i = 0; i < 60; i++) {
        flows.add(CashFlow(day, -(120 + (i % 7) * 35).toDouble()));
        day = day.add(Duration(days: 17 + (i % 5)));
      }
      flows.add(CashFlow(DateTime(2025, 6, 1), 4200));
      flows.add(CashFlow(DateTime(2026, 8, 24), 9800));

      final rate = computeXirr(flows);

      expect(rate, isNotNull);
      expect(npvAt(flows, rate!).abs(), lessThan(1e-4),
          reason: 'the rate must actually zero the present value');
    });

    test('returns null when there is no sign change', () {
      expect(
        computeXirr([
          CashFlow(DateTime(2025, 1, 1), -100),
          CashFlow(DateTime(2026, 1, 1), -100),
        ]),
        isNull,
      );
      expect(computeXirr([CashFlow(DateTime(2025, 1, 1), -100)]), isNull);
    });

    test('a total wipeout does not blow up the solver', () {
      final rate = computeXirr([
        CashFlow(DateTime(2025, 1, 1), -1000),
        CashFlow(DateTime(2026, 1, 1), 0.01),
      ]);
      expect(rate, isNotNull);
      expect(rate!, lessThan(-0.9));
    });
  });

  group('cashFlowsFor', () {
    CryptoEntity coinWith(List<TransactionEntity> txs, double price) =>
        CryptoEntity(
          id: 'c1',
          coinId: 'bitcoin',
          name: 'Bitcoin',
          symbol: 'BTC',
          transactions: txs,
          currentPrice: price,
        );

    test('buys are outflows, sells are inflows, value closes the series', () {
      final flows = cashFlowsFor(
        [
          coinWith([
            t('1', TransactionType.buy, 1, 1000, DateTime(2025, 1, 1)),
            t('2', TransactionType.sell, 0.5, 1500, DateTime(2025, 6, 1)),
          ], 2000)
        ],
        valuationDate: DateTime(2026, 1, 1),
      );

      expect(flows.length, 3);
      expect(flows[0].amount, -1000);
      expect(flows[1].amount, 750);
      expect(flows[2].amount, 1000, reason: '0.5 remaining at 2000');
    });

    test('zero-price transfers are not contributions', () {
      // A staking reward costs nothing, so it must not count as capital
      // deployed — it should show up purely as return.
      final flows = cashFlowsFor(
        [
          coinWith([
            t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
            t('2', TransactionType.transferIn, 5, 0, DateTime(2025, 3, 1)),
          ], 100)
        ],
        valuationDate: DateTime(2026, 1, 1),
      );

      expect(flows.length, 2, reason: 'the transfer contributes no cash flow');
      expect(flows.first.amount, -100);
      expect(flows.last.amount, 600);

      final rate = computeXirr(flows)!;
      expect(rate, greaterThan(4.0), reason: '100 in, 600 out in one year');
    });
  });

  // ── The same guarantees, seen through the entity the UI actually reads ────

  group('CryptoEntity wiring', () {
    CryptoEntity coin(List<TransactionEntity> txs, {double price = 0}) =>
        CryptoEntity(
          id: 'c1',
          coinId: 'bitcoin',
          name: 'Bitcoin',
          symbol: 'BTC',
          transactions: txs,
          currentPrice: price,
        );

    test('realized P&L stops drifting when a later buy is added', () {
      final sold = [
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.sell, 1, 150, DateTime(2025, 2, 1)),
      ];

      expect(coin(sold).realizedPnl, closeTo(50, 1e-9));
      expect(
        coin([...sold, t('3', TransactionType.buy, 1, 900, DateTime(2025, 6, 1))])
            .realizedPnl,
        closeTo(50, 1e-9),
        reason: 'the old formula turned this +50 into a large loss',
      );
    });

    test('a transfer out is not counted as proceeds', () {
      final e = coin([
        t('1', TransactionType.buy, 2, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.transferOut, 1, 500, DateTime(2025, 2, 1)),
      ]);

      expect(e.totalProceeds, 0);
      expect(e.realizedPnl, 0);
      expect(e.totalHoldings, closeTo(1, 1e-9));
    });

    test('unrealized P&L values free coins against their real basis', () {
      final e = coin([
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.transferIn, 1, 0, DateTime(2025, 2, 1)),
      ], price: 100);

      // 2 coins worth 200, basis 100.
      expect(e.unrealizedPnl, closeTo(100, 1e-9));
      expect(e.averageNetCost, closeTo(50, 1e-9));
    });

    test('avgBuyPrice still ignores transfers, for the Entry Signal', () {
      final e = coin([
        t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        t('2', TransactionType.transferIn, 9, 0, DateTime(2025, 2, 1)),
      ], price: 100);

      expect(e.avgBuyPrice, closeTo(100, 1e-9),
          reason: 'what you normally pay, not what you hold it at');
      expect(e.averageNetCost, closeTo(10, 1e-9),
          reason: 'the two metrics are deliberately different');
    });

    test('a coin with no price yields no paper gain', () {
      final e = coin([t('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1))]);
      expect(e.unrealizedPnl, 0);
      expect(e.unrealizedPnlPercent, 0);
    });
  });
}
