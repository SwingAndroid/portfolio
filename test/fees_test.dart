import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/models/transaction_model.dart';
import 'package:crypto_portfolio/domain/analytics/cost_basis_ledger.dart';
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

void main() {
  group('fees in the cost basis', () {
    test('a buy fee raises what the units cost', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1), fee: 5),
      ]);

      expect(ledger.remainingCost, closeTo(105, 1e-9));
      expect(ledger.avgCost, closeTo(105, 1e-9));
      expect(ledger.unrealizedPnl(100), closeTo(-5, 1e-9),
          reason: 'flat price still leaves you down by the fee');
    });

    test('a sell fee comes out of the proceeds and the gain', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.sell, 1, 150, DateTime(2025, 2, 1), fee: 8),
      ]);

      expect(ledger.proceeds, closeTo(142, 1e-9));
      expect(ledger.realizedPnl, closeTo(42, 1e-9),
          reason: '150 - 8 received, against a basis of 100');
    });

    test('fees on both sides compound against you', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1), fee: 5),
        tx('2', TransactionType.sell, 1, 100, DateTime(2025, 2, 1), fee: 5),
      ]);

      // Bought and sold at the same price: the round trip costs both fees.
      expect(ledger.realizedPnl, closeTo(-10, 1e-9));
    });

    test('a transfer-in fee is part of acquiring the units', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.transferIn, 2, 0, DateTime(2025, 1, 1), fee: 3),
      ]);

      expect(ledger.remainingCost, closeTo(3, 1e-9));
      expect(ledger.avgCost, closeTo(1.5, 1e-9));
    });

    test('a transfer-out fee does not disturb the remaining basis', () {
      final ledger = CostBasisLedger.fromTransactions([
        tx('1', TransactionType.buy, 2, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.transferOut, 1, 0, DateTime(2025, 2, 1), fee: 4),
      ]);

      expect(ledger.realizedPnl, 0);
      expect(ledger.remainingCost, closeTo(100, 1e-9),
          reason: 'half the basis relieved, the fee sits outside the position');
    });

    test('unrecorded fees leave every figure exactly as before', () {
      // The regression that matters: 454 existing rows carry no fee, and none
      // of their numbers may shift because the field now exists.
      final withoutFees = [
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.buy, 1, 200, DateTime(2025, 2, 1)),
        tx('3', TransactionType.sell, 1, 250, DateTime(2025, 3, 1)),
      ];
      final ledger = CostBasisLedger.fromTransactions(withoutFees);

      expect(ledger.realizedPnl, closeTo(100, 1e-9));
      expect(ledger.proceeds, closeTo(250, 1e-9));
      expect(ledger.remainingCost, closeTo(150, 1e-9));
      expect(ledger.avgCost, closeTo(150, 1e-9));
    });

    test('entity helpers state the two directions plainly', () {
      final buy = tx('1', TransactionType.buy, 2, 50, DateTime(2025, 1, 1), fee: 4);
      expect(buy.totalValue, closeTo(100, 1e-9));
      expect(buy.grossCost, closeTo(104, 1e-9));

      final sell =
          tx('2', TransactionType.sell, 2, 50, DateTime(2025, 1, 1), fee: 4);
      expect(sell.netProceeds, closeTo(96, 1e-9));
    });
  });

  group('storage compatibility', () {
    test('a record written before the field existed reads back as zero', () {
      // Hive hands back null for a field absent from an older record.
      final legacy = TransactionModel(
        id: 't1',
        cryptoId: 'c1',
        typeIndex: TransactionType.buy.index,
        quantity: 1,
        pricePerCoin: 100,
        date: DateTime(2025, 1, 1),
        // fee omitted entirely, exactly as the generated adapter produces
      );

      expect(legacy.fee, isNull);
      expect(legacy.toEntity().fee, 0,
          reason: 'null must degrade to zero, never to a crash');
      expect(legacy.toEntity().grossCost, closeTo(100, 1e-9));
    });

    test('a zero fee is stored as null, not as a zero row', () {
      final entity = tx('t1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1));
      expect(TransactionModel.fromEntity(entity).fee, isNull,
          reason: 'unrecorded and free stay distinguishable');
    });

    test('a real fee survives the round trip', () {
      final entity =
          tx('t1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1), fee: 2.5);
      final restored = TransactionModel.fromEntity(entity).toEntity();

      expect(restored.fee, closeTo(2.5, 1e-9));
      expect(restored.grossCost, closeTo(102.5, 1e-9));
    });
  });
}
