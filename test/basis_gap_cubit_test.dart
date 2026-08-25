import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/data/services/basis_backfill_service.dart';
import 'package:crypto_portfolio/domain/analytics/basis_gap.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/repositories/crypto_repository.dart';
import 'package:crypto_portfolio/presentation/bloc/basis_gap/basis_gap_cubit.dart';

TransactionEntity gap(String id, double qty, DateTime date) =>
    TransactionEntity(
      id: id,
      cryptoId: 'apt',
      type: TransactionType.transferIn,
      quantity: qty,
      pricePerCoin: 0,
      date: date,
    );

/// Records every write, and can be told to refuse specific rows.
class _FakeRepository implements CryptoRepository {
  _FakeRepository(
      {this.chart = const [], this.refuse = const {}, this.chartFails = false});

  final List<PricePoint> chart;
  final Set<String> refuse;
  final bool chartFails;

  final written = <TransactionEntity>[];
  int chartCalls = 0;

  @override
  Future<List<PricePoint>> getMarketChart(String coinId,
      {int days = 30}) async {
    chartCalls++;
    if (chartFails) throw Exception('rate limited');
    return chart;
  }

  @override
  Future<void> addTransaction(TransactionEntity t) async {
    if (refuse.contains(t.id)) throw Exception('cloud refused ${t.id}');
    written.add(t);
  }

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  final oct = DateTime(2025, 10, 22);
  final nov = DateTime(2025, 11, 22);
  final feb = DateTime(2026, 2, 22);

  final chart = [
    PricePoint(oct, 3.2210),
    PricePoint(nov, 2.3969),
    PricePoint(feb, 0.8880),
  ];

  CoinBasisGaps coinWith(List<TransactionEntity> txs,
          {double holdings = 100}) =>
      CoinBasisGaps(
        cryptoId: 'apt',
        coinId: 'aptos',
        symbol: 'APT',
        totalHoldings: holdings,
        transactions: txs,
      );

  final threeDrips = [gap('a', 2, oct), gap('b', 2, nov), gap('c', 5, feb)];

  BasisGapCubit cubitFor(_FakeRepository repo) =>
      BasisGapCubit(service: BasisBackfillService(repo));

  group('loading', () {
    test('prices every row from a single chart request', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);

      await cubit.load(coinWith(threeDrips));

      expect(repo.chartCalls, 1,
          reason: 'three gaps must not cost three requests');
      expect(cubit.state.ready!.gaps, hasLength(3));
      expect(cubit.state.ready!.selectedIncome, closeTo(15.67, 0.02));
    });

