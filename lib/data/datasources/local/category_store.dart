import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Remembers each coin's sector labels on disk.
///
/// Sectors cost one `/coins/{id}` call each and essentially never change, so
/// fetching them on every visit would spend a third of the device's per-minute
/// budget to learn that Ethereum is still a Layer 1.
abstract class CategoryStore {
  Future<List<String>?> get(String coinId);
  Future<void> put(String coinId, List<String> categories);
}

class CategoryStoreImpl implements CategoryStore {
  final Box<String> box;

  /// Long enough that the call is rare, short enough that a genuine
  /// reclassification is picked up within a month.
  static const Duration ttl = Duration(days: 30);

  CategoryStoreImpl(this.box);

  @override
  Future<List<String>?> get(String coinId) async {
    final raw = box.get(coinId);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final at = DateTime.tryParse(decoded['at'] as String? ?? '');
      if (at == null || DateTime.now().difference(at) > ttl) return null;
      final list = decoded['c'];
      if (list is! List) return null;
      return list.whereType<String>().toList();
    } catch (_) {
      // A corrupt row simply counts as a miss.
      return null;
    }
  }

  @override
  Future<void> put(String coinId, List<String> categories) async {
    await box.put(
      coinId,
      jsonEncode({'c': categories, 'at': DateTime.now().toIso8601String()}),
    );
  }
}
