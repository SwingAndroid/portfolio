import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/core/theme/app_theme.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';
import 'package:crypto_portfolio/domain/usecases/add_transaction_usecase.dart';
import 'package:crypto_portfolio/domain/usecases/delete_transaction_usecase.dart';
import 'package:crypto_portfolio/presentation/bloc/crypto_detail/crypto_detail_cubit.dart';
import 'package:crypto_portfolio/presentation/widgets/add_transaction_sheet.dart';

/// A repository that answers price questions and records what it was asked.
class _FakeRepository implements CryptoRepository {
  _FakeRepository({this.spot = 0.5985, this.chart = const [], this.fail = false});

  final double spot;
  final List<PricePoint> chart;
  final bool fail;

  int spotCalls = 0;
  int chartCalls = 0;

  @override
  Future<double> getCryptoPrice(String coinId) async {
    spotCalls++;
    if (fail) throw Exception('network down');
    return spot;
  }

  @override
  Future<List<PricePoint>> getMarketChart(String coinId, {int days = 30}) async {
    chartCalls++;
    if (fail) throw Exception('network down');
    return chart;
  }

  @override
  Future<void> addTransaction(TransactionEntity transaction) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used by this test');
}

void main() {
  late _FakeRepository repository;

  Widget host(_FakeRepository repo, {String? coinId = 'aptos'}) {
    repository = repo;
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: BlocProvider(
        create: (_) => CryptoDetailCubit(
          repository: repo,
          addTransaction: AddTransactionUsecase(repo),
          deleteTransaction: DeleteTransactionUsecase(repo),
        ),
        child: Scaffold(
          body: AddTransactionSheet(
            cryptoId: 'apt-1',
            cryptoSymbol: 'APT',
            coinId: coinId,
          ),
        ),
      ),
    );
  }

  /// Quantity, price, fee — the price field is the second.
  ///
  /// Found by position rather than by label, because the label itself changes
  /// with the transaction type.
  Finder priceField() => find
      .descendant(
          of: find.byType(AddTransactionSheet), matching: find.byType(TextField))
      .at(1);

  Finder quantityField() => find
      .descendant(
          of: find.byType(AddTransactionSheet), matching: find.byType(TextField))
      .first;

  String priceText(WidgetTester tester) =>
      tester.widget<TextField>(priceField()).controller!.text;

  Future<void> tapReward(WidgetTester tester) async {
    await tester.tap(find.text('Reward'));
    await tester.pumpAndSettle();
  }

  group('choosing Reward', () {
    testWidgets('fills the price with what the coin is worth today',
        (tester) async {
      await tester.pumpWidget(host(_FakeRepository(spot: 0.5985)));
      expect(priceText(tester), isEmpty, reason: 'nothing typed yet');

      await tapReward(tester);

      expect(priceText(tester), '0.598500');
      expect(repository.spotCalls, 1);
      expect(repository.chartCalls, 0,
          reason: 'today needs the live price, not a year of history');
      expect(find.text('Filled with the current price'), findsOneWidget);
    });

    testWidgets('never overwrites a price the user already typed',
        (tester) async {
      await tester.pumpWidget(host(_FakeRepository()));

      await tester.enterText(priceField(), '0.62');
      await tester.pump();
      await tapReward(tester);

      expect(priceText(tester), '0.62');
      expect(repository.spotCalls, 0,
          reason: 'a figure the user chose is not ours to replace');
    });

    testWidgets('says so when no price can be found', (tester) async {
      await tester.pumpWidget(host(_FakeRepository(spot: 0)));

      await tapReward(tester);

      expect(priceText(tester), isEmpty);
      expect(find.text('No price available for that date'), findsOneWidget);
    });

    testWidgets('reports a failed lookup instead of leaving a spinner',
        (tester) async {
      await tester.pumpWidget(host(_FakeRepository(fail: true)));

      await tapReward(tester);

      expect(find.text('Could not reach the price service'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(priceText(tester), isEmpty);
    });
  });

  group('the fill button', () {
    testWidgets('works for a buy, not just a reward', (tester) async {
      await tester.pumpWidget(host(_FakeRepository(spot: 2500.0)));

      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tester.pumpAndSettle();

      expect(priceText(tester), '2500.00',
          reason: 'a four-figure price does not need six decimals');
    });

    testWidgets('is absent when the coin cannot be looked up', (tester) async {
      await tester.pumpWidget(host(_FakeRepository(), coinId: null));

      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    });

    testWidgets('a filled-in price can still be edited by hand',
        (tester) async {
      await tester.pumpWidget(host(_FakeRepository()));

      await tapReward(tester);
      expect(priceText(tester), '0.598500');
      expect(find.text('Filled with the current price'), findsOneWidget);

      // The lookup pre-fills; it does not lock. The last word is the user's.
      await tester.enterText(priceField(), '0.61');
      await tester.pump();

      expect(priceText(tester), '0.61');
      expect(find.text('Filled with the current price'), findsNothing,
          reason: 'the field is the user\'s again');
    });

    testWidgets('a hand-edited price is what gets saved', (tester) async {
      await tester.pumpWidget(host(_FakeRepository()));

      await tapReward(tester);
      await tester.enterText(priceField(), '0.61');
      await tester.enterText(quantityField(), '17');
      await tester.pump();

      // 17 × 0.61 = 10.37, not 17 × 0.5985 = 10.17.
      expect(find.text('\$10.37'), findsOneWidget,
          reason: 'the total follows the typed price, not the looked-up one');
    });
  });

  group('changing the date', () {
    testWidgets('re-fetches a filled price for the new day', (tester) async {
      final past = DateTime.now().subtract(const Duration(days: 4));
      await tester.pumpWidget(host(_FakeRepository(
        spot: 0.5985,
        chart: [PricePoint(DateTime(past.year, past.month, past.day), 0.6492)],
      )));

      await tapReward(tester);
      expect(priceText(tester), '0.598500', reason: 'today, to begin with');

      // Open the picker and step back to a day earlier in the month.
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${past.day}').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(repository.chartCalls, 1,
          reason: 'a past date is answered from history, not the live price');
      expect(priceText(tester), '0.649200',
          reason: 'the reward is worth what it was worth on the day it landed');
    });

    testWidgets('leaves a typed price alone', (tester) async {
      final past = DateTime.now().subtract(const Duration(days: 4));
      await tester.pumpWidget(host(_FakeRepository(
        chart: [PricePoint(DateTime(past.year, past.month, past.day), 0.6492)],
      )));

      await tester.enterText(priceField(), '0.61');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${past.day}').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(priceText(tester), '0.61');
      expect(repository.chartCalls, 0);
    });
  });
}
