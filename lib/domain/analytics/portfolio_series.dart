import '../entities/crypto_entity.dart';
import '../entities/transaction_entity.dart';
import '../entities/value_snapshot.dart';

/// Looks up a coin's price on a given day. Returns null when that day is not
/// covered, which makes the whole day unusable.
typedef PriceAt = double? Function(String coinId, DateTime day);

/// Running position for one coin as the sweep advances through time.
class _Position {
  double quantity = 0;
  double invested = 0;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Rebuilds the daily value of the portfolio between [from] and [to].
///
/// Used to fill gaps in the recorded history: within CoinGecko's 365-day
/// window any missing day can be reconstructed exactly, because holdings come
/// from local transactions and only the price has to be fetched. Past that
/// window nothing can be rebuilt, which is why the daily snapshot exists.
///
/// Days where any held coin has no price are omitted rather than guessed — a
/// partial total understates the portfolio, and a wrong point in a curve is
/// worse than a missing one.
List<ValueSnapshot> buildDailySeries({
  required List<CryptoEntity> cryptos,
  required DateTime from,
  required DateTime to,
  required PriceAt priceAt,
}) {
  final start = _day(from);
  final end = _day(to);
  if (end.isBefore(start)) return const [];

  // One chronological pass over every transaction, consumed as the day
  // pointer advances — rather than re-scanning the whole history per day.
  final events = <TransactionEntity>[];
  final coinOf = <String, String>{};
  for (final crypto in cryptos) {
    coinOf[crypto.id] = crypto.coinId;
    events.addAll(crypto.transactions);
  }
  events.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });

  final positions = <String, _Position>{
    for (final c in cryptos) c.id: _Position(),
  };

  var cursor = 0;
  final out = <ValueSnapshot>[];

  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    // Apply everything that happened up to and including this day.
    while (cursor < events.length && !_day(events[cursor].date).isAfter(d)) {
      final t = events[cursor];
      final pos = positions[t.cryptoId];
      cursor++;
      if (pos == null) continue; // transaction for a coin no longer tracked
      if (t.type.addsHoldings) {
        pos.quantity += t.quantity;
        // Income adds coins without adding capital.
        pos.invested += t.capitalIn;
      } else {
        pos.quantity -= t.quantity;
        pos.invested -= t.netProceeds;
      }
    }

    var value = 0.0;
    var invested = 0.0;
    var complete = true;

    for (final crypto in cryptos) {
      final pos = positions[crypto.id]!;
      invested += pos.invested;
      if (pos.quantity <= 0) continue;

      final price = priceAt(coinOf[crypto.id]!, d);
      if (price == null) {
        complete = false;
        break;
      }
      value += pos.quantity * price;
    }

    if (!complete) continue;
    if (value <= 0 && invested == 0) continue; // nothing held, nothing spent

    out.add(ValueSnapshot(date: d, value: value, invested: invested));
  }

  return out;
}

/// Indexes market-chart samples into a day-keyed lookup, carrying the last
/// known price forward across gaps within the covered range.
///
/// CoinGecko returns roughly one sample per day on a daily interval, but the
/// spacing is not guaranteed; carrying forward avoids punching holes in the
/// curve for a merely missing sample. Nothing is carried before the first
/// sample — that would be inventing history.
class DailyPriceIndex {
  final Map<String, Map<String, double>> _byCoin = {};
  final Map<String, DateTime> _earliest = {};

  void add(String coinId, Iterable<({DateTime time, double price})> samples) {
    final byDay = _byCoin.putIfAbsent(coinId, () => {});
    DateTime? earliest;
    for (final s in samples) {
      final key = ValueSnapshot.keyFor(s.time);
      // Later samples on the same day win: closing price for that day.
      byDay[key] = s.price;
      if (earliest == null || s.time.isBefore(earliest)) earliest = s.time;
    }
    if (earliest != null) _earliest[coinId] = _day(earliest);
  }

  double? priceAt(String coinId, DateTime day) {
    final byDay = _byCoin[coinId];
    if (byDay == null || byDay.isEmpty) return null;

    final first = _earliest[coinId];
    if (first != null && day.isBefore(first)) return null;

    var probe = _day(day);
    // Walk back at most a week for a missing sample before giving up.
    for (var i = 0; i < 7; i++) {
      final hit = byDay[ValueSnapshot.keyFor(probe)];
      if (hit != null) return hit;
      probe = probe.subtract(const Duration(days: 1));
      if (first != null && probe.isBefore(first)) return null;
    }
    return null;
  }

  bool covers(String coinId) => _byCoin[coinId]?.isNotEmpty ?? false;
}

/// Capital engaged on each day of a range, keyed by [ValueSnapshot.keyFor].
///
/// Derived purely from local transactions, so it stays correct even for a
/// snapshot recorded before a back-dated transaction was entered. Value needs
/// prices and can only be observed; capital engaged is always recomputable,
/// so it never has to be trusted from storage.
Map<String, double> investedByDay({
  required List<CryptoEntity> cryptos,
  required DateTime from,
  required DateTime to,
}) {
  final start = _day(from);
  final end = _day(to);
  final out = <String, double>{};
  if (end.isBefore(start)) return out;

  final events = <TransactionEntity>[];
  for (final c in cryptos) {
    events.addAll(c.transactions);
  }
  events.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  });

  var invested = 0.0;
  var cursor = 0;

  // Everything before the window still counts towards the running total.
  while (cursor < events.length && _day(events[cursor].date).isBefore(start)) {
    final t = events[cursor++];
    invested += t.type.addsHoldings ? t.capitalIn : -t.netProceeds;
  }

  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    while (cursor < events.length && !_day(events[cursor].date).isAfter(d)) {
      final t = events[cursor++];
      invested += t.type.addsHoldings ? t.capitalIn : -t.netProceeds;
    }
    out[ValueSnapshot.keyFor(d)] = invested;
  }

  return out;
}
