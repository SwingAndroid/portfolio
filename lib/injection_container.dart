import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/sync/sync_status.dart';
import 'data/datasources/cloud/supabase_datasource.dart';
import 'data/datasources/cloud/sync_service.dart';
import 'data/datasources/local/crypto_local_datasource.dart';
import 'data/datasources/local/value_history_store.dart';
import 'data/services/portfolio_history_service.dart';
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
import 'presentation/bloc/auth/auth_cubit.dart';
import 'presentation/bloc/history/portfolio_history_cubit.dart';
import 'presentation/bloc/portfolio/portfolio_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // ── Hive ─────────────────────────────────────────────────────────────────
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CryptoModelAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());

  final cryptoBox = await Hive.openBox<CryptoModel>(AppConstants.cryptoBoxName);
  final transactionBox =
      await Hive.openBox<TransactionModel>(AppConstants.transactionBoxName);
  // Separate box, plain String values: no new typeId and no adapter, so the
  // existing cryptos/transactions boxes are never migrated or rewritten.
  final pendingDeleteBox =
      await Hive.openBox<String>(AppConstants.pendingDeleteBoxName);
  // Our own daily record of portfolio value. CoinGecko refuses history beyond
  // 365 days, so this is the only way to ever have a multi-year curve.
  final valueHistoryBox =
      await Hive.openBox<String>(AppConstants.valueHistoryBoxName);

  // ── CoinGecko HTTP client ─────────────────────────────────────────────────
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.coingeckoBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    // Chart and coin-detail responses are large; 10s was tight enough to
    // fail on slow mobile connections, which silently blanked those cards.
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'x-cg-demo-api-key': AppConstants.coingeckoApiKey,
      'Accept': 'application/json',
    },
  ));

  // ── Value history ─────────────────────────────────────────────────────────
  sl.registerLazySingleton<ValueHistoryStore>(
    () => ValueHistoryStoreImpl(valueHistoryBox),
  );
  sl.registerLazySingleton<PortfolioSnapshotRecorder>(
    () => PortfolioSnapshotRecorder(sl()),
  );
  sl.registerLazySingleton<PortfolioHistoryService>(
    () => PortfolioHistoryService(repository: sl(), store: sl()),
  );

  // ── Sync health (drives the banner; replaces silent catch blocks) ─────────
  sl.registerLazySingleton<SyncStatus>(() => SyncStatus());

  // ── Supabase ──────────────────────────────────────────────────────────────
  final supabaseClient = Supabase.instance.client;

  sl.registerLazySingleton<SupabaseDataSource>(
    () => SupabaseDataSourceImpl(supabaseClient),
  );

  // ── Datasources ───────────────────────────────────────────────────────────
  sl.registerLazySingleton<CryptoLocalDatasource>(
    () => CryptoLocalDatasourceImpl(
      cryptoBox: cryptoBox,
      transactionBox: transactionBox,
      pendingDeleteBox: pendingDeleteBox,
    ),
  );
  sl.registerLazySingleton<CryptoRemoteDatasource>(
    () => CryptoRemoteDatasourceImpl(dio: dio),
  );

  // ── Sync service ──────────────────────────────────────────────────────────
  sl.registerLazySingleton<SyncService>(
    () => SyncService(
      cloudDataSource: sl(),
      localDataSource: sl(),
    ),
  );

  // ── Repository ────────────────────────────────────────────────────────────
  sl.registerLazySingleton<CryptoRepository>(
    () => CryptoRepositoryImpl(
      localDatasource: sl(),
      remoteDatasource: sl(),
      cloudDatasource: sl(),
      syncStatus: sl(),
    ),
  );

  // ── Use cases ─────────────────────────────────────────────────────────────
  sl.registerLazySingleton(() => GetPortfolioUsecase(sl()));
  sl.registerLazySingleton(() => AddCryptoUsecase(sl()));
  sl.registerLazySingleton(() => AddTransactionUsecase(sl()));
  sl.registerLazySingleton(() => DeleteTransactionUsecase(sl()));
  sl.registerLazySingleton(() => GetCryptoPriceUsecase(sl()));
  sl.registerLazySingleton(() => DeleteCryptoUsecase(sl()));

  // ── BLoCs / Cubits ────────────────────────────────────────────────────────
  sl.registerFactory(() => AuthCubit(
        client: supabaseClient,
        syncService: sl(),
        local: sl(),
        syncStatus: sl(),
      ));

  sl.registerFactory(() => PortfolioHistoryCubit(service: sl()));

  sl.registerFactory(() => PortfolioBloc(
        snapshotRecorder: sl(),
        getPortfolio: sl(),
        addCrypto: sl(),
        deleteCrypto: sl(),
        getCryptoPrice: sl(),
        syncService: sl(),
      ));
}
