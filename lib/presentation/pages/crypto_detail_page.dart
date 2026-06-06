import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../injection_container.dart';
import '../bloc/crypto_detail/crypto_detail_cubit.dart';
import '../bloc/crypto_detail/crypto_detail_state.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/add_transaction_sheet.dart';
import '../widgets/stat_row.dart';

class CryptoDetailPage extends StatelessWidget {
  final String cryptoId;
  const CryptoDetailPage({super.key, required this.cryptoId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CryptoDetailCubit(
        repository: sl(),
        addTransaction: sl(),
        deleteTransaction: sl(),
      )..loadCrypto(cryptoId),
      child: _CryptoDetailView(cryptoId: cryptoId),
    );
  }
}

class _CryptoDetailView extends StatelessWidget {
  final String cryptoId;
  const _CryptoDetailView({required this.cryptoId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoDetailCubit, CryptoDetailState>(
      builder: (context, state) {
        if (state is CryptoDetailLoading) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        if (state is CryptoDetailError) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
              backgroundColor: AppTheme.background,
              leading: _backButton(context),
            ),
            body: Center(
              child: Text(state.message,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ),
          );
        }
        if (state is CryptoDetailLoaded) {
          return Responsive.isDesktop(context)
              ? _buildDesktopLayout(context, state)
              : _buildMobileLayout(context, state);
        }
        return const Scaffold(backgroundColor: AppTheme.background);
      },
    );
  }

  // ─── Mobile / Tablet layout ───────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context, CryptoDetailLoaded state) {
    final crypto = state.crypto;
    final isProfit = crypto.totalProfitLoss >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;
    final isWide = Responsive.isWide(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, crypto),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 24 : 16, vertical: 8),
                children: [
                  _holdingsCard(context, crypto, isProfit, pnlColor),
                  const SizedBox(height: 24),
                  _transactionsSection(context, crypto),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
        child: ElevatedButton(
          onPressed: () =>
              _showAddTransaction(context, crypto.id, crypto.symbol),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Add Transaction',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ─── Desktop layout ───────────────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context, CryptoDetailLoaded state) {
    final crypto = state.crypto;
    final isProfit = crypto.totalProfitLoss >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, crypto, showBack: false),
            const Divider(color: AppTheme.divider, height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left panel: stats + add button
                  SizedBox(
                    width: 380,
                    child: ListView(
                      padding: const EdgeInsets.all(28),
                      children: [
                        _holdingsCard(context, crypto, isProfit, pnlColor),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _showAddTransaction(
                              context, crypto.id, crypto.symbol),
                          icon: const Icon(Icons.add,
                              color: Colors.black, size: 18),
                          label: const Text('Add Transaction'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppTheme.divider),
                  // Right panel: transaction history
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Transaction History',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${crypto.transactions.length} total',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: crypto.transactions.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.receipt_long_outlined,
                                          color: AppTheme.textTertiary,
                                          size: 40),
                                      SizedBox(height: 12),
                                      Text('No transactions yet',
                                          style: TextStyle(
                                              color: AppTheme.textSecondary)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28),
                                  itemCount: crypto.transactions.length,
                                  itemBuilder: (ctx, i) => TransactionTile(
                                    transaction: crypto.transactions[i],
                                    cryptoSymbol: crypto.symbol,
                                    onDelete: () async {
                                      final confirm =
                                          await _confirmDelete(context);
                                      if (confirm == true &&
                                          context.mounted) {
                                        context
                                            .read<CryptoDetailCubit>()
                                            .removeTransaction(
                                                crypto.transactions[i].id);
                                        context
                                            .read<PortfolioBloc>()
                                            .add(const RefreshPortfolioEvent());
                                      }
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, dynamic crypto,
      {bool showBack = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (showBack) ...[
            _backButton(context),
            const SizedBox(width: 8),
          ],
          if (crypto.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(crypto.imageUrl!, width: 32, height: 32,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(crypto.symbol,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Text(crypto.name,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const Spacer(),
          if (crypto.currentPrice > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Formatters.formatPrice(crypto.currentPrice),
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Row(
                  children: [
                    Icon(
                      crypto.priceChangePercent24h >= 0
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      color: crypto.priceChangePercent24h >= 0
                          ? AppTheme.profit
                          : AppTheme.loss,
                      size: 16,
                    ),
                    Text(
                      '${crypto.priceChangePercent24h.abs().toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: crypto.priceChangePercent24h >= 0
                            ? AppTheme.profit
                            : AppTheme.loss,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(width: 8),
          _DeleteButton(cryptoId: crypto.id),
        ],
      ),
    );
  }

  Widget _holdingsCard(BuildContext context, dynamic crypto, bool isProfit,
      Color pnlColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.diamond, color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('Holdings',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatRow(
                  label: 'HOLDINGS VALUE',
                  value: Formatters.formatCurrency(crypto.holdingsValue),
                ),
              ),
              Expanded(
                child: StatRow(
                  label: 'HOLDINGS',
                  value:
                      Formatters.formatCrypto(crypto.totalHoldings, crypto.symbol),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatRow(
                  label: 'TOTAL COST',
                  value: Formatters.formatCurrency(crypto.totalCost),
                ),
              ),
              Expanded(
                child: StatRow(
                  label: 'AVERAGE NET COST',
                  value: Formatters.formatCurrency(crypto.averageNetCost),
                  hasInfo: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StatRow(
            label: 'TOTAL PROFIT/LOSS',
            value:
                '${Formatters.formatCurrencyWithSign(crypto.totalProfitLoss)}  (${isProfit ? "▲" : "▼"} ${Formatters.formatPercent(crypto.totalProfitLossPercent).replaceAll('+', '')})',
            valueColor: pnlColor,
          ),
        ],
      ),
    );
  }

  Widget _transactionsSection(BuildContext context, dynamic crypto) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Transactions History',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            Text('${crypto.transactions.length} total',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        if (crypto.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      color: AppTheme.textTertiary, size: 40),
                  SizedBox(height: 12),
                  Text('No transactions yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          )
        else
          ...crypto.transactions.map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: TransactionTile(
                  transaction: tx,
                  cryptoSymbol: crypto.symbol,
                  onDelete: () async {
                    final confirm = await _confirmDelete(context);
                    if (confirm == true && context.mounted) {
                      context
                          .read<CryptoDetailCubit>()
                          .removeTransaction(tx.id);
                      context
                          .read<PortfolioBloc>()
                          .add(const RefreshPortfolioEvent());
                    }
                  },
                ),
              )),
      ],
    );
  }

  Widget _backButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pop(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: const Icon(Icons.arrow_back_ios,
            color: AppTheme.textPrimary, size: 16),
      ),
    );
  }

  void _showAddTransaction(
      BuildContext context, String cryptoId, String symbol) {
    if (Responsive.isDesktop(context)) {
      // Desktop: show as dialog instead of bottom sheet
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: AppTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 480,
            child: BlocProvider.value(
              value: context.read<CryptoDetailCubit>(),
              child: AddTransactionSheet(
                  cryptoId: cryptoId, cryptoSymbol: symbol),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => BlocProvider.value(
          value: context.read<CryptoDetailCubit>(),
          child: AddTransactionSheet(cryptoId: cryptoId, cryptoSymbol: symbol),
        ),
      );
    }
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Transaction',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
            'Are you sure you want to delete this transaction?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.loss)),
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final String cryptoId;
  const _DeleteButton({required this.cryptoId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('Remove Crypto',
                style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text(
                'This will delete the crypto and all its transactions.',
                style: TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: AppTheme.loss)),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          context.read<PortfolioBloc>().add(DeleteCryptoEvent(cryptoId));
          context.go('/');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child:
            const Icon(Icons.delete_outline, color: AppTheme.loss, size: 18),
      ),
    );
  }
}
