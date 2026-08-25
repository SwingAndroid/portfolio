import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/diversification.dart';
import 'package:crypto_portfolio/domain/analytics/portfolio_series.dart';
import 'package:crypto_portfolio/domain/analytics/risk_metrics.dart';
import 'package:crypto_portfolio/domain/analytics/tax_report.dart';
import 'package:crypto_portfolio/domain/analytics/xirr.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';

import 'support/portfolio_fixture.dart';

/// Guards against a change that quietly makes the app crawl on a real
/// portfolio.
///
/// The budgets sit roughly ten times above what these actually take, so they
/// catch an accidental quadratic rather than machine-to-machine noise. Every
/// figure below was measured on the full fixture, not guessed.
void main() {
  late List<dynamic> cryptos;

  setUpAll(() => cryptos = PortfolioFixture.build());

  int msFor(void Function() body) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  test('the fixture really is the size of a live portfolio', () {
    expect(PortfolioFixture.transactionCount, 454);
    expect(cryptos.length, 8);
    final total = cryptos.fold<int>(0, (s, c) => s + (c.transactions.length as int));
    expect(total, greaterThan(400));
  });

  test('a card render pass stays cheap', () {
    // Every getter a card touches, for every coin. Each rebuilds the ledger,
    // which is only acceptable because it is this fast.
    final ms = msFor(() {
      for (var i = 0; i < 10; i++) {
        for (final c in cryptos) {
          c.totalHoldings;
          c.holdingsValue;
          c.totalCost;
          c.realizedPnl;
          c.unrealizedPnl;
          c.averageNetCost;
          c.avgBuyPrice;
          c.totalProfitLossPercent;
        }
      }
    });
    expect(ms, lessThan(300), reason: '10 full passes; measured around 20ms');
  });

  test('the money-weighted return solves quickly', () {
    final ms = msFor(() => computeXirr(cashFlowsFor(cryptos.cast())));
    expect(ms, lessThan(200), reason: 'measured around 6ms');
  });

  test('the tax report and both exports stay quick', () {
    final ms = msFor(() {
      final report = TaxReport.from(cryptos.cast());
      transactionsCsv(cryptos.cast());
      disposalsCsv(report);
    });
    expect(ms, lessThan(300), reason: 'measured around 12ms');
  });

  test('rebuilding a year of daily values stays quick', () {
    final ms = msFor(() => buildDailySeries(
          cryptos: cryptos.cast(),
          from: DateTime.now().subtract(const Duration(days: 364)),
          to: DateTime.now(),
          priceAt: (_, __) => 100,
        ));
    expect(ms, lessThan(500), reason: 'measured around 28ms');
  });

  test('risk and correlation over a year stay quick', () {
    final points = [
      for (var i = 0; i < 365; i++)
        ValueSnapshot(
          date: DateTime(2025, 8, 25).add(Duration(days: i)),
          value: 20000 + i * 5,
          invested: 30000,
        )
    ];
    final series = [
      for (final c in cryptos)
        CoinSeries(
          coinId: c.coinId as String,
          symbol: c.symbol as String,
          weight: 1 / cryptos.length,
          returns: [for (var i = 0; i < 365; i++) (i % 7 - 3) / 100],
        )
    ];

    final ms = msFor(() {
      computeRiskMetrics(points);
      buildDiversificationReport(series);
    });
    expect(ms, lessThan(300));
  });
}
