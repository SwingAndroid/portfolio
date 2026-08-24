import '../entities/crypto_entity.dart';
import '../entities/transaction_entity.dart';
import 'cost_basis_ledger.dart';

/// A disposal with the coin it belonged to, so a report can span the whole
/// portfolio rather than one position at a time.
class RealizedDisposal {
  final String symbol;
  final String coinId;
  final Disposal disposal;

  const RealizedDisposal({
    required this.symbol,
    required this.coinId,
    required this.disposal,
  });

  DateTime get date => disposal.date;
  double get gain => disposal.gain;
}

/// Realized results for one calendar year.
class TaxYearSummary {
  final int year;
  final double proceeds;
  final double costBasis;
  final int disposalCount;

  const TaxYearSummary({
    required this.year,
    required this.proceeds,
    required this.costBasis,
    required this.disposalCount,
  });

  double get gain => proceeds - costBasis;

  double get gainPercent => costBasis > 0 ? (gain / costBasis) * 100 : 0;
}

/// Realized gains across the portfolio, grouped by calendar year.
///
/// Built from the same chronological walk the P&L uses, so what a return
/// reports and what the app displays cannot disagree. Only sales appear: a
/// transfer moves coins without disposing of them and is not a taxable event
/// here.
class TaxReport {
  final List<RealizedDisposal> disposals;

  const TaxReport(this.disposals);

  factory TaxReport.from(List<CryptoEntity> cryptos) {
    final out = <RealizedDisposal>[];
    for (final crypto in cryptos) {
      for (final d in crypto.ledger.disposals) {
        out.add(RealizedDisposal(
          symbol: crypto.symbol,
          coinId: crypto.coinId,
          disposal: d,
        ));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return TaxReport(out);
  }

  bool get isEmpty => disposals.isEmpty;

  /// Years that actually contain a sale, most recent first.
  List<TaxYearSummary> get years {
    final byYear = <int, List<RealizedDisposal>>{};
    for (final d in disposals) {
      byYear.putIfAbsent(d.disposal.taxYear, () => []).add(d);
    }

    final out = [
      for (final entry in byYear.entries)
        TaxYearSummary(
          year: entry.key,
          proceeds:
              entry.value.fold(0.0, (s, d) => s + d.disposal.proceeds),
          costBasis:
              entry.value.fold(0.0, (s, d) => s + d.disposal.costBasis),
          disposalCount: entry.value.length,
        )
    ];
    out.sort((a, b) => b.year.compareTo(a.year));
    return out;
  }

  List<RealizedDisposal> forYear(int year) =>
      disposals.where((d) => d.disposal.taxYear == year).toList();

  double get totalGain =>
      disposals.fold(0.0, (s, d) => s + d.gain);
}

// ── CSV ──────────────────────────────────────────────────────────────────────

/// Quotes a field only when it needs it, and doubles any embedded quote —
/// a note containing a comma must not shift every later column.
String _csv(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[",\n\r]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String _row(List<Object?> cells) => cells.map(_csv).join(',');

/// Local wall-clock time, exactly as entered — never converted.
///
/// Converting to UTC pushed a transaction dated 1 January into the previous
/// calendar year for anyone east of Greenwich, while `tax_year` was derived
/// from the local date. The two disagreed on which return the sale belonged
/// to, which is the one thing a tax export must never get wrong.
String _date(DateTime d) => d.toIso8601String();

/// Every transaction, for import into a spreadsheet or another tracker.
String transactionsCsv(List<CryptoEntity> cryptos) {
  final rows = <String>[
    _row([
      'date',
      'symbol',
      'coin_id',
      'type',
      'quantity',
      'price_per_coin',
      'fee',
      'total',
      'note',
      'transaction_id',
    ])
  ];

  final all = <({CryptoEntity coin, TransactionEntity tx})>[];
  for (final crypto in cryptos) {
    for (final t in crypto.transactions) {
      all.add((coin: crypto, tx: t));
    }
  }
  all.sort((a, b) => a.tx.date.compareTo(b.tx.date));

  for (final entry in all) {
    final t = entry.tx;
    rows.add(_row([
      _date(t.date),
      entry.coin.symbol,
      entry.coin.coinId,
      t.type.name,
      t.quantity,
      t.pricePerCoin,
      t.fee,
      t.type.addsHoldings ? t.grossCost : t.netProceeds,
      t.note,
      t.id,
    ]));
  }

  return rows.join('\n');
}

/// Realized disposals, the shape a tax return needs.
String disposalsCsv(TaxReport report) {
  final rows = <String>[
    _row([
      'date',
      'tax_year',
      'symbol',
      'quantity',
      'proceeds',
      'cost_basis',
      'gain',
      'gain_percent',
      'transaction_id',
    ])
  ];

  for (final d in report.disposals) {
    rows.add(_row([
      _date(d.date),
      d.disposal.taxYear,
      d.symbol,
      d.disposal.quantity,
      d.disposal.proceeds,
      d.disposal.costBasis,
      d.disposal.gain,
      d.disposal.gainPercent.toStringAsFixed(2),
      d.disposal.transactionId,
    ]));
  }

  return rows.join('\n');
}
