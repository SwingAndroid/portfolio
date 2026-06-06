import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/crypto_entity.dart';
import '../bloc/auth/auth_cubit.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../bloc/portfolio/portfolio_state.dart';

class DesktopSidebar extends StatelessWidget {
  final String? selectedCryptoId;

  const DesktopSidebar({super.key, this.selectedCryptoId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const Divider(color: AppTheme.divider, height: 1),
          _buildTotalValue(context),
          const Divider(color: AppTheme.divider, height: 1),
          Expanded(child: _buildCryptoList(context)),
          const Divider(color: AppTheme.divider, height: 1),
          _buildAddButton(context),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CryptoPortfolio',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Track your assets',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary, size: 18),
            onPressed: () =>
                context.read<PortfolioBloc>().add(const RefreshPortfolioEvent()),
            tooltip: 'Refresh prices',
          ),
        ],
      ),
    );
  }

  Widget _buildTotalValue(BuildContext context) {
    return BlocBuilder<PortfolioBloc, PortfolioState>(
      builder: (context, state) {
        double totalValue = 0;
        double pnl = 0;
        double pnlPct = 0;
        if (state is PortfolioLoaded) {
          totalValue = state.totalValue;
          pnl = state.totalProfitLoss;
          pnlPct = state.totalProfitLossPercent;
        }
        final isProfit = pnl >= 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total Balance',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                Formatters.formatCurrency(totalValue),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isProfit ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: isProfit ? AppTheme.profit : AppTheme.loss,
                    size: 16,
                  ),
                  Text(
                    '${Formatters.formatCurrencyWithSign(pnl)}  (${Formatters.formatPercent(pnlPct)})',
                    style: TextStyle(
                      color: isProfit ? AppTheme.profit : AppTheme.loss,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCryptoList(BuildContext context) {
    return BlocBuilder<PortfolioBloc, PortfolioState>(
      builder: (context, state) {
        if (state is PortfolioLoading) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (state is! PortfolioLoaded || state.cryptos.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No assets yet.\nTap "Add Crypto" to start.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: state.cryptos.length,
          itemBuilder: (ctx, i) => _SidebarCryptoTile(
            crypto: state.cryptos[i],
            isSelected: state.cryptos[i].id == selectedCryptoId,
            onTap: () => context.go('/crypto/${state.cryptos[i].id}'),
          ),
        );
      },
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ElevatedButton.icon(
        onPressed: () => context.go('/search'),
        icon: const Icon(Icons.add, color: Colors.black, size: 18),
        label: const Text('Add Crypto'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextButton.icon(
        onPressed: () => context.read<AuthCubit>().signOut(),
        icon: const Icon(Icons.logout, color: AppTheme.textTertiary, size: 16),
        label: const Text('Sign Out',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        style: TextButton.styleFrom(
          minimumSize: const Size(double.infinity, 36),
        ),
      ),
    );
  }
}

class _SidebarCryptoTile extends StatelessWidget {
  final CryptoEntity crypto;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarCryptoTile({
    required this.crypto,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isProfit = crypto.totalProfitLossPercent >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppTheme.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            _CoinAvatar(imageUrl: crypto.imageUrl, symbol: crypto.symbol),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crypto.symbol,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    Formatters.formatCrypto(
                        crypto.totalHoldings, crypto.symbol),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.formatCurrency(crypto.holdingsValue),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isProfit
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      color: pnlColor,
                      size: 14,
                    ),
                    Text(
                      '${crypto.totalProfitLossPercent.abs().toStringAsFixed(2)}%',
                      style: TextStyle(color: pnlColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinAvatar extends StatelessWidget {
  final String? imageUrl;
  final String symbol;

  const _CoinAvatar({this.imageUrl, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl!,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => const Icon(Icons.currency_bitcoin,
      color: AppTheme.primary, size: 16);
}
