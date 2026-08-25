import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/basis_backfill_service.dart';
import '../../../domain/analytics/basis_gap.dart';

/// Drives the review of one coin's priceless holdings.
///
/// Nothing is written until the user picks rows and confirms: a transfer
/// between two wallets they own is not income, and only they can tell it apart
/// from a staking payout.
class BasisGapCubit extends Cubit<BasisGapState> {
  final BasisBackfillService service;

  BasisGapCubit({required this.service}) : super(const BasisGapState.initial());

  Future<void> load(CoinBasisGaps coin) async {
    emit(const BasisGapState.loading());
    try {
      final resolved = await service.priceGaps(coin);
      emit(BasisGapState.ready(
        coin: coin,
        gaps: resolved,
        // Everything priceable starts ticked: the user came here to fix these,
        // and unticking the odd wallet transfer is less work than ticking
        // thirty payouts.
        selected: {
          for (final g in resolved)
            if (g.resolvable) g.transaction.id,
        },
      ));
    } catch (e) {
      emit(BasisGapState.failed(e));
    }
  }

  void toggle(String transactionId) {
    final current = state.ready;
    if (current == null) return;

    final next = Set<String>.from(current.selected);
    if (!next.remove(transactionId)) next.add(transactionId);
    emit(current.withSelection(next));
  }

  void selectAll() {
    final current = state.ready;
    if (current == null) return;
    emit(current.withSelection({
      for (final g in current.gaps)
        if (g.resolvable) g.transaction.id,
    }));
  }

  void selectNone() {
    final current = state.ready;
    if (current == null) return;
    emit(current.withSelection(const {}));
  }

  /// Writes the ticked rows.
  ///
  /// Afterwards the screen shows what is genuinely left, not what was expected
  /// to be left: a row drops off only if its write actually succeeded.
  Future<BackfillResult?> applySelection() async {
    final current = state.ready;
    if (current == null || current.selected.isEmpty) return null;

    emit(current.applying());
    final chosen = current.chosen.map((g) => g.transaction.id).toSet();
    final result = await service.convert(current.chosen);

    final remaining = current.gaps.where((g) {
      // Rows the user left unticked, or could not price, stay put.
      if (!chosen.contains(g.transaction.id)) return true;
      // Ticked rows disappear once written, and stay if the write failed.
      return result.failedIds.contains(g.transaction.id);
    }).toList();

    emit(BasisGapState.ready(
      coin: current.coin,
      gaps: remaining,
      selected: const {},
      lastResult: result,
    ));
    return result;
  }
}

class BasisGapState {
  final bool isLoading;
  final Object? error;
  final BasisGapReady? ready;

  const BasisGapState._({this.isLoading = false, this.error, this.ready});

  const BasisGapState.initial() : this._(isLoading: true);
  const BasisGapState.loading() : this._(isLoading: true);
  const BasisGapState.failed(Object e) : this._(error: e);
  BasisGapState.ready({
    required CoinBasisGaps coin,
    required List<ResolvedGap> gaps,
    required Set<String> selected,
    BackfillResult? lastResult,
  }) : this._(
          ready: BasisGapReady(
            coin: coin,
            gaps: gaps,
            selected: selected,
            lastResult: lastResult,
          ),
        );
}

class BasisGapReady {
  final CoinBasisGaps coin;
  final List<ResolvedGap> gaps;
  final Set<String> selected;
  final bool isApplying;
  final BackfillResult? lastResult;

  const BasisGapReady({
    required this.coin,
    required this.gaps,
    required this.selected,
    this.isApplying = false,
    this.lastResult,
  });

  /// Rows that are both ticked and priceable.
  Iterable<ResolvedGap> get chosen =>
      gaps.where((g) => selected.contains(g.transaction.id) && g.resolvable);

  /// Income that confirming would record.
  double get selectedIncome => incomeFrom(chosen);

  /// Rows whose date is older than the free price history reaches.
  int get unreachable => gaps.where((g) => !g.resolvable).length;

  /// The same screen with the confirm button spinning.
  BasisGapState applying() => BasisGapState._(
        ready: BasisGapReady(
          coin: coin,
          gaps: gaps,
          selected: selected,
          isApplying: true,
          lastResult: lastResult,
        ),
      );

  BasisGapState withSelection(Set<String> next) => BasisGapState.ready(
        coin: coin,
        gaps: gaps,
        selected: next,
        lastResult: lastResult,
      );
}
