import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/data/datasources/local/value_history_store.dart';
import 'package:crypto_portfolio/domain/entities/crypto_entity.dart';
import 'package:crypto_portfolio/domain/entities/transaction_entity.dart';
import 'package:crypto_portfolio/domain/entities/value_snapshot.dart';

class MemHistory implements ValueHistoryStore {
  final Map<String, ValueSnapshot> rows = {};

  @override
  Future<void> record(ValueSnapshot s) async => rows[s.key] = s;

  @override
  Future<List<ValueSnapshot>> all() async {
    final out = rows.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  @override
  Future<List<ValueSnapshot>> since(DateTime from) async {
    final cutoff = DateTime(from.year, from.month, from.day);
    return (await all()).where((s) => !s.date.isBefore(cutoff)).toList();
  }

  @override
  Future<void> clear() async => rows.clear();
}

CryptoEntity coin({
  required String id,
  required double qty,
  required double buyPrice,
  required double price,
}) =>
    CryptoEntity(
      id: id,
      coinId: id,
      name: id,
      symbol: id.toUpperCase(),
      currentPrice: price,
      transactions: [
        TransactionEntity(
          id: '$id-1',
          cryptoId: id,
          type: TransactionType.buy,
          quantity: qty,
          pricePerCoin: buyPrice,
          date: DateTime(2026, 1, 1),
        ),
      ],
    );

void main() {
  late MemHistory store;
  late PortfolioSnapshotRecorder recorder;

  setUp(() {
    store = MemHistory();
    recorder = PortfolioSnapshotRecorder(store);
  });

  group('snapshot recording', () {
    test('records value and capital engaged when everything is priced',
        () async {
      final snap = await recorder.recordIfComplete(
        [
          coin(id: 'btc', qty: 1, buyPrice: 50000, price: 60000),
          coin(id: 'eth', qty: 2, buyPrice: 2000, price: 2500),
        ],
        now: DateTime(2026, 8, 24, 13, 45),
      );

      expect(snap, isNotNull);
      expect(snap!.value, closeTo(65000, 1e-9));
      expect(snap.invested, closeTo(54000, 1e-9));
      expect(snap.key, '2026-08-24');
      expect(snap.date.hour, 0, reason: 'normalised to the day');
      expect(store.rows.length, 1);
    });

    test('refuses a reading when a held coin has no price', () async {
      // This is the offline case: prices collapse to zero, and a naive
      // snapshot would burn a permanent false crash into the curve.
      final snap = await recorder.recordIfComplete([
        coin(id: 'btc', qty: 1, buyPrice: 50000, price: 60000),
        coin(id: 'eth', qty: 2, buyPrice: 2000, price: 0),
      ]);

      expect(snap, isNull);
      expect(store.rows, isEmpty, reason: 'partial data is worse than none');
    });

    test('refuses when the whole portfolio prices at zero', () async {
      final snap = await recorder.recordIfComplete([
        coin(id: 'btc', qty: 1, buyPrice: 50000, price: 0),
      ]);
      expect(snap, isNull);
      expect(store.rows, isEmpty);
    });

    test('an empty portfolio records nothing', () async {
      expect(await recorder.recordIfComplete([]), isNull);
      expect(store.rows, isEmpty);
    });

    test('a coin sold down to zero does not block the snapshot', () async {
      // No holdings left, so a missing price for it is harmless.
      final sold = CryptoEntity(
        id: 'old',
        coinId: 'old',
        name: 'old',
        symbol: 'OLD',
        currentPrice: 0,
        transactions: [
          TransactionEntity(
              id: 'a',
              cryptoId: 'old',
              type: TransactionType.buy,
              quantity: 1,
              pricePerCoin: 100,
              date: DateTime(2026, 1, 1)),
          TransactionEntity(
              id: 'b',
              cryptoId: 'old',
              type: TransactionType.sell,
              quantity: 1,
              pricePerCoin: 150,
              date: DateTime(2026, 2, 1)),
        ],
      );

      final snap = await recorder.recordIfComplete(
        [coin(id: 'btc', qty: 1, buyPrice: 50000, price: 60000), sold],
      );

      expect(snap, isNotNull);
      expect(snap!.value, closeTo(60000, 1e-9));
    });

    test('the last reading of a day replaces the earlier one', () async {
      await recorder.recordIfComplete(
        [coin(id: 'btc', qty: 1, buyPrice: 50000, price: 60000)],
        now: DateTime(2026, 8, 24, 9),
      );
      await recorder.recordIfComplete(
        [coin(id: 'btc', qty: 1, buyPrice: 50000, price: 61000)],
        now: DateTime(2026, 8, 24, 21),
      );

      expect(store.rows.length, 1, reason: 'one row per day');
      expect(store.rows['2026-08-24']!.value, closeTo(61000, 1e-9));
    });

    test('successive days accumulate into a curve', () async {
      for (var day = 1; day <= 5; day++) {
        await recorder.recordIfComplete(
          [coin(id: 'btc', qty: 1, buyPrice: 50000, price: 50000.0 + day * 100)],
          now: DateTime(2026, 8, day),
        );
      }

      final history = await store.all();
      expect(history.length, 5);
      expect(history.first.date, DateTime(2026, 8, 1));
      expect(history.last.value, closeTo(50500, 1e-9));
      expect(history.map((s) => s.value).toList(),
          orderedEquals([50100.0, 50200.0, 50300.0, 50400.0, 50500.0]));
    });

    test('since() trims to the requested window', () async {
      for (var day = 1; day <= 10; day++) {
        await recorder.recordIfComplete(
          [coin(id: 'btc', qty: 1, buyPrice: 50000, price: 60000)],
          now: DateTime(2026, 8, day),
        );
      }

      final recent = await store.since(DateTime(2026, 8, 7));
      expect(recent.length, 4);
      expect(recent.first.date, DateTime(2026, 8, 7));
    });
  });

  group('ValueSnapshot serialisation', () {
    test('round-trips through the stored form', () {
      final original = ValueSnapshot(
          date: DateTime(2026, 8, 24), value: 22046.31, invested: 32109.04);
      final restored =
          ValueSnapshot.fromEntry(original.key, original.toJson())!;

      expect(restored.date, original.date);
      expect(restored.value, original.value);
      expect(restored.invested, original.invested);
      expect(restored.profitLoss, closeTo(-10062.73, 1e-6));
      expect(restored.profitLossPercent, closeTo(-31.34, 0.01));
    });

    test('rejects malformed rows instead of throwing', () {
      expect(ValueSnapshot.fromEntry('not-a-date', {'v': 1, 'i': 2}), isNull);
      expect(ValueSnapshot.fromEntry('2026-08-24', {'v': 'x', 'i': 2}), isNull);
      expect(ValueSnapshot.fromEntry('2026-08-24', {}), isNull);
      expect(ValueSnapshot.fromEntry('2026-8', {'v': 1, 'i': 2}), isNull);
    });

    test('pads the key so days sort lexicographically', () {
      expect(ValueSnapshot.keyFor(DateTime(2026, 1, 5)), '2026-01-05');
      final keys = [
        ValueSnapshot.keyFor(DateTime(2026, 1, 5)),
        ValueSnapshot.keyFor(DateTime(2026, 10, 2)),
        ValueSnapshot.keyFor(DateTime(2026, 2, 11)),
      ]..sort();
      expect(keys, ['2026-01-05', '2026-02-11', '2026-10-02']);
    });

    test('a zero cost basis does not divide by zero', () {
      final free =
          ValueSnapshot(date: DateTime(2026, 8, 24), value: 500, invested: 0);
      expect(free.profitLossPercent, 0);
      expect(free.profitLoss, 500);
    });
  });
}
