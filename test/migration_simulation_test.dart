@Tags(['migration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:crypto_portfolio/data/models/transaction_model.dart';

/// Writes a Hive box in the *current* on-disk format, then reads it back.
///
/// Run once before adding a field and once after: the second run proves that
/// records written by the older build still load, field for field, with the
/// new one. This is the only check that actually exercises the binary format
/// rather than reasoning about it.
///
///   flutter test test/migration_simulation_test.dart
void main() {
  final dir = Directory('${Directory.systemTemp.path}/hive_migration_sim');

  setUpAll(() {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TransactionModelAdapter());
    }
  });

  test('a box written today reads back intact', () async {
    final box = await Hive.openBox<TransactionModel>('sim');
    await box.clear();

    // Same shape and scale as the live portfolio.
    for (var i = 0; i < 454; i++) {
      await box.put(
        't$i',
        TransactionModel(
          id: 't$i',
          cryptoId: 'c${i % 8}',
          typeIndex: i % 5,
          quantity: 1.5 + i,
          pricePerCoin: 100.0 + i,
          date: DateTime(2025, 1, 1).add(Duration(days: i)),
          note: i % 7 == 0 ? 'note $i' : null,
          fee: i % 3 == 0 ? 2.5 : null,
        ),
      );
    }
    await box.close();

    final reopened = await Hive.openBox<TransactionModel>('sim');
    expect(reopened.length, 454, reason: 'every record survived the round trip');

    final first = reopened.get('t0')!;
    expect(first.id, 't0');
    expect(first.cryptoId, 'c0');
    expect(first.quantity, 1.5);
    expect(first.pricePerCoin, 100.0);
    expect(first.fee, 2.5);
    expect(first.date, DateTime(2025, 1, 1));

    final sparse = reopened.get('t1')!;
    expect(sparse.note, isNull);
    expect(sparse.fee, isNull, reason: 'an absent optional stays absent');

    // Every type index round-trips, including the newest one.
    final types = reopened.values.map((t) => t.typeIndex).toSet();
    expect(types, {0, 1, 2, 3, 4});

    await reopened.close();
  });

  test('reading a record written before a field existed yields null for it',
      () async {
    // The guarantee the whole scheme rests on: the adapter reads only as many
    // fields as the record declares, so an index the writer never wrote comes
    // back as null rather than throwing or shifting the others.
    final box = await Hive.openBox<TransactionModel>('sim');
    final legacyShaped = TransactionModel(
      id: 'legacy',
      cryptoId: 'c1',
      typeIndex: 0,
      quantity: 1,
      pricePerCoin: 100,
      date: DateTime(2024, 1, 1),
      // note and fee omitted, exactly as an older writer would leave them
    );
    await box.put('legacy', legacyShaped);
    await box.close();

    final reopened = await Hive.openBox<TransactionModel>('sim');
    final read = reopened.get('legacy')!;

    expect(read.note, isNull);
    expect(read.fee, isNull);
    expect(read.toEntity().fee, 0, reason: 'null degrades to zero, not a crash');
    expect(read.quantity, 1, reason: 'earlier fields are not shifted');
    expect(read.pricePerCoin, 100);

    await reopened.close();
  });

  tearDownAll(() async {
    await Hive.close();
  });
}
