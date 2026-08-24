/// One day's closing picture of the whole portfolio.
///
/// CoinGecko's free tier refuses any historical window beyond 365 days, on
/// every endpoint. Recording our own snapshot each day builds a history that
/// grows past that ceiling and cannot be taken away — the only route to a
/// multi-year equity curve without a paid plan.
class ValueSnapshot {
  final DateTime date;

  /// Market value of everything held that day.
  final double value;

  /// Net capital engaged: everything bought, less everything sold.
  final double invested;

  const ValueSnapshot({
    required this.date,
    required this.value,
    required this.invested,
  });

  double get profitLoss => value - invested;

  double get profitLossPercent =>
      invested == 0 ? 0 : (profitLoss / invested) * 100;

  /// Day key, stable and sortable: `2026-08-24`.
  static String keyFor(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String get key => keyFor(date);

  Map<String, dynamic> toJson() => {'v': value, 'i': invested};

  static ValueSnapshot? fromEntry(String key, Map<String, dynamic> json) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;

    final v = json['v'];
    final i = json['i'];
    if (v is! num || i is! num) return null;

    return ValueSnapshot(
      date: DateTime(y, m, d),
      value: v.toDouble(),
      invested: i.toDouble(),
    );
  }
}
