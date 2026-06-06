import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/get_portfolio_usecase.dart';
import '../../../domain/usecases/add_crypto_usecase.dart';
import '../../../domain/usecases/delete_crypto_usecase.dart';
import '../../../domain/usecases/get_crypto_price_usecase.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  final GetPortfolioUsecase getPortfolio;
  final AddCryptoUsecase addCrypto;
  final DeleteCryptoUsecase deleteCrypto;
  final GetCryptoPriceUsecase getCryptoPrice;

  PortfolioBloc({
    required this.getPortfolio,
    required this.addCrypto,
    required this.deleteCrypto,
    required this.getCryptoPrice,
  }) : super(const PortfolioInitial()) {
    on<LoadPortfolioEvent>(_onLoad);
    on<RefreshPortfolioEvent>(_onRefresh);
    on<AddCryptoEvent>(_onAddCrypto);
    on<DeleteCryptoEvent>(_onDeleteCrypto);
  }

  Future<void> _onLoad(LoadPortfolioEvent event, Emitter<PortfolioState> emit) async {
    emit(const PortfolioLoading());
    try {
      final cryptos = await getPortfolio();
      emit(PortfolioLoaded(cryptos: cryptos));
    } catch (e) {
      emit(PortfolioError(e.toString()));
    }
  }

  Future<void> _onRefresh(RefreshPortfolioEvent event, Emitter<PortfolioState> emit) async {
    if (state is PortfolioLoaded) {
      emit((state as PortfolioLoaded).copyWith(isRefreshing: true));
    }
    try {
      final cryptos = await getPortfolio();
      emit(PortfolioLoaded(cryptos: cryptos));
    } catch (e) {
      emit(PortfolioError(e.toString()));
    }
  }

  Future<void> _onAddCrypto(AddCryptoEvent event, Emitter<PortfolioState> emit) async {
    try {
      await addCrypto(event.crypto);
      final cryptos = await getPortfolio();
      emit(PortfolioLoaded(cryptos: cryptos));
    } catch (e) {
      emit(PortfolioError(e.toString()));
    }
  }

  Future<void> _onDeleteCrypto(DeleteCryptoEvent event, Emitter<PortfolioState> emit) async {
    try {
      await deleteCrypto(event.cryptoId);
      final cryptos = await getPortfolio();
      emit(PortfolioLoaded(cryptos: cryptos));
    } catch (e) {
      emit(PortfolioError(e.toString()));
    }
  }
}
