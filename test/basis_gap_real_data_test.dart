import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_portfolio/domain/analytics/basis_gap.dart';
import 'package:crypto_portfolio/domain/analytics/cost_basis_ledger.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

/// The live APT and SEI staking drips, with the prices CoinGecko returns for
/// each date.
///
/// Replaying the real rows is the only check that says the feature produces
/// the figures the owner was told to expect, rather than figures that merely
/// satisfy a hand-made fixture.
const aptDrips = <(String, double, double)>[
  ('2025-10-22', 2, 3.2210),
  ('2025-10-26', 1, 3.3133),
  ('2025-10-30', 1, 3.4005),
  ('2025-10-31', 1, 3.2045),
  ('2025-11-04', 1, 2.7755),
  ('2025-11-06', 1, 2.6797),
  ('2025-11-10', 1, 3.2314),
  ('2025-11-22', 2, 2.3969),
  ('2025-12-07', 1, 1.7512),
  ('2025-12-17', 1, 1.5882),
  ('2025-12-24', 1, 1.6110),
  ('2026-01-04', 1, 1.8970),
  ('2026-01-13', 1, 1.7654),
  ('2026-02-22', 5, 0.8880),
  ('2026-03-01', 1, 0.9675),
  ('2026-03-15', 1, 0.9231),
  ('2026-03-28', 2, 0.9754),
];

const seiDrips = <(String, double, double)>[
  ('2025-10-17', 4, 0.2051),
  ('2025-10-21', 1, 0.1992),
  ('2025-10-26', 2, 0.1996),
  ('2025-10-28', 1, 0.2008),
  ('2025-10-30', 1, 0.1989),
  ('2025-10-31', 1, 0.1843),
  ('2025-11-02', 1, 0.1946),
  ('2025-11-03', 1, 0.1947),
  ('2025-11-05', 1, 0.1584),
  ('2025-11-07', 1, 0.1607),
  ('2025-11-09', 1, 0.1799),
  ('2025-11-11', 1, 0.1896),
  ('2025-11-13', 1, 0.1725),
  ('2025-11-15', 1, 0.1597),
  ('2025-11-17', 1, 0.1554),
  ('2025-11-20', 1, 0.1479),
  ('2025-11-22', 1, 0.1325),
  ('2025-11-23', 1, 0.1309),
  ('2025-11-25', 1, 0.1373),
  ('2025-11-29', 2, 0.1377),
  ('2025-12-04', 2, 0.1405),
  ('2025-12-07', 2, 0.1285),
  ('2025-12-12', 2, 0.1319),
  ('2025-12-14', 2, 0.1294),
  ('2025-12-17', 2, 0.1183),
  ('2025-12-24', 4, 0.1099),
  ('2026-01-04', 6, 0.1216),
  ('2026-01-13', 4, 0.1509),
  ('2026-01-21', 4, 0.1411),
  ('2026-02-10', 10, 0.0748),
  ('2026-02-22', 7, 0.0705),
  ('2026-03-01', 5, 0.1009),
  ('2026-03-07', 5, 0.1067),
  ('2026-03-13', 3, 0.1037),
  ('2026-03-28', 10, 0.0549),
  ('2026-04-16', 10, 0.0561),
  ('2026-05-09', 10, 0.0655),
];

List<TransactionEntity> gapsFrom(
        List<(String, double, double)> drips, String cryptoId) =>
    [
      for (var i = 0; i < drips.length; i++)
        TransactionEntity(
          id: '$cryptoId-$i',
          cryptoId: cryptoId,
          type: TransactionType.transferIn,
          quantity: drips[i].$2,
          pricePerCoin: 0,
          date: DateTime.parse(drips[i].$1),
        )
    ];

List<PricePoint> chartFrom(List<(String, double, double)> drips) =>
    [for (final d in drips) PricePoint(DateTime.parse(d.$1), d.$3)];

void main() {
  group('the real APT drips', () {
    final gaps = gapsFrom(aptDrips, 'apt');
    final chart = chartFrom(aptDrips);

    test('24 units across 17 rows, none of them priced', () {
      final found = findBasisGaps([
        CryptoEntity(
          id: 'apt',
          coinId: 'aptos',
          name: 'Aptos',
          symbol: 'APT',
          // 2228.09 bought, 22.28 sold, plus the 24 that arrived free.
          transactions: [
            TransactionEntity(
              id: 'buy',
              cryptoId: 'apt',
              type: TransactionType.buy,
              quantity: 2228.09,
              pricePerCoin: 2.0,
              date: DateTime(2025, 9, 7),
            ),
            TransactionEntity(
              id: 'sell',
              cryptoId: 'apt',
              type: TransactionType.sell,
              quantity: 22.28,
              pricePerCoin: 2.0,
              date: DateTime(2025, 9, 11),
            ),
            ...gaps,
          ],
        )
      ]).single;

      expect(found.count, 17);
      expect(found.quantity, 24);
      expect(found.shareOfHoldings, closeTo(1.08, 0.01));
    });

    test('prices out to the 46.74 the owner was quoted', () {
      final resolved = resolveGaps(gaps, chart);

      expect(resolved.every((g) => g.resolvable), isTrue,
          reason: 'every APT date still sits inside the year of history');
      expect(incomeFrom(resolved), closeTo(46.74, 0.01));
    });

    test('converting turns zero cost into a real basis', () {
      final before = CostBasisLedger.fromTransactions(gaps);
      expect(before.remainingCost, 0);
      expect(before.income, 0);

      final after = CostBasisLedger.fromTransactions(
          resolveGaps(gaps, chart).map((g) => g.asReward).toList());

      expect(after.remainingQuantity, 24, reason: 'holdings must not move');
      expect(after.remainingCost, closeTo(46.74, 0.01));
      expect(after.income, closeTo(46.74, 0.01));
    });

    test('the staking actually lost money, which zero basis hid', () {
      final after = CostBasisLedger.fromTransactions(
          resolveGaps(gaps, chart).map((g) => g.asReward).toList());

      // 24 APT at the 0.5957 they are worth now.
      const spot = 0.5957;
      expect(after.unrealizedPnl(spot), closeTo(-32.44, 0.05),
          reason: 'at zero basis this would have read as +14.30 of pure gain');
    });
  });

  group('the real SEI drips', () {
    final gaps = gapsFrom(seiDrips, 'sei');
    final chart = chartFrom(seiDrips);

    test('113 units across 37 rows', () {
      final resolved = resolveGaps(gaps, chart);
      expect(gaps.fold(0.0, (s, t) => s + t.quantity), 113);
      expect(resolved, hasLength(37));
    });

    test('prices out to the 12.38 the owner was quoted', () {
      expect(incomeFrom(resolveGaps(gaps, chart)), closeTo(12.38, 0.01));
    });
  });

  test('both coins together restore 59.12 of basis', () {
    final apt =
        incomeFrom(resolveGaps(gapsFrom(aptDrips, 'apt'), chartFrom(aptDrips)));
    final sei =
        incomeFrom(resolveGaps(gapsFrom(seiDrips, 'sei'), chartFrom(seiDrips)));

    expect(apt + sei, closeTo(59.12, 0.02));
  });
}
