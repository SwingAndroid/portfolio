import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/domain/analytics/tax_report.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';

TransactionEntity tx(
  String id,
  TransactionType type,
  double qty,
  double price,
  DateTime date, {
  double fee = 0,
  String? note,
  String cryptoId = 'c1',
}) =>
    TransactionEntity(
      id: id,
      cryptoId: cryptoId,
      type: type,
      quantity: qty,
      pricePerCoin: price,
      date: date,
      fee: fee,
      note: note,
    );

CryptoEntity coin(
  List<TransactionEntity> txs, {
  String id = 'c1',
  String symbol = 'BTC',
  String coinId = 'bitcoin',
}) =>
    CryptoEntity(
      id: id,
      coinId: coinId,
      name: symbol,
      symbol: symbol,
      transactions: txs,
    );

void main() {
  group('disposals', () {
    test('a sale is recorded with the basis that applied that day', () {
      final ledger = coin([
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.buy, 1, 200, DateTime(2025, 2, 1)),
        tx('3', TransactionType.sell, 1, 250, DateTime(2025, 3, 1)),
      ]).ledger;

      expect(ledger.disposals.length, 1);
      final d = ledger.disposals.single;
      expect(d.proceeds, closeTo(250, 1e-9));
      expect(d.costBasis, closeTo(150, 1e-9), reason: 'average at that date');
      expect(d.gain, closeTo(100, 1e-9));
      expect(d.taxYear, 2025);
      expect(d.transactionId, '3');
    });

    test('a selling fee lowers the proceeds that get reported', () {
      final ledger = coin([
        tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.sell, 1, 200, DateTime(2025, 6, 1), fee: 12),
      ]).ledger;

      expect(ledger.disposals.single.proceeds, closeTo(188, 1e-9));
      expect(ledger.disposals.single.gain, closeTo(88, 1e-9));
    });

    test('transfers never appear as disposals', () {
      final ledger = coin([
        tx('1', TransactionType.buy, 5, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.transferOut, 2, 0, DateTime(2025, 2, 1)),
        tx('3', TransactionType.transferIn, 1, 0, DateTime(2025, 3, 1)),
      ]).ledger;

      expect(ledger.disposals, isEmpty,
          reason: 'moving coins is not a taxable disposal');
    });

    test('each sale is its own line', () {
      final ledger = coin([
        tx('1', TransactionType.buy, 3, 100, DateTime(2025, 1, 1)),
        tx('2', TransactionType.sell, 1, 150, DateTime(2025, 3, 1)),
        tx('3', TransactionType.sell, 1, 180, DateTime(2026, 3, 1)),
      ]).ledger;

      expect(ledger.disposals.map((d) => d.taxYear).toList(), [2025, 2026]);
    });
  });

  group('TaxReport', () {
    test('groups across coins into years, newest first', () {
      final report = TaxReport.from([
        coin([
          tx('a1', TransactionType.buy, 1, 100, DateTime(2024, 1, 1)),
          tx('a2', TransactionType.sell, 1, 150, DateTime(2025, 5, 1)),
        ]),
        coin(
          [
            tx('b1', TransactionType.buy, 1, 50, DateTime(2024, 1, 1),
                cryptoId: 'c2'),
            tx('b2', TransactionType.sell, 1, 80, DateTime(2025, 9, 1),
                cryptoId: 'c2'),
            tx('b3', TransactionType.buy, 1, 60, DateTime(2026, 1, 1),
                cryptoId: 'c2'),
            tx('b4', TransactionType.sell, 1, 40, DateTime(2026, 2, 1),
                cryptoId: 'c2'),
          ],
          id: 'c2',
          symbol: 'ETH',
          coinId: 'ethereum',
        ),
      ]);

      final years = report.years;
      expect(years.map((y) => y.year).toList(), [2026, 2025]);

      final y2025 = years.firstWhere((y) => y.year == 2025);
      expect(y2025.disposalCount, 2);
      expect(y2025.proceeds, closeTo(230, 1e-9));
      expect(y2025.costBasis, closeTo(150, 1e-9));
      expect(y2025.gain, closeTo(80, 1e-9));

      final y2026 = years.firstWhere((y) => y.year == 2026);
      expect(y2026.gain, closeTo(-20, 1e-9), reason: 'a loss year stays a loss');
    });

    test('disposals come back in chronological order', () {
      final report = TaxReport.from([
        coin([
          tx('a1', TransactionType.buy, 2, 100, DateTime(2024, 1, 1)),
          tx('a2', TransactionType.sell, 1, 150, DateTime(2026, 5, 1)),
          tx('a3', TransactionType.sell, 1, 160, DateTime(2025, 5, 1)),
        ]),
      ]);

      expect(report.disposals.map((d) => d.date.year).toList(), [2025, 2026]);
    });

    test('the total gain matches the sum of the years', () {
      final report = TaxReport.from([
        coin([
          tx('1', TransactionType.buy, 2, 100, DateTime(2024, 1, 1)),
          tx('2', TransactionType.sell, 1, 150, DateTime(2025, 5, 1)),
          tx('3', TransactionType.sell, 1, 90, DateTime(2026, 5, 1)),
        ]),
      ]);

      final summed = report.years.fold<double>(0, (s, y) => s + y.gain);
      expect(report.totalGain, closeTo(summed, 1e-9));
      expect(report.totalGain, closeTo(40, 1e-9));
    });

    test('forYear narrows to a single return', () {
      final report = TaxReport.from([
        coin([
          tx('1', TransactionType.buy, 2, 100, DateTime(2024, 1, 1)),
          tx('2', TransactionType.sell, 1, 150, DateTime(2025, 5, 1)),
          tx('3', TransactionType.sell, 1, 90, DateTime(2026, 5, 1)),
        ]),
      ]);

      expect(report.forYear(2025).length, 1);
      expect(report.forYear(2025).single.symbol, 'BTC');
      expect(report.forYear(2023), isEmpty);
    });

    test('a portfolio that never sold produces an empty report', () {
      final report = TaxReport.from([
        coin([tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1))]),
      ]);

      expect(report.isEmpty, isTrue);
      expect(report.years, isEmpty);
      expect(report.totalGain, 0);
    });
  });

  group('CSV', () {
    test('transactions export carries a header and every row', () {
      final csv = transactionsCsv([
        coin([
          tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1), fee: 2),
          tx('2', TransactionType.sell, 1, 150, DateTime(2025, 3, 1)),
        ]),
      ]);

      final lines = csv.split('\n');
      expect(lines.first, startsWith('date,symbol,coin_id,type'));
      expect(lines.length, 3);
      expect(lines[1], contains('buy'));
      expect(lines[1], contains('102'), reason: 'total includes the fee');
      expect(lines[2], contains('sell'));
    });

    test('a note containing a comma cannot shift the columns', () {
      final csv = transactionsCsv([
        coin([
          tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1),
              note: 'DCA, weekly'),
        ]),
      ]);

      expect(csv, contains('"DCA, weekly"'));
      // Header has 10 columns; the quoted note must not add an eleventh.
      final header = csv.split('\n').first.split(',').length;
      expect(header, 10);
    });

    test('an embedded quote is doubled, not dropped', () {
      final csv = transactionsCsv([
        coin([
          tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1),
              note: 'said "buy"'),
        ]),
      ]);

      expect(csv, contains('"said ""buy"""'));
    });

    test('the exported date is the local one the user entered', () {
      // A sale entered on 1 January must not be reported in the previous
      // year because the exporter shifted it to UTC.
      final csv = transactionsCsv([
        coin([tx('1', TransactionType.buy, 1, 100, DateTime(2024, 1, 1))]),
      ]);

      expect(csv.split('\n')[1], startsWith('2024-01-01T00:00:00'));
      expect(csv, isNot(contains('2023-12-31')));
    });

    test('the disposal date agrees with its tax year', () {
      final report = TaxReport.from([
        coin([
          tx('1', TransactionType.buy, 1, 100, DateTime(2023, 6, 1)),
          tx('2', TransactionType.sell, 1, 150, DateTime(2024, 1, 1)),
        ]),
      ]);

      final line = disposalsCsv(report).split('\n')[1];
      expect(line, startsWith('2024-01-01'));
      expect(line.split(',')[1], '2024',
          reason: 'date and tax_year must name the same return');
    });

    test('rows are ordered oldest first', () {
      final csv = transactionsCsv([
        coin([
          tx('late', TransactionType.buy, 1, 100, DateTime(2026, 1, 1)),
          tx('early', TransactionType.buy, 1, 100, DateTime(2024, 1, 1)),
        ]),
      ]);

      final lines = csv.split('\n');
      expect(lines[1], contains('2024'));
      expect(lines[2], contains('2026'));
    });

    test('disposals export reports gain per sale', () {
      final report = TaxReport.from([
        coin([
          tx('1', TransactionType.buy, 1, 100, DateTime(2025, 1, 1)),
          tx('2', TransactionType.sell, 1, 150, DateTime(2025, 6, 1)),
        ]),
      ]);

      final csv = disposalsCsv(report);
      final lines = csv.split('\n');

      expect(lines.first, startsWith('date,tax_year,symbol'));
      expect(lines.length, 2);
      expect(lines[1], contains('2025'));
      expect(lines[1], contains('BTC'));
      expect(lines[1], contains('50'), reason: 'the gain');
    });

    test('an empty report still exports its header', () {
      final csv = disposalsCsv(const TaxReport([]));
      expect(csv.split('\n').length, 1);
      expect(csv, startsWith('date,tax_year'));
    });
  });
}
