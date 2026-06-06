import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../bloc/portfolio/portfolio_state.dart';
import '../widgets/crypto_card.dart';
import '../widgets/portfolio_header.dart';

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) => const _PortfolioView();
}

class _PortfolioView extends StatelessWidget {
  const _PortfolioView();

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isWide = Responsive.isWide(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: BlocBuilder<PortfolioBloc, PortfolioState>(
          builder: (context, state) {
            return RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: () async {
                context.read<PortfolioBloc>().add(const RefreshPortfolioEvent());
                await Future.delayed(const Duration(milliseconds: 800));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Header: hide on desktop (sidebar shows total balance)
                  if (!isDesktop)
                    SliverToBoxAdapter(child: _buildHeader(context, state)),

                  // Desktop: just a section title
                  if (isDesktop)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(32, 32, 32, 16),
                        child: Text(
                          'Portfolio Overview',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  if (state is PortfolioLoaded) ...[
                    if (state.cryptos.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState(context))
                    else if (isWide)
                      // Tablet & Desktop: grid layout
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 32 : 24,
                          vertical: 8,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: isDesktop ? 400 : 340,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: 88,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => CryptoCard(
                              crypto: state.cryptos[i],
                              onTap: () =>
                                  context.go('/crypto/${state.cryptos[i].id}'),
                            ),
                            childCount: state.cryptos.length,
                          ),
                        ),
                      )
                    else
                      // Mobile: list layout
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CryptoCard(
                                crypto: state.cryptos[i],
                                onTap: () =>
                                    context.go('/crypto/${state.cryptos[i].id}'),
                              ),
                            ),
                            childCount: state.cryptos.length,
                          ),
                        ),
                      ),
                  ],

                  if (state is PortfolioLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    ),

                  if (state is PortfolioError)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppTheme.loss, size: 48),
                            const SizedBox(height: 12),
                            Text(state.message,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary)),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => context
                                  .read<PortfolioBloc>()
                                  .add(const LoadPortfolioEvent()),
                              child: const Text('Retry',
                                  style: TextStyle(color: AppTheme.primary)),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom padding (extra for FAB on mobile/tablet)
                  SliverToBoxAdapter(
                      child: SizedBox(height: isDesktop ? 32 : 100)),
                ],
              ),
            );
          },
        ),
      ),
      // FAB only on mobile and tablet (desktop has sidebar button)
      floatingActionButton:
          Responsive.isDesktop(context) ? null : _AddButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(BuildContext context, PortfolioState state) {
    double totalValue = 0;
    double totalPnl = 0;
    double totalPnlPercent = 0;
    bool isLoaded = false;
    if (state is PortfolioLoaded) {
      totalValue = state.totalValue;
      totalPnl = state.totalProfitLoss;
      totalPnlPercent = state.totalProfitLossPercent;
      isLoaded = true;
    }
    return PortfolioHeader(
      totalValue: totalValue,
      totalPnl: totalPnl,
      totalPnlPercent: totalPnlPercent,
      isLoaded: isLoaded,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: AppTheme.primary, size: 40),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your portfolio is empty',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first crypto to get started',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ElevatedButton.icon(
        onPressed: () => context.go('/search'),
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Add Crypto'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
