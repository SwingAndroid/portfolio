@Tags(['migration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:crypto_portfolio/data/models/transaction_model.dart';

/// Reads the box left behind by `migration_simulation_test.dart` — written by
/// the *previous* adapter, before `swapId` existed — using the current one.
///
/// This is the only proof that matters for a schema change: not that the new
/// code round-trips its own writes, but that it still understands bytes the
/// old code produced. Nothing here writes, so the file keeps its original
/// 8-field layout however often this runs.
void main() {
  final dir = Directory('${Directory.systemTemp.path}/hive_migration_sim');

  setUpAll(() {
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TransactionModelAdapter());
    }
  });

  test('records written before swapId existed still load', () async {
    expect(File('${dir.path}/sim.hive').existsSync(), isTrue,
        reason: 'run migration_simulation_test.dart first to lay down a box '
            'in the older format');

    final box = await Hive.openBox<TransactionModel>('sim');

    expect(box.length, 455,
        reason: '454 transactions plus the deliberately sparse one');

    // Nothing shifted: the fields the old writer did emit are still correct.
    final first = box.get('t0')!;
    expect(first.id, 't0');
    expect(first.cryptoId, 'c0');
    expect(first.quantity, 1.5);
    expect(first.pricePerCoin, 100.0);
    expect(first.fee, 2.5);
    expect(first.date, DateTime(2025, 1, 1));

    // The field the old writer never wrote comes back absent, not garbage.
    expect(first.swapId, isNull);
    expect(box.values.every((t) => t.swapId == null), isTrue,
        reason: 'no record can invent a value for a field that did not exist');

    // The sparse record still has its optionals absent rather than shifted.
    final legacy = box.get('legacy')!;
    expect(legacy.note, isNull);
    expect(legacy.fee, isNull);
    expect(legacy.swapId, isNull);
    expect(legacy.quantity, 1);
    expect(legacy.pricePerCoin, 100);

    // Every type index survives, including reward.
    expect(box.values.map((t) => t.typeIndex).toSet(), {0, 1, 2, 3, 4});

    // And the whole set still maps to entities without throwing.
    final entities = box.values.map((t) => t.toEntity()).toList();
    expect(entities.length, 455);
    expect(entities.every((e) => e.swapId == null), isTrue);
    // Hive iterates in its own order, so name the record rather than assume.
    expect(box.get('t0')!.toEntity().fee, 2.5);

    await box.close();
  });

  tearDownAll(() async => Hive.close());
}
