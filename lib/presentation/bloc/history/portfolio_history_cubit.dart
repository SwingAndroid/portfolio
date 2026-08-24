import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/portfolio_history_service.dart';
import '../../../domain/entities/crypto_entity.dart';
import 'portfolio_history_state.dart';

class PortfolioHistoryCubit extends Cubit<PortfolioHistoryState> {
  final PortfolioHistoryService service;

  PortfolioHistoryCubit({required this.service})
      : super(const PortfolioHistoryInitial());

  /// Ranges offered by the chart. A year is the ceiling the free CoinGecko
  /// tier will reconstruct; anything longer can only come from snapshots this
  /// app has recorded itself.
  static const ranges = [(30, '30D'), (90, '90D'), (365, '1Y')];

  /// Windows already assembled this session, so switching ranges back and
  /// forth does not re-hit the network.
  final Set<int> _fetched = {};

  Future<void> load(
    List<CryptoEntity> cryptos, {
    int days = 90,
    bool force = false,
  }) async {
    if (!force && _fetched.contains(days) && state is PortfolioHistoryLoaded) {
      final current = state as PortfolioHistoryLoaded;
      if (current.days == days) return;
    }

    emit(PortfolioHistoryLoading(days));
    try {
      final history = await service.load(cryptos: cryptos, days: days);
      if (history.backfillError == null) _fetched.add(days);
      emit(PortfolioHistoryLoaded(history, days));
    } catch (e) {
      // The service already degrades gracefully; this only catches the
      // unexpected. An empty curve is better than a broken page.
      emit(PortfolioHistoryLoaded(
        PortfolioHistory(points: const [], backfillError: e),
        days,
      ));
    }
  }

  /// Drops the cache so the next load re-checks for gaps — used after new
  /// transactions land.
  void invalidate() => _fetched.clear();
}
