import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/core/theme/app_theme.dart';
import 'package:crypto_portfolio/data/services/benchmark_service.dart';
import 'package:crypto_portfolio/data/services/diversification_service.dart';
import 'package:crypto_portfolio/domain/analytics/benchmark.dart';
import 'package:crypto_portfolio/domain/analytics/diversification.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/presentation/bloc/benchmark/benchmark_cubit.dart';
import 'package:crypto_portfolio/presentation/bloc/diversification/diversification_cubit.dart';
import 'package:crypto_portfolio/presentation/bloc/portfolio/portfolio_state.dart';
import 'package:crypto_portfolio/presentation/widgets/benchmark_card.dart';
import 'package:crypto_portfolio/presentation/widgets/diversification_card.dart';
import 'package:crypto_portfolio/presentation/widgets/performance_card.dart';
import 'package:crypto_portfolio/presentation/widgets/transaction_tile.dart';

import 'support/portfolio_fixture.dart';

/// Render tests for the cards.
///
/// Every other suite proves the arithmetic; none of them proves anything
/// reaches the screen. A divide-by-zero in a label, an overflow on a narrow
/// phone or a state that renders a permanent spinner are all invisible to a
/// unit test and obvious to a user.
void main() {
  late List<CryptoEntity> cryptos;

  setUpAll(() => cryptos = PortfolioFixture.build());

  /// Cards live inside a scrolling column on a phone-width screen.
  Widget host(Widget child, {double width = 375}) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  Future<void> expectNoOverflow(WidgetTester tester) async {
    // Flutter reports overflow through the exception channel rather than a
    // failed frame, so it has to be asked for explicitly.
    final error = tester.takeException();
    if (error is FlutterError) {
      for (final line in error.diagnostics.take(5)) {
        // ignore: avoid_print
        print('>>> $line');
      }
    }
    expect(error, isNull);
  }

  group('PerformanceCard', () {
    testWidgets('renders a real portfolio without complaint', (tester) async {
      await tester.pumpWidget(
        host(PerformanceCard(state: PortfolioLoaded(cryptos: cryptos))),
      );

      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Total return'), findsOneWidget);
      expect(find.text('Annualised (XIRR)'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('shows a dash rather than a fabricated rate', (tester) async {
      // One coin, one buy, nothing sold: no closing flow, so no rate exists.
      final single = [
        CryptoEntity(
          id: 'c1',
          coinId: 'bitcoin',
          name: 'Bitcoin',
          symbol: 'BTC',
          currentPrice: 0,
          transactions: [
            TransactionEntity(
              id: 't1',
              cryptoId: 'c1',
              type: TransactionType.buy,
              quantity: 1,
              pricePerCoin: 100,
              date: DateTime(2026, 1, 1),
            )
          ],
        )
      ];

      await tester.pumpWidget(
        host(PerformanceCard(state: PortfolioLoaded(cryptos: single))),
      );

      expect(find.text('—'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('survives a narrow screen', (tester) async {
      await tester.pumpWidget(
        host(PerformanceCard(state: PortfolioLoaded(cryptos: cryptos)),
            width: 320),
      );
      await expectNoOverflow(tester);
    });

    testWidgets('an empty portfolio does not crash the card', (tester) async {
      await tester.pumpWidget(
        host(PerformanceCard(state: PortfolioLoaded(cryptos: const []))),
      );
      expect(find.text('Performance'), findsOneWidget);
      await expectNoOverflow(tester);
    });
  });

  group('DiversificationCard', () {
    Widget withState(DiversificationState state) => host(
          BlocProvider<DiversificationCubit>(
            create: (_) => _StubDiversification(state),
            child: DiversificationCard(cryptos: cryptos),
          ),
        );

    testWidgets('shows a spinner while loading', (tester) async {
      await tester.pumpWidget(withState(const DiversificationState.loading()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders correlation and sectors', (tester) async {
      await tester.pumpWidget(withState(DiversificationState.ready(
        DiversificationResult(
          report: buildDiversificationReport([
            CoinSeries(
                coinId: 'a',
                symbol: 'AAVE',
                weight: 0.5,
                returns: [for (var i = 0; i < 100; i++) (i % 5 - 2) / 100]),
            CoinSeries(
                coinId: 'e',
                symbol: 'ETH',
                weight: 0.5,
                returns: [for (var i = 0; i < 100; i++) (i % 5 - 2) / 100]),
          ]),
          sectors: const [
            SectorWeight(
                sector: 'Layer 1 (L1)', weight: 0.62, symbols: ['ETH', 'SOL']),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Diversification'), findsOneWidget);
      expect(find.text('Real benefit'), findsOneWidget);
      expect(find.text('Layer 1 (L1)'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('says so when there is nothing to measure', (tester) async {
      await tester.pumpWidget(
          withState(const DiversificationState.ready(
              DiversificationResult(
                  report: DiversificationReport.empty, sectors: []))));

      expect(find.textContaining('two priced holdings'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('a failure is stated, not left spinning', (tester) async {
      await tester.pumpWidget(withState(DiversificationState.ready(
        DiversificationResult(
          report: DiversificationReport.empty,
          sectors: const [],
          error: Exception('rate limited'),
        ),
      )));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });

  group('BenchmarkCard', () {
    Widget withState(BenchmarkState state) => host(
          BlocProvider<BenchmarkCubit>(
            create: (_) => _StubBenchmark(state),
            child: BenchmarkCard(cryptos: cryptos),
          ),
        );

    BenchmarkOutcome outcome({
      required double actual,
      required double benchmark,
    }) =>
        BenchmarkOutcome(
          symbol: 'BTC',
          from: DateTime(2025, 8, 25),
          to: DateTime(2026, 8, 24),
          startValue: 1000,
          actualValue: actual,
          benchmarkValue: benchmark,
          netContributed: 500,
          flowCount: 12,
          actualRate: 0.1,
          benchmarkRate: 0.4,
        );

    testWidgets('spins while loading', (tester) async {
      await tester.pumpWidget(withState(const BenchmarkState.loading()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('reads as behind when the yardstick won', (tester) async {
      await tester.pumpWidget(withState(BenchmarkState.ready(
        BenchmarkComparison(
          outcomes: [outcome(actual: 1200, benchmark: 2000)],
          windowCoverage: 0.67,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Your portfolio'), findsOneWidget);
      expect(find.text('All in BTC'), findsOneWidget);
      expect(find.text('Behind BTC'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('reads as ahead when the portfolio won', (tester) async {
      await tester.pumpWidget(withState(BenchmarkState.ready(
        BenchmarkComparison(
          outcomes: [outcome(actual: 3000, benchmark: 2000)],
          windowCoverage: 1.0,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Ahead of BTC'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('states the share of capital it could not cover',
        (tester) async {
      await tester.pumpWidget(withState(BenchmarkState.ready(
        BenchmarkComparison(
          outcomes: [outcome(actual: 1200, benchmark: 2000)],
          windowCoverage: 0.67,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('67%'), findsOneWidget,
          reason: 'a partial comparison must show its limits');
    });

    testWidgets('offers a retry after a failure', (tester) async {
      await tester.pumpWidget(withState(BenchmarkState.ready(
        BenchmarkComparison(outcomes: const [], error: Exception('down')),
      )));

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TransactionTile', () {
    TransactionEntity tx(TransactionType type, {double price = 1880.52}) =>
        TransactionEntity(
          id: 't1',
          cryptoId: 'c1',
          type: type,
          quantity: 0.05969,
          pricePerCoin: price,
          date: DateTime(2026, 8, 17),
        );

    testWidgets('shows the unit price beside the total', (tester) async {
      await tester.pumpWidget(
        host(TransactionTile(
            transaction: tx(TransactionType.buy), cryptoSymbol: 'ETH')),
      );

      expect(find.text('Buy'), findsOneWidget);
      expect(find.textContaining('@'), findsOneWidget,
          reason: 'the price per coin is what a DCA average is made of');
      await expectNoOverflow(tester);
    });

    testWidgets('every movement type has a label', (tester) async {
      for (final type in TransactionType.values) {
        await tester.pumpWidget(
          host(TransactionTile(transaction: tx(type), cryptoSymbol: 'ETH')),
        );
        await expectNoOverflow(tester);
      }
      // The last one rendered is reward.
      expect(find.text('Reward'), findsOneWidget);
    });

    testWidgets('a transfer without a price says so', (tester) async {
      await tester.pumpWidget(
        host(TransactionTile(
          transaction: tx(TransactionType.transferIn, price: 0),
          cryptoSymbol: 'SEI',
        )),
      );

      expect(find.text('No cost basis'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('the menu appears only when an action is offered',
        (tester) async {
      await tester.pumpWidget(
        host(TransactionTile(
            transaction: tx(TransactionType.buy), cryptoSymbol: 'ETH')),
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);

      await tester.pumpWidget(
        host(TransactionTile(
          transaction: tx(TransactionType.buy),
          cryptoSymbol: 'ETH',
          onDelete: () {},
          onEdit: () {},
        )),
      );
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('deleting takes two deliberate actions', (tester) async {
      // A single tap used to delete outright, with no menu and no way back.
      var deleted = false;
      await tester.pumpWidget(
        host(TransactionTile(
          transaction: tx(TransactionType.buy),
          cryptoSymbol: 'ETH',
          onDelete: () => deleted = true,
        )),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(deleted, isFalse, reason: 'opening a menu is not a decision');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });
  });
}

class _StubDiversification extends DiversificationCubit {
  _StubDiversification(DiversificationState state)
      : super(service: _NoService()) {
    emit(state);
  }

  @override
  Future<void> load(List<CryptoEntity> cryptos, {bool force = false}) async {}
}

class _StubBenchmark extends BenchmarkCubit {
  _StubBenchmark(BenchmarkState state) : super(service: _NoBenchmark()) {
    emit(state);
  }

  @override
  Future<void> load(List<CryptoEntity> cryptos, {bool force = false}) async {}
}

class _NoService implements DiversificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the stub never calls the service');
}

class _NoBenchmark implements BenchmarkService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the stub never calls the service');
}
