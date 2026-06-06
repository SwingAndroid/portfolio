import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../layout/app_shell.dart';
import '../pages/portfolio_page.dart';
import '../pages/crypto_detail_page.dart';
import '../pages/search_coin_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
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
          builder: (context, state) {
            final cryptoId = state.pathParameters['id']!;
            return CryptoDetailPage(cryptoId: cryptoId);
          },
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchCoinPage(),
        ),
      ],
    ),
  ],
);
