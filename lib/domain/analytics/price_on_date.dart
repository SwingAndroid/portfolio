import '../entities/price_point.dart';

/// Picks the price that applied on [day] from a series of samples.
///
/// A reward is worth what the coin cost when it landed, not what it costs
/// now — filling in today's figure for something received last week would
/// quietly record the wrong income and the wrong cost basis.
///
/// Returns the latest sample on or before [day], so a gap in the series falls
/// back to the last known close rather than to nothing. Never looks forward:
/// a price that had not happened yet cannot be what something was worth.
double? priceOnDate(List<PricePoint> samples, DateTime day) {
  if (samples.isEmpty) return null;

  final target = DateTime(day.year, day.month, day.day, 23, 59, 59);
  PricePoint? best;

  for (final sample in samples) {
    if (sample.time.isAfter(target)) continue;
    if (best == null || sample.time.isAfter(best.time)) best = sample;
  }

  // Everything on record is later than the day asked for.
  return best?.price;
}

/// Whether [day] is today, in local time.
bool isToday(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  return day.year == today.year &&
      day.month == today.month &&
      day.day == today.day;
}
