import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/crypto_repository.dart';
import 'coin_search_state.dart';

class CoinSearchCubit extends Cubit<CoinSearchState> {
  final CryptoRepository repository;

  CoinSearchCubit({required this.repository}) : super(const CoinSearchInitial());

  Future<void> searchCoins(String query) async {
    if (query.isEmpty) {
      emit(const CoinSearchInitial());
      return;
    }
    emit(const CoinSearchLoading());
    try {
      final results = await repository.searchCoins(query);
      emit(CoinSearchLoaded(results));
    } catch (e) {
      emit(CoinSearchError(e.toString()));
    }
  }

  void clear() => emit(const CoinSearchInitial());
}
