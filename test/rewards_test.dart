import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/cost_basis_ledger.dart';
import 'package:crypto_portfolio/domain/analytics/portfolio_series.dart';
import 'package:crypto_portfolio/domain/analytics/tax_report.dart';
import 'package:crypto_portfolio/domain/analytics/xirr.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

TransactionEntity tx(
  String id,
  TransactionType type,
  double qty,
  double price,
  DateTime date, {
  double fee = 0,
}) =>
    TransactionEntity(
      id: id,
      cryptoId: 'c1',
      type: type,
      quantity: qty,
      pricePerCoin: price,
      date: date,
      fee: fee,
    );

CryptoEntity coin(List<TransactionEntity> txs, {double price = 0}) =>
    CryptoEntity(
      id: 'c1',
      coinId: 'sei-network',
      name: 'Sei',
      symbol: 'SEI',
      currentPrice: price,
      transactions: txs,
    );

void main() {
  // ── The storage contract ──────────────────────────────────────────────────

  group('enum layout', () {
    test('existing indices are untouched by the new value', () {
      // Hive stores the index, not the name. Anything but appending would
      // silently reinterpret all 454 stored transactions.
      expect(TransactionType.buy.index, 0);
      expect(TransactionType.sell.index, 1);
      expect(TransactionType.transferIn.index, 2);
      expect(TransactionType.transferOut.index, 3);
      expect(TransactionType.reward.index, 4);
    });

    test('a reward increases holdings and is not a transfer', () {
      expect(TransactionType.reward.addsHoldings, isTrue);
      expect(TransactionType.reward.removesHoldings, isFalse);
      expect(TransactionType.reward.isTransfer, isFalse);
      expect(TransactionType.reward.isIncome, isTrue);
    });
  });

  // ── Capital engaged is not the same as cost basis ─────────────────────────

  group('capital versus basis', () {
    test('a reward has a basis but costs no capital', () {
      final reward =
          tx('1', TransactionType.reward, 10, 2, DateTime(2026, 1, 1));

      expect(reward.grossCost, closeTo(20, 1e-9),
          reason: 'what a later sale is measured against');
      expect(reward.capitalIn, 0, reason: 'no money left your pocket');
      expect(reward.incomeValue, closeTo(20, 1e-9));
    });

    test('a buy puts in exactly what it cost', () {
      final buy = tx('1', TransactionType.buy, 10, 2, DateTime(2026, 1, 1),
          fee: 1);
      expect(buy.capitalIn, closeTo(21, 1e-9));
      expect(buy.incomeValue, 0);
    });

    test('capital engaged ignores rewards entirely', () {
      final entity = coin([
        tx('1', TransactionType.buy, 10, 10, DateTime(2026, 1, 1)),
        tx('2', TransactionType.reward, 5, 10, DateTime(2026, 2, 1)),
      ], price: 10);

      expect(entity.totalCost, closeTo(100, 1e-9),
          reason: 'counting the reward would invent 50 of deployed capital');
      expect(entity.totalHoldings, closeTo(15, 1e-9));
      expect(entity.totalProfitLoss, closeTo(50, 1e-9),
          reason: '150 held against 100 put in');
    });

    test('the capital line over time never rises on a reward', () {
      final map = investedByDay(
        cryptos: [
          coin([
            tx('1', TransactionType.buy, 10, 10, DateTime(2026, 1, 1)),
            tx('2', TransactionType.reward, 5, 10, DateTime(2026, 1, 3)),
          ])
        ],
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 4),
      );

      expect(map['2026-01-01'], closeTo(100, 1e-9));
      expect(map['2026-01-04'], closeTo(100, 1e-9),
          reason: 'free coins are return, not contribution');
    });

    test('a reward is not a cash flow in the return calculation', () {
      final flows = cashFlowsFor(
        [
          coin([
            tx('1', TransactionType.buy, 10, 10, DateTime(2026, 1, 1)),
            tx('2', TransactionType.reward, 5, 10, DateTime(2026, 6, 1)),
          ], price: 10)
        ],
        valuationDate: DateTime(2027, 1, 1),
      );

      expect(flows.length, 2, reason: 'the buy and the closing valuation');
      expect(flows.first.amount, closeTo(-100, 1e-9));
      expect(flows.last.amount, closeTo(150, 1e-9));

      final rate = computeXirr(flows)!;
      expect(rate, greaterThan(0.4),
          reason: 'free coins raise the return; booking them as capital '
              'deployed would have crushed it');
    });
  });

  // ── Ledger ────────────────────────────────────────────────────────────────

  group('cost basis of income', () {
    test('a reward is banked at its value on arrival', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.reward, 10, 3, DateTime(2026, 1, 1)),
      ]);

      expect(ledger.remainingQuantity, closeTo(10, 1e-9));
      expect(ledger.remainingCost, closeTo(30, 1e-9));
      expect(ledger.income, closeTo(30, 1e-9));
    });

    test('selling a reward is only taxed on the move since receipt', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.reward, 10, 3, DateTime(2026, 1, 1)),
        tx('2', TransactionType.sell, 10, 5, DateTime(2026, 6, 1)),
      ]);

      expect(ledger.realizedPnl, closeTo(20, 1e-9),
          reason: 'a zero basis would tax the same coins twice — once as '
              'income, then again as pure gain');
      expect(ledger.income, closeTo(30, 1e-9));
    });

    test('a reward blends into the running average like any acquisition', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.buy, 10, 10, DateTime(2026, 1, 1)),
        tx('2', TransactionType.reward, 10, 0, DateTime(2026, 2, 1)),
      ]);

      expect(ledger.avgCost, closeTo(5, 1e-9),
          reason: '100 of basis spread over 20 coins');
      expect(ledger.income, 0, reason: 'valued at nothing, so nothing earned');
    });

    test('income does not appear as a disposal', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.reward, 10, 3, DateTime(2026, 1, 1)),
      ]);
      expect(ledger.disposals, isEmpty);
    });
  });

  // ── Tax report ────────────────────────────────────────────────────────────

  group('income in the tax report', () {
    test('is grouped by year and kept apart from gains', () {
      final report = TaxReport.from([
        coin([
          tx('1', TransactionType.buy, 10, 10, DateTime(2025, 1, 1)),
          tx('2', TransactionType.reward, 2, 12, DateTime(2025, 6, 1)),
          tx('3', TransactionType.reward, 3, 8, DateTime(2026, 3, 1)),
          tx('4', TransactionType.sell, 5, 20, DateTime(2026, 5, 1)),
        ]),
      ]);

      final y2025 = report.years.firstWhere((y) => y.year == 2025);
      expect(y2025.income, closeTo(24, 1e-9));
      expect(y2025.incomeCount, 1);
      expect(y2025.disposalCount, 0);
      expect(y2025.gain, 0);

      final y2026 = report.years.firstWhere((y) => y.year == 2026);
      expect(y2026.incomeCount, 1);
      expect(y2026.income, closeTo(24, 1e-9));
      expect(y2026.disposalCount, 1);
      expect(y2026.gain, greaterThan(0));
      expect(y2026.total, closeTo(y2026.gain + y2026.income, 1e-9));
    });

    test('a year with income but no sale still shows up', () {
      final report = TaxReport.from([
        coin([tx('1', TransactionType.reward, 5, 4, DateTime(2026, 2, 1))]),
      ]);

      expect(report.isEmpty, isFalse);
      expect(report.years.single.year, 2026);
      expect(report.years.single.income, closeTo(20, 1e-9));
      expect(report.totalIncome, closeTo(20, 1e-9));
      expect(report.disposals, isEmpty);
    });

    test('rewards reach the transactions export', () {
      final csv = transactionsCsv([
        coin([tx('1', TransactionType.reward, 5, 4, DateTime(2026, 2, 1))]),
      ]);

      expect(csv, contains('reward'));
      expect(csv.split('\n')[1], contains('SEI'));
    });

    test('a portfolio with neither sales nor rewards is empty', () {
      final report = TaxReport.from([
        coin([tx('1', TransactionType.buy, 1, 100, DateTime(2026, 1, 1))]),
      ]);
      expect(report.isEmpty, isTrue);
    });
  });
}
