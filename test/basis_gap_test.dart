import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/domain/analytics/basis_gap.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

TransactionEntity tx({
  String id = 't',
  TransactionType type = TransactionType.transferIn,
  double qty = 1,
  double price = 0,
  DateTime? date,
  double fee = 0,
}) =>
    TransactionEntity(
      id: id,
      cryptoId: 'c1',
      type: type,
      quantity: qty,
      pricePerCoin: price,
      date: date ?? DateTime(2026, 1, 1),
      fee: fee,
    );

CryptoEntity coin(List<TransactionEntity> transactions,
        {String symbol = 'APT'}) =>
    CryptoEntity(
      id: 'c1',
      coinId: 'aptos',
      name: 'Aptos',
      symbol: symbol,
      transactions: transactions,
    );

void main() {
  group('spotting a gap', () {
    test('a transfer in with no price is one', () {
      expect(
          isBasisGap(tx(type: TransactionType.transferIn, price: 0)), isTrue);
    });

    test('a reward with no price is one too', () {
      expect(isBasisGap(tx(type: TransactionType.reward, price: 0)), isTrue);
    });

    test('anything carrying a price is not', () {
      expect(isBasisGap(tx(type: TransactionType.transferIn, price: 3.2)),
          isFalse);
      expect(isBasisGap(tx(type: TransactionType.reward, price: 0.6)), isFalse);
    });

    test('a buy at zero is left alone', () {
      // A purchase with no price is a typo the user meant to fill in, not a
      // cost that was never knowable. Guessing would overwrite their intent.
      expect(isBasisGap(tx(type: TransactionType.buy, price: 0)), isFalse);
    });

    test('a transfer out is not a gap', () {
      // Nothing entered the portfolio, so there is no basis to be missing.
      expect(
          isBasisGap(tx(type: TransactionType.transferOut, price: 0)), isFalse);
    });
  });

  group('grouping by coin', () {
    test('measures how much of the holding rests on no cost', () {
      final gaps = findBasisGaps([
        coin([
          tx(id: 'b', type: TransactionType.buy, qty: 76, price: 2.0),
          tx(id: 'g1', qty: 20),
          tx(id: 'g2', qty: 4),
        ])
      ]);

      expect(gaps, hasLength(1));
      expect(gaps.first.count, 2);
      expect(gaps.first.quantity, 24);
      expect(gaps.first.totalHoldings, 100);
      expect(gaps.first.shareOfHoldings, 24);
    });

    test('a coin with everything priced does not appear', () {
      final gaps = findBasisGaps([
        coin([tx(id: 'b', type: TransactionType.buy, qty: 10, price: 2.0)])
      ]);
      expect(gaps, isEmpty);
    });

    test('gaps come back oldest first', () {
      final gaps = findBasisGaps([
        coin([
          tx(id: 'late', date: DateTime(2026, 3, 28)),
          tx(id: 'early', date: DateTime(2025, 10, 22)),
          tx(id: 'mid', date: DateTime(2026, 1, 4)),
        ])
      ]);

      expect(
          gaps.first.transactions.map((t) => t.id), ['early', 'mid', 'late']);
      expect(gaps.first.earliest, DateTime(2025, 10, 22));
      expect(gaps.first.latest, DateTime(2026, 3, 28));
    });

    test('the worst-covered coin is listed first', () {
      final mostlyPriceless = CryptoEntity(
        id: 'sei',
        coinId: 'sei-network',
        name: 'Sei',
        symbol: 'SEI',
        transactions: [
          tx(id: 'b', type: TransactionType.buy, qty: 10, price: 0.2),
          tx(id: 'g', qty: 90),
        ],
      );
      final mostlyPriced = coin([
        tx(id: 'b2', type: TransactionType.buy, qty: 90, price: 3.0),
        tx(id: 'g2', qty: 10),
      ]);

      final gaps = findBasisGaps([mostlyPriced, mostlyPriceless]);
      expect(gaps.map((g) => g.symbol), ['SEI', 'APT']);
    });

    test('a coin sold down to nothing does not divide by zero', () {
      final gaps = findBasisGaps([
        coin([
          tx(id: 'g', qty: 10),
          tx(id: 's', type: TransactionType.sell, qty: 10, price: 1.0),
        ])
      ]);
      expect(gaps.first.totalHoldings, 0);
      expect(gaps.first.shareOfHoldings, 0);
    });
  });

  group('pricing the gaps', () {
    // The real APT staking drips, with the prices CoinGecko returns for them.
    final chart = [
      PricePoint(DateTime(2025, 10, 22), 3.2210),
      PricePoint(DateTime(2025, 11, 22), 2.3969),
      PricePoint(DateTime(2026, 2, 22), 0.8880),
    ];

    test('values each row at the price of its own day', () {
      final resolved = resolveGaps([
        tx(id: 'a', qty: 2, date: DateTime(2025, 10, 22)),
        tx(id: 'b', qty: 2, date: DateTime(2025, 11, 22)),
        tx(id: 'c', qty: 5, date: DateTime(2026, 2, 22)),
      ], chart);

      expect(resolved[0].value, closeTo(6.44, 0.01));
      expect(resolved[1].value, closeTo(4.79, 0.01));
      expect(resolved[2].value, closeTo(4.44, 0.01));
      expect(incomeFrom(resolved), closeTo(15.67, 0.02));
    });

    test('a date older than the price history is reported, not invented', () {
      final resolved = resolveGaps(
          [tx(id: 'ancient', qty: 3, date: DateTime(2024, 5, 1))], chart);

      expect(resolved.single.resolvable, isFalse);
      expect(resolved.single.price, isNull);
      expect(resolved.single.value, 0);
      expect(incomeFrom(resolved), 0,
          reason: 'an unvaluable row contributes nothing');
    });

    test('unresolvable rows are excluded from the total', () {
      final resolved = resolveGaps([
        tx(id: 'ok', qty: 2, date: DateTime(2025, 10, 22)),
        tx(id: 'old', qty: 99, date: DateTime(2023, 1, 1)),
      ], chart);

      expect(incomeFrom(resolved), closeTo(6.44, 0.01));
    });
  });

  group('rewriting a gap as income', () {
    test('keeps the id so the original row is overwritten', () {
      final original = tx(id: 'row-7', qty: 2, date: DateTime(2025, 10, 22));
      final resolved =
          resolveGaps([original], [PricePoint(DateTime(2025, 10, 22), 3.2210)])
              .single;

      final converted = resolved.asReward;
      expect(converted.id, 'row-7',
          reason: 'a new id would leave a duplicate behind');
      expect(converted.type, TransactionType.reward);
      expect(converted.pricePerCoin, 3.2210);
    });

    test('carries the quantity, date, fee and note across untouched', () {
      final original = TransactionEntity(
        id: 'row-8',
        cryptoId: 'c1',
        type: TransactionType.transferIn,
        quantity: 5,
        pricePerCoin: 0,
        date: DateTime(2026, 2, 22),
        note: 'staking payout',
        fee: 0.25,
      );
      final converted =
          resolveGaps([original], [PricePoint(DateTime(2026, 2, 22), 0.8880)])
              .single
              .asReward;

      expect(converted.quantity, 5);
      expect(converted.date, DateTime(2026, 2, 22));
      expect(converted.note, 'staking payout');
      expect(converted.fee, 0.25);
      expect(converted.cryptoId, 'c1');
    });

    test('the converted row books income and a matching cost basis', () {
      final converted = resolveGaps(
          [tx(id: 'r', qty: 5, date: DateTime(2026, 2, 22))],
          [PricePoint(DateTime(2026, 2, 22), 0.8880)]).single.asReward;

      // 5 × 0.8880 = 4.44 recorded as income, and the same figure becomes the
      // cost the units are measured against on a later sale.
      expect(converted.incomeValue, closeTo(4.44, 0.01));
      expect(converted.grossCost, closeTo(4.44, 0.01));
      expect(converted.capitalIn, 0,
          reason: 'a reward is income, not money the user put in');
    });
  });
}