    test('everything priceable starts ticked', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit.load(coinWith(threeDrips));

      expect(cubit.state.ready!.selected, {'a', 'b', 'c'});
    });

    test('a row older than the price history is left unticked', () async {
      final ancient = gap('old', 9, DateTime(2023, 1, 1));
      final cubit = cubitFor(_FakeRepository(chart: chart));

      await cubit.load(coinWith([...threeDrips, ancient]));

      expect(cubit.state.ready!.selected, isNot(contains('old')));
      expect(cubit.state.ready!.unreachable, 1);
    });

    test('a failed lookup surfaces instead of an empty screen', () async {
      final cubit = cubitFor(_FakeRepository(chartFails: true));
      await cubit.load(coinWith(threeDrips));

      expect(cubit.state.error, isNotNull);
      expect(cubit.state.ready, isNull);
    });
  });

  group('choosing rows', () {
    test('unticking removes it from the total', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit.load(coinWith(threeDrips));

      cubit.toggle('c'); // the 5 × 0.8880 = 4.44 row

      expect(cubit.state.ready!.selected, {'a', 'b'});
      expect(cubit.state.ready!.selectedIncome, closeTo(11.23, 0.02));
    });

    test('toggling twice puts it back', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit.load(coinWith(threeDrips));

      cubit.toggle('a');
      cubit.toggle('a');

      expect(cubit.state.ready!.selected, {'a', 'b', 'c'});
    });

    test('select none then all', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit.load(coinWith(threeDrips));

      cubit.selectNone();
      expect(cubit.state.ready!.selected, isEmpty);
      expect(cubit.state.ready!.selectedIncome, 0);

      cubit.selectAll();
      expect(cubit.state.ready!.selected, {'a', 'b', 'c'});
    });

    test('select all never ticks an unpriceable row', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit
          .load(coinWith([...threeDrips, gap('old', 9, DateTime(2023, 1, 1))]));

      cubit.selectAll();

      expect(cubit.state.ready!.selected, {'a', 'b', 'c'});
    });
  });

  group('converting', () {
    test('writes the ticked rows as rewards at their own price', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit.load(coinWith(threeDrips));

      final result = await cubit.applySelection();

      expect(result!.written, 3);
      expect(repo.written.map((t) => t.type),
          everyElement(TransactionType.reward));
      expect(repo.written.firstWhere((t) => t.id == 'a').pricePerCoin, 3.2210);
      expect(repo.written.firstWhere((t) => t.id == 'c').pricePerCoin, 0.8880);
    });

    test('keeps every id so nothing is duplicated', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit.load(coinWith(threeDrips));

      await cubit.applySelection();

      expect(repo.written.map((t) => t.id).toSet(), {'a', 'b', 'c'});
    });

    test('an unticked row is never written', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit.load(coinWith(threeDrips));

      cubit.toggle('b');
      await cubit.applySelection();

      expect(repo.written.map((t) => t.id), ['a', 'c']);
      expect(repo.written.any((t) => t.id == 'b'), isFalse,
          reason: 'a wallet transfer the user unticked is not income');
    });

    test('converted rows leave the list, unticked ones remain', () async {
      final cubit = cubitFor(_FakeRepository(chart: chart));
      await cubit.load(coinWith(threeDrips));

      cubit.toggle('b');
      await cubit.applySelection();

      expect(cubit.state.ready!.gaps.map((g) => g.transaction.id), ['b']);
      expect(cubit.state.ready!.selected, isEmpty);
    });

    test('a row the cloud refused stays on the list', () async {
      final repo = _FakeRepository(chart: chart, refuse: {'c'});
      final cubit = cubitFor(repo);
      await cubit.load(coinWith(threeDrips));

      final result = await cubit.applySelection();

      expect(result!.written, 2);
      expect(result.failedIds, ['c']);
      expect(result.hasFailures, isTrue);
      expect(cubit.state.ready!.gaps.map((g) => g.transaction.id), ['c'],
          reason: 'a failed write must not look like a success');
    });

    test('an unpriceable row is skipped, not written at zero', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit
          .load(coinWith([...threeDrips, gap('old', 9, DateTime(2023, 1, 1))]));

      cubit.selectAll();
      await cubit.applySelection();

      expect(repo.written.any((t) => t.id == 'old'), isFalse);
      expect(cubit.state.ready!.gaps.map((g) => g.transaction.id), ['old'],
          reason: 'it is still a gap, and still needs a price');
    });

    test('confirming nothing writes nothing', () async {
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit.load(coinWith(threeDrips));

      cubit.selectNone();
      final result = await cubit.applySelection();

      expect(result, isNull);
      expect(repo.written, isEmpty);
    });

    test('quantity, date and fee survive the rewrite', () async {
      final original = TransactionEntity(
        id: 'z',
        cryptoId: 'apt',
        type: TransactionType.transferIn,
        quantity: 5,
        pricePerCoin: 0,
        date: feb,
        note: 'payout',
        fee: 0.25,
      );
      final repo = _FakeRepository(chart: chart);
      final cubit = cubitFor(repo);
      await cubit.load(coinWith([original]));

      await cubit.applySelection();

      final saved = repo.written.single;
      expect(saved.quantity, 5);
      expect(saved.date, feb);
      expect(saved.note, 'payout');
      expect(saved.fee, 0.25);
      expect(saved.capitalIn, 0, reason: 'income is not capital put in');
    });
  });
}
