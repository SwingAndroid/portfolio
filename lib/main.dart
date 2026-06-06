import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'injection_container.dart';
import 'presentation/bloc/auth/auth_cubit.dart';
import 'presentation/bloc/portfolio/portfolio_bloc.dart';
import 'presentation/bloc/portfolio/portfolio_event.dart';
import 'presentation/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initDependencies();

  runApp(const CryptoPortfolioApp());
}

class CryptoPortfolioApp extends StatefulWidget {
  const CryptoPortfolioApp({super.key});

  @override
  State<CryptoPortfolioApp> createState() => _CryptoPortfolioAppState();
}

class _CryptoPortfolioAppState extends State<CryptoPortfolioApp> {
  late final AuthCubit _authCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authCubit = sl<AuthCubit>();
    _router = buildRouter(_authCubit);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authCubit),
        BlocProvider(
          create: (_) => sl<PortfolioBloc>()..add(const LoadPortfolioEvent()),
        ),
      ],
      child: MaterialApp.router(
        title: 'Crypto Portfolio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: _router,
      ),
    );
  }
}
