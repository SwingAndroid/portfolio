import '../../domain/analytics/basis_gap.dart';
import '../../domain/repositories/crypto_repository.dart';

/// What a conversion actually managed to write.
///
/// Rows go in one at a time, so a failure part way through leaves the earlier
/// ones converted. That is safe — each write keeps the original id, so
/// repeating it overwrites rather than duplicates — but it must be reported
/// rather than reported as a clean success.
class BackfillResult {
  final int written;
  final List<String> failedIds;

  const BackfillResult({required this.written, this.failedIds = const []});

  bool get hasFailures => failedIds.isNotEmpty;
}

/// Puts a price on holdings that were recorded without one.
class BasisBackfillService {
  final CryptoRepository repository;

  BasisBackfillService(this.repository);

  /// Prices every gap for one coin.
  ///
  /// A single chart covers every date, so forty gaps cost one request rather
  /// than forty — which matters against a shared rate limit.
  Future<List<ResolvedGap>> priceGaps(CoinBasisGaps gaps) async {
    final chart = await repository.getMarketChart(gaps.coinId, days: 365);
    return resolveGaps(gaps.transactions, chart);
  }

  /// Rewrites the chosen rows as rewards booked at their own day's price.
  ///
  /// Each write goes to Hive first and the cloud second, the same path a
  /// hand-typed edit takes, so nothing here depends on being online.
  Future<BackfillResult> convert(Iterable<ResolvedGap> chosen) async {
    var written = 0;
    final failed = <String>[];

    for (final gap in chosen) {
      // An unpriceable row is skipped rather than written at zero, which would
      // leave it exactly as broken while looking like it had been handled.
      if (!gap.resolvable) continue;
      try {
        await repository.addTransaction(gap.asReward);
        written++;
      } catch (_) {
        failed.add(gap.transaction.id);
      }
    }

    return BackfillResult(written: written, failedIds: failed);
  }
}
