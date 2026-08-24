import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../injection_container.dart';
import '../bloc/history/portfolio_history_cubit.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../bloc/portfolio/portfolio_state.dart';
import '../widgets/allocation_chart.dart';
import '../widgets/performance_card.dart';
import '../widgets/sync_banner.dart';
import '../widgets/crypto_card.dart';
import '../widgets/portfolio_header.dart';
import '../widgets/portfolio_value_chart.dart';

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PortfolioHistoryCubit>(),
      child: const _PortfolioView(),
    );
  }
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
        child: BlocConsumer<PortfolioBloc, PortfolioState>(
          // The history cubit caches per range, so re-emitting a loaded
          // portfolio costs nothing once the window has been assembled.
          listenWhen: (_, next) => next is PortfolioLoaded,
          listener: (context, state) {
            if (state is PortfolioLoaded && state.cryptos.isNotEmpty) {
              context.read<PortfolioHistoryCubit>().load(state.cryptos);
            }
          },
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
                  // Mobile header
                  if (!isDesktop)
                    SliverToBoxAdapter(child: _buildHeader(context, state)),

                  // Desktop overview card
                  if (isDesktop)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                        child: state is PortfolioLoaded
                            ? _DesktopOverviewCard(state: state)
                            : const Text(
                                'Portfolio Overview',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                  // Sync health + local backup. Placed above the fold on
                  // purpose: a failing sync must not be discoverable only by
                  // scrolling.
                  const SliverToBoxAdapter(child: SyncBanner()),

                  // Performance: total vs annualised return
                  if (state is PortfolioLoaded && state.cryptos.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 32 : 16,
                          0,
                          isDesktop ? 32 : 16,
                          isDesktop ? 16 : 12,
                        ),
                        child: PerformanceCard(state: state),
                      ),
                    ),

                  // Value over time, against capital engaged
                  if (state is PortfolioLoaded && state.cryptos.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 32 : 16,
                          0,
                          isDesktop ? 32 : 16,
                          isDesktop ? 16 : 12,
                        ),
                        child: PortfolioValueChart(cryptos: state.cryptos),
                      ),
                    ),

                  // Allocation chart (shown when loaded and has coins)
                  if (state is PortfolioLoaded && state.cryptos.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 32 : 16,
                          0,
                          isDesktop ? 32 : 16,
                          isDesktop ? 16 : 12,
                        ),
                        child: PortfolioAllocationCard(
                          cryptos: state.cryptos,
                          totalValue: state.totalValue,
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
                              allocationPercent:
                                  state.allocationPercent(state.cryptos[i]),
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
                                allocationPercent:
                                    state.allocationPercent(state.cryptos[i]),
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
    if (state is! PortfolioLoaded) {
      return PortfolioHeader(
        totalValue: 0, totalCost: 0, totalPnl: 0,
        totalPnlPercent: 0, numAssets: 0, isLoaded: false,
      );
    }
    return PortfolioHeader(
      totalValue: state.totalValue,
      totalCost: state.totalCost,
      totalPnl: state.totalProfitLoss,
      totalPnlPercent: state.totalProfitLossPercent,
      numAssets: state.numAssets,
      bestSymbol: state.bestPerformer?.symbol,
      bestPercent: state.bestPerformer?.totalProfitLossPercent,
      worstSymbol: state.worstPerformer?.symbol,
      worstPercent: state.worstPerformer?.totalProfitLossPercent,
      isLoaded: true,
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

// ─── Desktop portfolio overview card ──────────────────────────────────────────

class _DesktopOverviewCard extends StatelessWidget {
  final PortfolioLoaded state;
  const _DesktopOverviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isProfit = state.totalProfitLoss >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;
    final best = state.bestPerformer;
    final worst = state.worstPerformer;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text('Portfolio Overview',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 20),
          // Main value row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Balance',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.formatCurrency(state.totalValue),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pnlColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: pnlColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isProfit
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        color: pnlColor,
                        size: 18,
                      ),
                      Text(
                        '${Formatters.formatCurrencyWithSign(state.totalProfitLoss)}  (${Formatters.formatPercent(state.totalProfitLossPercent)})  All time',
                        style: TextStyle(
                            color: pnlColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 20),
          // Stats row
          Row(
            children: [
              _OverviewStat(
                icon: Icons.paid_outlined,
                label: 'Total Invested',
                value: Formatters.formatCurrency(state.totalCost),
              ),
              _divider(),
              _OverviewStat(
                icon: Icons.grid_view_rounded,
                label: 'Assets',
                value: '${state.numAssets} coins',
              ),
              if (best != null) ...[
                _divider(),
                _OverviewStat(
                  icon: Icons.trending_up,
                  label: 'Best Performer',
                  value:
                      '${best.symbol}  ${best.totalProfitLossPercent >= 0 ? '+' : ''}${best.totalProfitLossPercent.toStringAsFixed(1)}%',
                  valueColor: AppTheme.profit,
                ),
              ],
              if (worst != null) ...[
                _divider(),
                _OverviewStat(
                  icon: Icons.trending_down,
                  label: 'Worst Performer',
                  value:
                      '${worst.symbol}  ${worst.totalProfitLossPercent >= 0 ? '+' : ''}${worst.totalProfitLossPercent.toStringAsFixed(1)}%',
                  valueColor: AppTheme.loss,
                ),
              ],
              _divider(),
              _OverviewStat(
                icon: Icons.hourglass_bottom_rounded,
                label: 'Unrealized P&L',
                value: Formatters.formatCurrencyWithSign(state.totalUnrealizedPnl),
                valueColor: state.totalUnrealizedPnl >= 0
                    ? AppTheme.profit
                    : AppTheme.loss,
              ),
              _divider(),
              _OverviewStat(
                icon: Icons.lock_outline_rounded,
                label: 'Realized P&L',
                value: Formatters.formatCurrencyWithSign(state.totalRealizedPnl),
                valueColor: state.totalRealizedPnl >= 0
                    ? AppTheme.profit
                    : AppTheme.loss,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 40,
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        color: AppTheme.divider,
      );
}

class _OverviewStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _OverviewStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
