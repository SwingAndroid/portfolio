import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'core/constants/app_constants.dart';
import 'data/datasources/local/crypto_local_datasource.dart';
import 'data/datasources/remote/crypto_remote_datasource.dart';
import 'data/models/crypto_model.dart';
import 'data/models/transaction_model.dart';
import 'data/repositories/crypto_repository_impl.dart';
import 'domain/repositories/crypto_repository.dart';
import 'domain/usecases/get_portfolio_usecase.dart';
import 'domain/usecases/add_crypto_usecase.dart';
import 'domain/usecases/add_transaction_usecase.dart';
import 'domain/usecases/delete_transaction_usecase.dart';
import 'domain/usecases/get_crypto_price_usecase.dart';
import 'domain/usecases/delete_crypto_usecase.dart';
import 'presentation/bloc/portfolio/portfolio_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  await Hive.initFlutter();

  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(CryptoModelAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(TransactionModelAdapter());
  }

  final cryptoBox = await Hive.openBox<CryptoModel>(AppConstants.cryptoBoxName);
  final transactionBox = await Hive.openBox<TransactionModel>(AppConstants.transactionBoxName);

  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.coingeckoBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'x-cg-demo-api-key': AppConstants.coingeckoApiKey,
      'Accept': 'application/json',
    },
  ));

  sl.registerLazySingleton<CryptoLocalDatasource>(
    () => CryptoLocalDatasourceImpl(cryptoBox: cryptoBox, transactionBox: transactionBox),
  );
  sl.registerLazySingleton<CryptoRemoteDatasource>(
    () => CryptoRemoteDatasourceImpl(dio: dio),
  );
  sl.registerLazySingleton<CryptoRepository>(
    () => CryptoRepositoryImpl(
      localDatasource: sl(),
      remoteDatasource: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetPortfolioUsecase(sl()));
  sl.registerLazySingleton(() => AddCryptoUsecase(sl()));
  sl.registerLazySingleton(() => AddTransactionUsecase(sl()));
  sl.registerLazySingleton(() => DeleteTransactionUsecase(sl()));
  sl.registerLazySingleton(() => GetCryptoPriceUsecase(sl()));
  sl.registerLazySingleton(() => DeleteCryptoUsecase(sl()));

  sl.registerFactory(() => PortfolioBloc(
    getPortfolio: sl(),
    addCrypto: sl(),
    deleteCrypto: sl(),
    getCryptoPrice: sl(),
  ));
}
