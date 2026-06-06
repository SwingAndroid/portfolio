import 'package:equatable/equatable.dart';

abstract class CoinSearchState extends Equatable {
  const CoinSearchState();
  @override
  List<Object?> get props => [];
}

class CoinSearchInitial extends CoinSearchState {
  const CoinSearchInitial();
}

class CoinSearchLoading extends CoinSearchState {
  const CoinSearchLoading();
}

class CoinSearchLoaded extends CoinSearchState {
  final List<Map<String, dynamic>> results;
  const CoinSearchLoaded(this.results);
  @override
  List<Object?> get props => [results];
}

class CoinSearchError extends CoinSearchState {
  final String message;
  const CoinSearchError(this.message);
  @override
  List<Object?> get props => [message];
}
