import 'package:equatable/equatable.dart';

import '../../../data/services/portfolio_history_service.dart';

abstract class PortfolioHistoryState extends Equatable {
  const PortfolioHistoryState();
  @override
  List<Object?> get props => [];
}

class PortfolioHistoryInitial extends PortfolioHistoryState {
  const PortfolioHistoryInitial();
}

class PortfolioHistoryLoading extends PortfolioHistoryState {
  final int days;
  const PortfolioHistoryLoading(this.days);
  @override
  List<Object?> get props => [days];
}

class PortfolioHistoryLoaded extends PortfolioHistoryState {
  final PortfolioHistory history;
  final int days;

  const PortfolioHistoryLoaded(this.history, this.days);

  /// Fewer than two points cannot draw a line.
  bool get isDrawable => history.points.length >= 2;

  @override
  List<Object?> get props =>
      [history.points.length, history.backfillError, days];
}
