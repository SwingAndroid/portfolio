import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth/auth_cubit.dart';
import '../bloc/auth/auth_state.dart';
import '../layout/app_shell.dart';
import '../pages/auth/login_page.dart';
import '../pages/auth/register_page.dart';
import '../pages/portfolio_page.dart';
import '../pages/crypto_detail_page.dart';
import '../pages/search_coin_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AuthCubit authCubit) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: GoRouterAuthNotifier(authCubit),
    redirect: (context, state) {
      final authState = authCubit.state;
      final isAuth = authState is AuthAuthenticated;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/';
      return null;
    },
    routes: [
      // ── Auth routes (no shell / no sidebar) ───────────────────────────
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterPage(),
      ),

      // ── App routes (wrapped in responsive shell) ───────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const PortfolioPage(),
          ),
          GoRoute(
            path: '/crypto/:id',
            builder: (context, state) => CryptoDetailPage(
              key: ValueKey(state.pathParameters['id']),
              cryptoId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchCoinPage(),
          ),
        ],
      ),
    ],
  );
}

/// Bridges AuthCubit state changes into GoRouter's refresh mechanism.
class GoRouterAuthNotifier extends ChangeNotifier {
  GoRouterAuthNotifier(AuthCubit cubit) {
    cubit.stream.listen((_) => notifyListeners());
  }
}
