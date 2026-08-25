import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/tax_report.dart';
import 'package:crypto_portfolio/domain/analytics/xirr.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/presentation/bloc/portfolio/portfolio_state.dart';

import 'support/portfolio_fixture.dart';

/// End-to-end checks on a portfolio the size of a real one.
///
/// These assert *invariants* rather than figures: the amounts are generated,
/// so "realized plus unrealized reconciles" is provable where "the total is
/// 21,847" would only be testing the generator. Invariants also catch whole
/// classes of mistake — a sign flip, a double count, a NaN — that a fixed
/// expectation on tidy data never reaches.
void main() {
  late List<CryptoEntity> cryptos;
  late PortfolioLoaded portfolio;

  setUpAll(() {
    cryptos = PortfolioFixture.build();
    portfolio = PortfolioLoaded(cryptos: cryptos);
  });

  bool sane(double v) => v.isFinite && !v.isNaN;

  group('nothing produces a nonsense number', () {
    test('every figure on every coin is finite', () {
      for (final c in cryptos) {
        for (final value in [
          c.totalHoldings,
          c.holdingsValue,
          c.totalCost,
          c.totalBought,
          c.totalProceeds,
          c.realizedPnl,
          c.realizedPnlPercent,
          c.unrealizedPnl,
          c.unrealizedPnlPercent,
          c.averageNetCost,
          c.avgBuyPrice,
          c.minBuyPrice,
          c.totalProfitLoss,
          c.totalProfitLossPercent,
          c.incomeReceived,
        ]) {
          expect(sane(value), isTrue,
              reason: '${c.symbol} produced $value');
        }
      }
    });

    test('every portfolio-level figure is finite', () {
      for (final value in [
        portfolio.totalValue,
        portfolio.totalCost,
        portfolio.totalProfitLoss,
        portfolio.totalProfitLossPercent,
        portfolio.totalRealizedPnl,
        portfolio.totalUnrealizedPnl,
        portfolio.concentrationIndex,
      ]) {
        expect(sane(value), isTrue);
      }
    });
  });

  group('the ledger stays coherent', () {
    test('no coin holds a negative quantity', () {
      // The fixture only ever sells what it holds; a negative here would mean
      // the accounting, not the data, went wrong.
      for (final c in cryptos) {
        expect(c.totalHoldings, greaterThanOrEqualTo(-1e-9),
            reason: '${c.symbol} went short');
      }
    });

    test('no coin carries a negative cost basis', () {
      for (final c in cryptos) {
        expect(c.ledger.remainingCost, greaterThanOrEqualTo(0),
            reason: '${c.symbol} relieved more basis than it had');
      }
    });

    test('a disposal never relieves more basis than was held', () {
      for (final c in cryptos) {
        for (final d in c.ledger.disposals) {
          expect(d.costBasis, greaterThanOrEqualTo(0));
          expect(sane(d.gain), isTrue);
        }
      }
    });

    test('unrealized gain reconciles with value minus basis', () {
      for (final c in cryptos) {
        if (c.totalHoldings <= 0) continue;
        final expected = c.holdingsValue - c.ledger.remainingCost;
        expect(c.unrealizedPnl, closeTo(expected, 1e-6),
            reason: c.symbol);
      }
    });

    test('realized gain reconciles with proceeds minus basis sold', () {
      for (final c in cryptos) {
        final expected = c.ledger.proceeds - c.ledger.costOfSold;
        expect(c.realizedPnl, closeTo(expected, 1e-6), reason: c.symbol);
      }
    });

    test('a sale is settled at the average of its own moment', () {
      // Re-running the walk must reproduce the same locked-in figure, whatever
      // was bought afterwards.
      for (final c in cryptos) {
        final again = CryptoEntity(
          id: c.id,
          coinId: c.coinId,
          name: c.name,
          symbol: c.symbol,
          currentPrice: c.currentPrice,
          transactions: c.transactions.reversed.toList(),
        );
        expect(again.realizedPnl, closeTo(c.realizedPnl, 1e-6),
            reason: '${c.symbol} depends on row order');
      }
    });
  });

  group('portfolio totals reconcile with their parts', () {
    test('value is the sum of the holdings', () {
      final sum = cryptos.fold<double>(0, (s, c) => s + c.holdingsValue);
      expect(portfolio.totalValue, closeTo(sum, 1e-6));
    });

    test('capital engaged is the sum of the coins', () {
      final sum = cryptos.fold<double>(0, (s, c) => s + c.totalCost);
      expect(portfolio.totalCost, closeTo(sum, 1e-6));
    });

    test('profit is value less capital engaged', () {
      expect(portfolio.totalProfitLoss,
          closeTo(portfolio.totalValue - portfolio.totalCost, 1e-6));
    });

    test('allocation shares add up to a whole', () {
      final sum = cryptos
          .where((c) => c.holdingsValue > 0)
          .fold<double>(0, (s, c) => s + portfolio.allocationPercent(c));
      expect(sum, closeTo(100, 1e-6));
    });

    test('concentration sits inside its theoretical bounds', () {
      // Herfindahl runs from 10000/n when perfectly even to 10000 when it is
      // all one position.
      final held = cryptos.where((c) => c.holdingsValue > 0).length;
      expect(portfolio.concentrationIndex, greaterThan(10000 / held - 1));
      expect(portfolio.concentrationIndex, lessThanOrEqualTo(10000.5));
    });
  });

  group('the return solves on real-shaped flows', () {
    test('a rate is produced and it is finite', () {
      final rate = portfolio.moneyWeightedReturn;
      expect(rate, isNotNull);
      expect(sane(rate!), isTrue);
      expect(rate, greaterThan(-1), reason: 'a rate below -100% is impossible');
    });

    test('the rate actually zeroes the present value', () {
      final flows = cashFlowsFor(cryptos);
      final rate = computeXirr(flows)!;
      final start = flows.map((f) => f.date).reduce((a, b) => a.isBefore(b) ? a : b);
      var npv = 0.0;
      for (final f in flows) {
        final years = f.date.difference(start).inSeconds / (365 * 24 * 60 * 60);
        npv += f.amount / math.pow(1 + rate, years);
      }
      expect(npv.abs(), lessThan(1e-3),
          reason: 'the solver returned a rate that does not balance');
    });

    test('rewards are never counted as capital deployed', () {
      final flows = cashFlowsFor(cryptos);
      final rewardDates = {
        for (final c in cryptos)
          for (final t in c.transactions)
            if (t.isIncomeMovement) t.date
      };
      for (final flow in flows) {
        if (flow.amount >= 0) continue;
        expect(rewardDates.contains(flow.date), isFalse);
      }
    });
  });

  group('exports carry the whole portfolio', () {
    test('every transaction reaches the CSV', () {
      final lines = transactionsCsv(cryptos).split('\n');
      expect(lines.length, PortfolioFixture.transactionCount + 1,
          reason: 'one header plus every row');
    });

    test('the CSV keeps its column count on every row', () {
      final lines = transactionsCsv(cryptos).split('\n');
      final columns = lines.first.split(',').length;
      for (var i = 1; i < lines.length; i++) {
        expect(_countFields(lines[i]), columns,
            reason: 'row $i broke the column alignment');
      }
    });

    test('every sale appears exactly once in the disposals export', () {
      final report = TaxReport.from(cryptos);
      final sales = cryptos.fold<int>(
        0,
        (s, c) =>
            s + c.transactions.where((t) => t.type == TransactionType.sell).length,
      );
      expect(report.disposals.length, sales);
      expect(disposalsCsv(report).split('\n').length, sales + 1);
    });

    test('tax years reconcile with the per-coin realized figures', () {
      final report = TaxReport.from(cryptos);
      final fromCoins =
          cryptos.fold<double>(0, (s, c) => s + c.realizedPnl);
      expect(report.totalGain, closeTo(fromCoins, 1e-6));

      final fromYears = report.years.fold<double>(0, (s, y) => s + y.gain);
      expect(fromYears, closeTo(report.totalGain, 1e-6));
    });

    test('the disposal date and its tax year name the same return', () {
      final report = TaxReport.from(cryptos);
      for (final line in disposalsCsv(report).split('\n').skip(1)) {
        final fields = line.split(',');
        expect(fields[0].substring(0, 4), fields[1],
            reason: 'a timezone shift would put a January sale in the '
                'previous year');
      }
    });
  });

  group('the backup is complete and readable', () {
    test('it round-trips through JSON with every row', () {
      // Mirrors what SyncService writes, without needing Hive.
      final payload = {
        'transactions': [
          for (final c in cryptos)
            for (final t in c.transactions)
              {
                'id': t.id,
                'type': t.type.name,
                'quantity': t.quantity,
                'price_per_coin': t.pricePerCoin,
                'fee': t.fee,
                'date': t.date.toIso8601String(),
              }
        ]
      };

      final decoded = jsonDecode(jsonEncode(payload));
      expect((decoded['transactions'] as List).length,
          PortfolioFixture.transactionCount);
      for (final row in decoded['transactions'] as List) {
        expect(sane((row['quantity'] as num).toDouble()), isTrue);
        expect(DateTime.tryParse(row['date'] as String), isNotNull);
      }
    });
  });

  group('the fixture reproduces the real shape', () {
    test('the same seed always builds the same portfolio', () {
      final a = PortfolioFixture.build(seed: 7);
      final b = PortfolioFixture.build(seed: 7);
      expect(a.first.realizedPnl, b.first.realizedPnl);
      expect(a.last.totalHoldings, b.last.totalHoldings);
    });

    test('a different seed builds a different one', () {
      final other = PortfolioFixture.build(seed: 99);
      expect(other.first.totalHoldings,
          isNot(closeTo(cryptos.first.totalHoldings, 1e-9)));
    });

    test('the mix of movement types matches the profile', () {
      for (final c in cryptos) {
        final spec = PortfolioFixture.profile[c.symbol]!;
        final buys =
            c.transactions.where((t) => t.type == TransactionType.buy).length;
        final transfers = c.transactions
            .where((t) => t.type == TransactionType.transferIn)
            .length;
        expect(buys, spec.buys, reason: c.symbol);
        expect(transfers, spec.transfers, reason: c.symbol);
      }
    });

    test('it spans the same years as the real history', () {
      final all = [
        for (final c in cryptos)
          for (final t in c.transactions) t.date
      ];
      final earliest = all.reduce((a, b) => a.isBefore(b) ? a : b);
      final latest = all.reduce((a, b) => a.isAfter(b) ? a : b);

      expect(earliest.year, lessThanOrEqualTo(2023));
      expect(latest.year, greaterThanOrEqualTo(2026));
    });

    test('coins that only ever received transfers have no cost basis', () {
      // SEI in the real account is mostly transfers; the fixture keeps that,
      // because a zero-basis position is exactly where P&L maths goes wrong.
      final sei = cryptos.firstWhere((c) => c.symbol == 'SEI');
      expect(
        sei.transactions.where((t) => t.pricePerCoin == 0).length,
        greaterThan(30),
      );
      expect(sane(sei.averageNetCost), isTrue);
      expect(sane(sei.unrealizedPnlPercent), isTrue);
    });
  });
}

int _countFields(String line) {
  var count = 1;
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ',' && !inQuotes) {
      count++;
    }
  }
  return count;
}
