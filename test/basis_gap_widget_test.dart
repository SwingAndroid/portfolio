import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/core/theme/app_theme.dart';
import 'package:crypto_portfolio/data/services/basis_backfill_service.dart';
import 'package:crypto_portfolio/domain/analytics/basis_gap.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';
import 'package:crypto_portfolio/presentation/bloc/basis_gap/basis_gap_cubit.dart';
import 'package:crypto_portfolio/presentation/pages/basis_gap_page.dart';
import 'package:crypto_portfolio/presentation/widgets/basis_gap_card.dart';

class _FakeRepository implements CryptoRepository {
  _FakeRepository(this.chart);

  final List<PricePoint> chart;
  final written = <TransactionEntity>[];

  @override
  Future<List<PricePoint>> getMarketChart(String c, {int days = 30}) async =>
      chart;

  @override
  Future<void> addTransaction(TransactionEntity t) async => written.add(t);

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

TransactionEntity drip(String id, double qty, DateTime date) =>
    TransactionEntity(
      id: id,
      cryptoId: 'apt',
      type: TransactionType.transferIn,
      quantity: qty,
      pricePerCoin: 0,
      date: date,
    );

void main() {
  final oct = DateTime(2025, 10, 22);
  final feb = DateTime(2026, 2, 22);
  final chart = [PricePoint(oct, 3.2210), PricePoint(feb, 0.8880)];

  CoinBasisGaps aptGaps(
          {List<TransactionEntity>? txs, double holdings = 100}) =>
      CoinBasisGaps(
        cryptoId: 'apt',
        coinId: 'aptos',
        symbol: 'APT',
        totalHoldings: holdings,
        transactions: txs ?? [drip('a', 2, oct), drip('c', 5, feb)],
      );

  Widget host(Widget child, {double width = 375}) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: SizedBox(width: width, child: child),
        ),
      );

  Future<void> expectNoOverflow(WidgetTester tester) async {
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'the layout overflowed: $ex');
  }

  group('the summary card', () {
    testWidgets('renders nothing when there is nothing wrong', (tester) async {
      await tester.pumpWidget(host(const BasisGapCard(gaps: [])));

      expect(find.text('Missing cost basis'), findsNothing,
          reason: 'a tidy portfolio should not be nagged');
    });

    testWidgets('names each coin and how much rests on no cost',
        (tester) async {
      await tester.pumpWidget(host(BasisGapCard(gaps: [aptGaps()])));

      expect(find.text('Missing cost basis'), findsOneWidget);
      expect(find.text('APT'), findsOneWidget);
      expect(find.text('2 rows'), findsOneWidget);
      expect(find.text('7%'), findsOneWidget,
          reason: '7 of 100 units carry no recorded cost');
    });

    testWidgets('survives a narrow phone and a long symbol', (tester) async {
      final wide = CoinBasisGaps(
        cryptoId: 'x',
        coinId: 'x',
        symbol: 'WBTCWBTCWBTC',
        totalHoldings: 1000,
        transactions: [
          for (var i = 0; i < 40; i++) drip('$i', 12345.6789, oct)
        ],
      );

      await tester.pumpWidget(host(BasisGapCard(gaps: [wide]), width: 320));
      await expectNoOverflow(tester);
    });
  });

  group('the review screen', () {
    /// Opens the page on a tall viewport.
    ///
    /// The default 600px test surface leaves later rows unbuilt — a ListView
    /// only builds what fits — which looks like a missing row rather than the
    /// scrolling it actually is.
    Future<BasisGapCubit> open(
      WidgetTester tester, {
      required _FakeRepository repo,
      CoinBasisGaps? coin,
      double width = 375,
    }) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cubit = BasisGapCubit(service: BasisBackfillService(repo));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: BasisGapPage(coin: coin ?? aptGaps(), cubit: cubit),
      ));
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('lists every row with its own day\'s price', (tester) async {
      await open(tester, repo: _FakeRepository(chart));

      expect(find.text('@ 3.2210'), findsOneWidget);
      expect(find.text('@ 0.8880'), findsOneWidget);
      await expectNoOverflow(tester);
    });

    testWidgets('totals the income that confirming would record',
        (tester) async {
      await open(tester, repo: _FakeRepository(chart));

      // 2 × 3.2210 + 5 × 0.8880 = 6.44 + 4.44 = 10.88
      expect(find.text('Income to record'), findsOneWidget);
      expect(find.textContaining('10.88'), findsOneWidget);
      expect(find.text('Record 2 as rewards'), findsOneWidget);
    });

    testWidgets('unticking a row drops it from the total', (tester) async {
      await open(tester, repo: _FakeRepository(chart));

      await tester.tap(find.text('@ 0.8880'));
      await tester.pump();

      // The 4.44 row is out, so the only row left and the total both read
      // 6.44 — one on the row, one in the confirm bar.
      expect(find.textContaining('6.44'), findsNWidgets(2));
      expect(find.textContaining('10.88'), findsNothing);
      expect(find.text('Record 1 as reward'), findsOneWidget,
          reason: 'one row should not be pluralised');
    });

    testWidgets('None disables the button rather than writing nothing',
        (tester) async {
      final repo = _FakeRepository(chart);
      await open(tester, repo: repo);

      await tester.tap(find.text('None'));
      await tester.pump();

      expect(find.text('Nothing selected'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('confirming writes the ticked rows and reports back',
        (tester) async {
      final repo = _FakeRepository(chart);
      await open(tester, repo: repo);

      await tester.tap(find.text('Record 2 as rewards'));
      await tester.pumpAndSettle();

      expect(repo.written, hasLength(2));
      expect(repo.written.map((t) => t.type),
          everyElement(TransactionType.reward));
      expect(find.text('2 recorded as income'), findsOneWidget);
    });

    testWidgets('once everything is fixed the screen says so', (tester) async {
      await open(tester, repo: _FakeRepository(chart));

      await tester.tap(find.text('Record 2 as rewards'));
      await tester.pumpAndSettle();

      expect(
          find.text('Every holding here has a recorded cost'), findsOneWidget);
    });

    testWidgets('a row older than the price history is shown but not tickable',
        (tester) async {
      final coin = aptGaps(txs: [
        drip('a', 2, oct),
        drip('ancient', 9, DateTime(2023, 1, 1)),
      ]);
      await open(tester, repo: _FakeRepository(chart), coin: coin);

      expect(find.text('no price'), findsOneWidget);
      expect(find.textContaining('older than the year of price history'),
          findsOneWidget);
      expect(find.text('Record 1 as reward'), findsOneWidget,
          reason: 'the unpriceable row is not counted in');
    });

    testWidgets('many rows on a narrow screen do not overflow', (tester) async {
      final crowded = CoinBasisGaps(
        cryptoId: 'sei',
        coinId: 'sei-network',
        symbol: 'SEI',
        totalHoldings: 7241,
        transactions: [
          for (var i = 0; i < 37; i++) drip('$i', 1234.5678, feb),
        ],
      );
      await open(tester,
          repo: _FakeRepository(chart), coin: crowded, width: 320);

      await expectNoOverflow(tester);
    });
  });
}
