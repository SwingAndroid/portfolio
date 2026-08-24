import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../domain/entities/crypto_entity.dart';
import '../../../domain/entities/value_snapshot.dart';

abstract class ValueHistoryStore {
  /// Records the portfolio for [date], replacing any earlier entry for the
  /// same day so the last reading of the day wins.
  Future<void> record(ValueSnapshot snapshot);

  /// Every snapshot, oldest first.
  Future<List<ValueSnapshot>> all();

  /// Snapshots taken on or after [from], oldest first.
  Future<List<ValueSnapshot>> since(DateTime from);

  Future<void> clear();
}

class ValueHistoryStoreImpl implements ValueHistoryStore {
  final Box<String> box;

  ValueHistoryStoreImpl(this.box);

  @override
  Future<void> record(ValueSnapshot snapshot) async {
    await box.put(snapshot.key, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<List<ValueSnapshot>> all() async {
    final out = <ValueSnapshot>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        final snap = ValueSnapshot.fromEntry(key as String, decoded);
        if (snap != null) out.add(snap);
      } catch (_) {
        // A corrupt row must not take the whole history down with it.
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  @override
  Future<List<ValueSnapshot>> since(DateTime from) async {
    final cutoff = DateTime(from.year, from.month, from.day);
    final everything = await all();
    return everything.where((s) => !s.date.isBefore(cutoff)).toList();
  }

  @override
  Future<void> clear() async => box.clear();
}

/// Decides whether today's portfolio is worth recording, and records it.
///
/// The guard is the important part. Offline, every price falls back to zero,
/// so a naive snapshot would write a portfolio worth nothing and leave a
/// permanent false crash in the curve. A reading is only trusted when every
/// coin actually held came back with a price.
class PortfolioSnapshotRecorder {
  final ValueHistoryStore store;

  PortfolioSnapshotRecorder(this.store);

  /// Returns the snapshot written, or null when the reading was rejected.
  Future<ValueSnapshot?> recordIfComplete(
    List<CryptoEntity> cryptos, {
    DateTime? now,
  }) async {
    if (cryptos.isEmpty) return null;

    var value = 0.0;
    var invested = 0.0;
    for (final crypto in cryptos) {
      // A coin held with no price means the quote failed. Partial data would
      // understate the total, so the whole reading is discarded.
      if (crypto.totalHoldings > 0 && crypto.currentPrice <= 0) return null;
      value += crypto.holdingsValue;
      invested += crypto.totalCost;
    }

    if (value <= 0) return null;

    final today = now ?? DateTime.now();
    final snapshot = ValueSnapshot(
      date: DateTime(today.year, today.month, today.day),
      value: value,
      invested: invested,
    );
    await store.record(snapshot);
    return snapshot;
  }
}
