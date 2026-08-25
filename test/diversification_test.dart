import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/diversification.dart';
import 'package:crypto_portfolio/domain/entities/price_point.dart';

CoinSeries coin(String symbol, double weight, List<double> returns) =>
    CoinSeries(
      coinId: symbol.toLowerCase(),
      symbol: symbol,
      weight: weight,
      returns: returns,
    );

/// A deterministic wobble, so tests do not depend on a random seed.
List<double> wave(int n, {double phase = 0, double scale = 0.05}) =>
    [for (var i = 0; i < n; i++) scale * math.sin((i + phase) / 3)];

void main() {
  group('correlation', () {
    test('identical series correlate at 1', () {
      final a = wave(50);
      expect(correlation(a, a), closeTo(1.0, 1e-9));
    });

    test('mirrored series correlate at -1', () {
      final a = wave(50);
      final b = a.map((v) => -v).toList();
      expect(correlation(a, b), closeTo(-1.0, 1e-9));
    });

    test('a scaled copy still correlates at 1', () {
      // Correlation measures direction, not amplitude: a coin that moves the
      // same way twice as hard is still the same bet.
      final a = wave(50);
      final b = a.map((v) => v * 3).toList();
      expect(correlation(a, b), closeTo(1.0, 1e-9));
    });

    test('a flat series has no relationship to express', () {
      expect(correlation(wave(50), List.filled(50, 0.0)), 0);
    });

    test('too few points yields zero rather than a false signal', () {
      expect(correlation([0.01], [0.02]), 0);
      expect(correlation([], []), 0);
    });

    test('series of different length are compared on the overlap', () {
      final long = wave(80);
      final short = long.sublist(30);
      expect(correlation(long, short), closeTo(1.0, 1e-9));
    });
  });

  group('returnsFromPrices', () {
    test('turns a price path into returns', () {
      final points = [
        PricePoint(DateTime(2026, 1, 1), 100),
        PricePoint(DateTime(2026, 1, 2), 110),
        PricePoint(DateTime(2026, 1, 3), 99),
      ];
      final r = returnsFromPrices(points);
      expect(r.length, 2);
      expect(r[0], closeTo(0.10, 1e-9));
      expect(r[1], closeTo(-0.10, 1e-9));
    });

    test('sorts before differencing', () {
      final points = [
        PricePoint(DateTime(2026, 1, 3), 121),
        PricePoint(DateTime(2026, 1, 1), 100),
        PricePoint(DateTime(2026, 1, 2), 110),
      ];
      expect(returnsFromPrices(points), [closeTo(0.10, 1e-9), closeTo(0.10, 1e-9)]);
    });

    test('a single price is not a return', () {
      expect(returnsFromPrices([PricePoint(DateTime(2026, 1, 1), 100)]), isEmpty);
    });
  });

  group('diversification benefit', () {
    test('coins moving as one buy no protection', () {
      final r = wave(100);
      final report = buildDiversificationReport([
        coin('A', 0.5, r),
        coin('B', 0.5, [...r]),
      ]);

      expect(report.averageCorrelation, closeTo(1.0, 1e-9));
      expect(report.benefit, closeTo(0, 1e-6),
          reason: 'two names, one position');
      expect(report.portfolioVolatility,
          closeTo(report.weightedAverageVolatility, 1e-6));
    });

    test('opposite movers cancel almost entirely', () {
      final r = wave(100);
      final report = buildDiversificationReport([
        coin('A', 0.5, r),
        coin('B', 0.5, r.map((v) => -v).toList()),
      ]);

      expect(report.averageCorrelation, closeTo(-1.0, 1e-9));
      expect(report.benefit, greaterThan(0.95));
      expect(report.portfolioVolatility, lessThan(0.01));
    });

    test('partly independent movers land in between', () {
      final report = buildDiversificationReport([
        coin('A', 0.5, wave(120)),
        coin('B', 0.5, wave(120, phase: 4)),
      ]);

      expect(report.benefit, greaterThan(0));
      expect(report.benefit, lessThan(1));
      expect(report.portfolioVolatility,
          lessThan(report.weightedAverageVolatility));
    });

    test('names the strongest and weakest pair', () {
      final base = wave(100);
      final report = buildDiversificationReport([
        coin('TWIN1', 0.4, base),
        coin('TWIN2', 0.4, [...base]),
        coin('ODD', 0.2, base.map((v) => -v).toList()),
      ]);

      expect(report.strongest!.value, closeTo(1.0, 1e-9));
      expect({report.strongest!.a, report.strongest!.b}, {'TWIN1', 'TWIN2'});
      expect(report.weakest!.value, closeTo(-1.0, 1e-9));
      expect(report.weakest!.a == 'ODD' || report.weakest!.b == 'ODD', isTrue);
    });

    test('the matrix is symmetric with a unit diagonal', () {
      final report = buildDiversificationReport([
        coin('A', 0.5, wave(60)),
        coin('B', 0.5, wave(60, phase: 2)),
      ]);

      expect(report.matrix['A']!['A'], 1.0);
      expect(report.matrix['B']!['B'], 1.0);
      expect(report.matrix['A']!['B'], closeTo(report.matrix['B']!['A']!, 1e-12));
    });

    test('every series is measured over the same window', () {
      // A short history must not let one pair be scored on more data than
      // another, which would make the matrix internally inconsistent.
      final report = buildDiversificationReport([
        coin('LONG', 0.5, wave(200)),
        coin('SHORT', 0.5, wave(40)),
      ]);

      expect(report.observations, 40);
      expect(report.coins.every((c) => c.returns.length == 40), isTrue);
    });

    test('a lone holding cannot be diversified', () {
      final report = buildDiversificationReport([coin('A', 1.0, wave(100))]);
      expect(report.hasData, isFalse);
      expect(report.benefit, 0);
    });

    test('a thin sample is flagged rather than presented as solid', () {
      final short = buildDiversificationReport([
        coin('A', 0.5, wave(10)),
        coin('B', 0.5, wave(10, phase: 3)),
      ]);
      expect(short.hasData, isTrue);
      expect(short.isReliable, isFalse);

      final long = buildDiversificationReport([
        coin('A', 0.5, wave(120)),
        coin('B', 0.5, wave(120, phase: 3)),
      ]);
      expect(long.isReliable, isTrue);
    });
  });

  group('sectors', () {
    test('index memberships are filtered out as noise', () {
      expect(isMeaningfulSector('Layer 1 (L1)'), isTrue);
      expect(isMeaningfulSector('Decentralized Finance (DeFi)'), isTrue);
      expect(isMeaningfulSector('Ethereum Ecosystem'), isTrue);

      expect(isMeaningfulSector('GMCI Index'), isFalse);
      expect(isMeaningfulSector('Coinbase 50 Index'), isFalse);
      expect(isMeaningfulSector('FTX Holdings'), isFalse);
      expect(isMeaningfulSector('World Liberty Financial Portfolio'), isFalse);
      expect(isMeaningfulSector('Binance Listed'), isFalse);
    });

    test('weights each sector by the value that touches it', () {
      final sectors = sectorAllocation(
        categoriesByCoinId: {
          'ethereum': ['Layer 1 (L1)', 'Smart Contract Platform'],
          'solana': ['Layer 1 (L1)', 'Smart Contract Platform'],
          'aave': ['Decentralized Finance (DeFi)'],
        },
        valueByCoinId: {'ethereum': 600, 'solana': 200, 'aave': 200},
        symbolByCoinId: {
          'ethereum': 'ETH',
          'solana': 'SOL',
          'aave': 'AAVE',
        },
      );

      final l1 = sectors.firstWhere((s) => s.sector == 'Layer 1 (L1)');
      expect(l1.weight, closeTo(0.8, 1e-9));
      expect(l1.symbols, ['ETH', 'SOL']);

      final defi = sectors
          .firstWhere((s) => s.sector == 'Decentralized Finance (DeFi)');
      expect(defi.weight, closeTo(0.2, 1e-9));
    });

    test('weights overlap on purpose and need not sum to one', () {
      // A coin sits in several sectors at once; each line answers "how much of
      // the book touches this", not "how is it split".
      final sectors = sectorAllocation(
        categoriesByCoinId: {
          'ethereum': ['Layer 1 (L1)', 'Smart Contract Platform'],
        },
        valueByCoinId: {'ethereum': 1000},
        symbolByCoinId: {'ethereum': 'ETH'},
      );

      expect(sectors.length, 2);
      expect(sectors.every((s) => s.weight == 1.0), isTrue);
    });

    test('heaviest sector comes first', () {
      final sectors = sectorAllocation(
        categoriesByCoinId: {
          'a': ['Small'],
          'b': ['Big'],
          'c': ['Big'],
        },
        valueByCoinId: {'a': 100, 'b': 400, 'c': 500},
        symbolByCoinId: {'a': 'A', 'b': 'B', 'c': 'C'},
      );

      expect(sectors.first.sector, 'Big');
      expect(sectors.first.weight, closeTo(0.9, 1e-9));
    });

    test('a coin with no value contributes nothing', () {
      final sectors = sectorAllocation(
        categoriesByCoinId: {
          'held': ['Layer 1 (L1)'],
          'sold': ['Privacy'],
        },
        valueByCoinId: {'held': 1000, 'sold': 0},
        symbolByCoinId: {'held': 'H', 'sold': 'S'},
      );

      expect(sectors.length, 1);
      expect(sectors.single.sector, 'Layer 1 (L1)');
    });

    test('an empty portfolio yields no sectors', () {
      expect(
        sectorAllocation(
          categoriesByCoinId: const {},
          valueByCoinId: const {},
          symbolByCoinId: const {},
        ),
        isEmpty,
      );
    });
  });
}
