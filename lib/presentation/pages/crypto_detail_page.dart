import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../injection_container.dart';
import '../bloc/crypto_detail/crypto_detail_cubit.dart';
import '../bloc/crypto_detail/crypto_detail_state.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_event.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/entities/entry_signal.dart';
import '../../domain/entities/price_point.dart';
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
                  _holdingsCard(context, crypto, isProfit, pnlColor, state),
                  const SizedBox(height: 24),
                  _TransactionSection(
                    transactions: crypto.transactions,
                    cryptoSymbol: crypto.symbol,
                    isScrollable: false,
                    padding: EdgeInsets.zero,
                    onDeleteTx: (tx) async {
                      final confirm = await _confirmDelete(context);
                      if (confirm == true && context.mounted) {
                        context.read<CryptoDetailCubit>().removeTransaction(tx.id);
                        context.read<PortfolioBloc>().add(const RefreshPortfolioEvent());
                      }
                    },
                  ),
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
                        _holdingsCard(context, crypto, isProfit, pnlColor,
                            state),
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
                  // Right panel: transaction history with filters
                  Expanded(
                    child: _TransactionSection(
                      transactions: crypto.transactions,
                      cryptoSymbol: crypto.symbol,
                      isScrollable: true,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      onDeleteTx: (tx) async {
                        final confirm = await _confirmDelete(context);
                        if (confirm == true && context.mounted) {
                          context.read<CryptoDetailCubit>().removeTransaction(tx.id);
                          context.read<PortfolioBloc>().add(const RefreshPortfolioEvent());
                        }
                      },
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
      Color pnlColor, CryptoDetailLoaded state) {
    final marketData = state.marketData;
    final signal = EntrySignal.compute(
      currentPrice: crypto.currentPrice as double,
      avgBuyPrice: crypto.avgBuyPrice as double,
      athChangePercent: marketData?.athChangePercent,
      change30d: marketData?.change30d,
    );
    return Column(
      children: [
        // ── Entry Signal card (DCA "should I add now?") ─────────────────────
        if (signal.hasData) ...[
          _EntrySignalCard(signal: signal),
          const SizedBox(height: 12),
        ],
        // ── Price chart with avg-cost line + buy markers ────────────────────
        _PriceChartCard(
          crypto: crypto,
          history: state.priceHistory,
          days: state.chartDays,
          loading: state.chartLoading,
          onRange: (d) =>
              context.read<CryptoDetailCubit>().loadChart(crypto.coinId, d),
        ),
        // ── Holdings card ───────────────────────────────────────────────────
        Container(
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
                      value: Formatters.formatCrypto(
                          crypto.totalHoldings, crypto.symbol),
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
        ),
        // ── Realized / Unrealized P&L card ────────────────────────────────
        if (crypto.totalSoldQuantity > 0 || crypto.currentPrice > 0) ...[
          const SizedBox(height: 12),
          _PnlBreakdownCard(crypto: crypto),
        ],
        // ── Price analysis card ─────────────────────────────────────────────
        if (crypto.currentPrice > 0 && crypto.minBuyPrice > 0) ...[
          const SizedBox(height: 12),
          _PriceAnalysisCard(crypto: crypto),
        ],
      ],
    );
  }

  Widget _backButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.canPop() ? context.pop() : context.go('/'),
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

// ─── Transaction section with filters + sort ─────────────────────────────────

enum _TxSort { newest, oldest, highestValue, lowestValue }

class _TransactionSection extends StatefulWidget {
  final List<TransactionEntity> transactions;
  final String cryptoSymbol;
  final bool isScrollable;
  final EdgeInsets padding;
  final Future<void> Function(TransactionEntity tx) onDeleteTx;

  const _TransactionSection({
    required this.transactions,
    required this.cryptoSymbol,
    required this.isScrollable,
    required this.padding,
    required this.onDeleteTx,
  });

  @override
  State<_TransactionSection> createState() => _TransactionSectionState();
}

class _TransactionSectionState extends State<_TransactionSection> {
  TransactionType? _filter; // null = All
  _TxSort _sort = _TxSort.newest;

  List<TransactionEntity> get _filtered {
    var list = [...widget.transactions];
    if (_filter != null) {
      list = list.where((t) => t.type == _filter).toList();
    }
    switch (_sort) {
      case _TxSort.newest:
        list.sort((a, b) => b.date.compareTo(a.date));
      case _TxSort.oldest:
        list.sort((a, b) => a.date.compareTo(b.date));
      case _TxSort.highestValue:
        list.sort((a, b) => b.totalValue.compareTo(a.totalValue));
      case _TxSort.lowestValue:
        list.sort((a, b) => a.totalValue.compareTo(b.totalValue));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = widget.transactions.length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: widget.isScrollable
              ? const EdgeInsets.fromLTRB(0, 28, 0, 0)
              : EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaction History',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                _filter == null
                    ? '$total transactions'
                    : '${filtered.length} of $total',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // ── Filter chips ─────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter == null,
                color: AppTheme.primary,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Buy',
                selected: _filter == TransactionType.buy,
                color: AppTheme.profit,
                onTap: () => setState(() => _filter = _filter == TransactionType.buy ? null : TransactionType.buy),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Sell',
                selected: _filter == TransactionType.sell,
                color: AppTheme.loss,
                onTap: () => setState(() => _filter = _filter == TransactionType.sell ? null : TransactionType.sell),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Transfer In',
                selected: _filter == TransactionType.transferIn,
                color: const Color(0xFF3D8BFF),
                onTap: () => setState(() => _filter = _filter == TransactionType.transferIn ? null : TransactionType.transferIn),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Transfer Out',
                selected: _filter == TransactionType.transferOut,
                color: const Color(0xFFFF9800),
                onTap: () => setState(() => _filter = _filter == TransactionType.transferOut ? null : TransactionType.transferOut),
              ),
              const SizedBox(width: 12),
              // Sort dropdown
              _SortButton(
                current: _sort,
                onChanged: (s) => setState(() => _sort = s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(color: AppTheme.divider, height: 1),
        const SizedBox(height: 4),
        // ── Transaction list ─────────────────────────────────────────────
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.filter_list_off,
                      color: AppTheme.textTertiary, size: 36),
                  const SizedBox(height: 10),
                  Text(
                    _filter == null
                        ? 'No transactions yet'
                        : 'No ${_filter!.name} transactions',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else if (widget.isScrollable)
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => TransactionTile(
                transaction: filtered[i],
                cryptoSymbol: widget.cryptoSymbol,
                onDelete: () => widget.onDeleteTx(filtered[i]),
              ),
            ),
          )
        else
          ...filtered.map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: TransactionTile(
                  transaction: tx,
                  cryptoSymbol: widget.cryptoSymbol,
                  onDelete: () => widget.onDeleteTx(tx),
                ),
              )),
      ],
    );

    if (widget.isScrollable) {
      return Padding(
        padding: widget.padding,
        child: content,
      );
    }
    return content;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppTheme.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final _TxSort current;
  final ValueChanged<_TxSort> onChanged;

  const _SortButton({required this.current, required this.onChanged});

  String get _label => switch (current) {
        _TxSort.newest => 'Newest',
        _TxSort.oldest => 'Oldest',
        _TxSort.highestValue => 'Highest \$',
        _TxSort.lowestValue => 'Lowest \$',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showMenu<_TxSort>(
          context: context,
          color: AppTheme.surface,
          position: RelativeRect.fromLTRB(
            MediaQuery.of(context).size.width,
            kToolbarHeight,
            0,
            0,
          ),
          items: const [
            PopupMenuItem(value: _TxSort.newest, child: Text('Newest first', style: TextStyle(color: AppTheme.textPrimary))),
            PopupMenuItem(value: _TxSort.oldest, child: Text('Oldest first', style: TextStyle(color: AppTheme.textPrimary))),
            PopupMenuItem(value: _TxSort.highestValue, child: Text('Highest value', style: TextStyle(color: AppTheme.textPrimary))),
            PopupMenuItem(value: _TxSort.lowestValue, child: Text('Lowest value', style: TextStyle(color: AppTheme.textPrimary))),
          ],
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded,
                color: AppTheme.textSecondary, size: 14),
            const SizedBox(width: 5),
            Text(
              _label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_drop_down,
                color: AppTheme.textTertiary, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─── Realized / Unrealized P&L card ──────────────────────────────────────────

class _PnlBreakdownCard extends StatelessWidget {
  final dynamic crypto;
  const _PnlBreakdownCard({required this.crypto});

  @override
  Widget build(BuildContext context) {
    final unrealized = crypto.unrealizedPnl as double;
    final unrealizedPct = crypto.unrealizedPnlPercent as double;
    final realized = crypto.realizedPnl as double;
    final realizedPct = crypto.realizedPnlPercent as double;
    final hasRealized = (crypto.totalSoldQuantity as double) > 0;
    final hasUnrealized = (crypto.currentPrice as double) > 0;

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
              Icon(Icons.bar_chart_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('P&L Breakdown',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Unrealized
              if (hasUnrealized)
                Expanded(
                  child: _PnlPanel(
                    label: 'UNREALIZED',
                    sublabel: 'Paper gain on holdings',
                    amount: unrealized,
                    percent: unrealizedPct,
                    icon: Icons.hourglass_bottom_rounded,
                  ),
                ),
              if (hasUnrealized && hasRealized)
                Container(
                    width: 1,
                    height: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: AppTheme.divider),
              // Realized
              if (hasRealized)
                Expanded(
                  child: _PnlPanel(
                    label: 'REALIZED',
                    sublabel: 'Locked in from sells',
                    amount: realized,
                    percent: realizedPct,
                    icon: Icons.lock_outline_rounded,
                  ),
                ),
            ],
          ),
          // Total check row
          if (hasUnrealized && hasRealized) ...[
            const SizedBox(height: 14),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Combined P&L',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                Text(
                  Formatters.formatCurrencyWithSign(unrealized + realized),
                  style: TextStyle(
                    color: (unrealized + realized) >= 0
                        ? AppTheme.profit
                        : AppTheme.loss,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PnlPanel extends StatelessWidget {
  final String label;
  final String sublabel;
  final double amount;
  final double percent;
  final IconData icon;

  const _PnlPanel({
    required this.label,
    required this.sublabel,
    required this.amount,
    required this.percent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = amount >= 0;
    final color = isPositive ? AppTheme.profit : AppTheme.loss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: AppTheme.textTertiary),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ],
        ),
        const SizedBox(height: 2),
        Text(sublabel,
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 10)),
        const SizedBox(height: 8),
        Text(
          Formatters.formatCurrencyWithSign(amount),
          style: TextStyle(
              color: color, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${isPositive ? '▲' : '▼'} ${percent.abs().toStringAsFixed(2)}%',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ─── Price analysis card ───────────────────────────────────────────────────────

class _PriceAnalysisCard extends StatelessWidget {
  final dynamic crypto;
  const _PriceAnalysisCard({required this.crypto});

  @override
  Widget build(BuildContext context) {
    final currentPrice = crypto.currentPrice as double;
    final minBuy = crypto.minBuyPrice as double;
    final gap = ((currentPrice - minBuy) / minBuy) * 100;
    final isCheaper = currentPrice <= minBuy; // today is at or below best entry
    final gapColor = isCheaper ? AppTheme.profit : AppTheme.loss;
    final gapIcon = isCheaper ? '▼' : '▲';
    final gapLabel = isCheaper
        ? '${gap.abs().toStringAsFixed(2)}% below your best entry'
        : '${gap.abs().toStringAsFixed(2)}% above your best entry';

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
              Icon(Icons.show_chart, color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('Price Analysis',
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
                  label: 'CURRENT PRICE',
                  value: Formatters.formatPrice(currentPrice),
                ),
              ),
              Expanded(
                child: StatRow(
                  label: 'BEST BUY PRICE',
                  value: Formatters.formatPrice(minBuy),
                  valueColor: AppTheme.profit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: gapColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gapColor.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  isCheaper
                      ? Icons.thumb_up_outlined
                      : Icons.arrow_upward_rounded,
                  color: gapColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$gapIcon $gapLabel',
                    style: TextStyle(
                      color: gapColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Price chart card (price history + avg cost + buy markers) ───────────────

class _PriceChartCard extends StatelessWidget {
  final dynamic crypto;
  final List<PricePoint>? history;
  final int days;
  final bool loading;
  final ValueChanged<int> onRange;

  const _PriceChartCard({
    required this.crypto,
    required this.history,
    required this.days,
    required this.loading,
    required this.onRange,
  });

  static const _ranges = [(30, '30D'), (90, '90D'), (365, '1Y')];

  String _yLabel(double v) {
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    if (v >= 1) return '\$${v.toStringAsFixed(0)}';
    if (v >= 0.01) return '\$${v.toStringAsFixed(2)}';
    return '\$${v.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = history != null && history!.isNotEmpty;
    // Nothing to show and nothing loading → take no space.
    if (!hasData && !loading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header + range selector ──────────────────────────────────
            Row(
              children: [
                const Icon(Icons.candlestick_chart_rounded,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 6),
                const Text('Price History',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                ..._ranges.map((r) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _ChartRangeChip(
                        label: r.$2,
                        selected: days == r.$1,
                        onTap: () => onRange(r.$1),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 180,
              child: (!hasData)
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary),
                      ),
                    )
                  : _buildChart(),
            ),
            const SizedBox(height: 14),
            // ── Legend ───────────────────────────────────────────────────
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                const _LegendDot(color: AppTheme.primary, label: 'Price'),
                if ((crypto.avgBuyPrice as double) > 0)
                  const _LegendDot(
                      color: AppTheme.accent, label: 'Your avg cost', dashed: true),
                const _LegendDot(color: AppTheme.profit, label: 'Your buys'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final hist = history!;
    final spots = [
      for (final p in hist)
        FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.price)
    ];
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final avgBuy = crypto.avgBuyPrice as double;

    // Buy markers within the visible window.
    final List<TransactionEntity> txs = crypto.transactions;
    final buySpots = <FlSpot>[];
    for (final t in txs) {
      if (t.type == TransactionType.buy && t.pricePerCoin > 0) {
        final x = t.date.millisecondsSinceEpoch.toDouble();
        if (x >= minX && x <= maxX) buySpots.add(FlSpot(x, t.pricePerCoin));
      }
    }
    buySpots.sort((a, b) => a.x.compareTo(b.x));

    double minY = hist.first.price, maxY = hist.first.price;
    for (final p in hist) {
      if (p.price < minY) minY = p.price;
      if (p.price > maxY) maxY = p.price;
    }
    if (avgBuy > 0) {
      minY = math.min(minY, avgBuy);
      maxY = math.max(maxY, avgBuy);
    }
    for (final b in buySpots) {
      minY = math.min(minY, b.y);
      maxY = math.max(maxY, b.y);
    }
    final span = maxY - minY;
    final pad = span == 0 ? (maxY == 0 ? 1 : maxY * 0.1) : span * 0.10;
    minY = math.max(0, minY - pad);
    maxY = maxY + pad;

    final xInterval = (maxX - minX) / 3;
    final yInterval = (maxY - minY) / 3;
    final dateFmt = days >= 365 ? DateFormat('MMM yy') : DateFormat('MMM d');

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval > 0 ? yInterval : null,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: yInterval > 0 ? yInterval : null,
              getTitlesWidget: (v, meta) {
                if (v <= minY || v >= maxY) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(_yLabel(v),
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 9)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: xInterval > 0 ? xInterval : null,
              getTitlesWidget: (v, meta) {
                final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(dateFmt.format(d),
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surfaceVariant,
            getTooltipItems: (touched) => touched.map((s) {
              if (s.barIndex == 1) return null; // suppress buy-marker bar
              final d = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
              return LineTooltipItem(
                '${Formatters.formatPrice(s.y)}\n${Formatters.formatShortDate(d)}',
                const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (avgBuy > 0)
              HorizontalLine(
                y: avgBuy,
                color: AppTheme.accent,
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700),
                  labelResolver: (_) => 'Avg ${Formatters.formatPrice(avgBuy)}',
                ),
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.1,
            color: AppTheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primary.withOpacity(0.25),
                  AppTheme.primary.withOpacity(0.0),
                ],
              ),
            ),
          ),
          if (buySpots.isNotEmpty)
            LineChartBarData(
              spots: buySpots,
              barWidth: 0,
              color: Colors.transparent,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 4,
                  color: AppTheme.profit,
                  strokeColor: Colors.white,
                  strokeWidth: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartRangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChartRangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.15)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.cardBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot(
      {required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dashed
            ? Container(width: 14, height: 2, color: color)
            : Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ─── Entry Signal card (DCA decision helper) ─────────────────────────────────

class _EntrySignalCard extends StatelessWidget {
  final EntrySignal signal;
  const _EntrySignalCard({required this.signal});

  static const Color _gold = Color(0xFFFFD700);
  static const Color _orange = Color(0xFFFF9800);

  Color get _color => switch (signal.level) {
        EntryLevel.strong => AppTheme.profit,
        EntryLevel.good => AppTheme.primary,
        EntryLevel.fair => _gold,
        EntryLevel.wait => _orange,
        EntryLevel.expensive => AppTheme.loss,
      };

  String get _label => switch (signal.level) {
        EntryLevel.strong => 'STRONG ENTRY',
        EntryLevel.good => 'GOOD ENTRY',
        EntryLevel.fair => 'FAIR',
        EntryLevel.wait => 'WAIT',
        EntryLevel.expensive => 'EXPENSIVE',
      };

  String get _summary => switch (signal.level) {
        EntryLevel.strong => 'Conditions look favourable to add.',
        EntryLevel.good => 'A reasonable spot to DCA in.',
        EntryLevel.fair => 'Neutral — neither cheap nor rich.',
        EntryLevel.wait => 'A little rich vs your usual entries.',
        EntryLevel.expensive => 'Looks expensive right now.',
      };

  IconData get _icon => switch (signal.level) {
        EntryLevel.strong => Icons.trending_up_rounded,
        EntryLevel.good => Icons.thumb_up_outlined,
        EntryLevel.fair => Icons.remove_rounded,
        EntryLevel.wait => Icons.schedule_rounded,
        EntryLevel.expensive => Icons.trending_down_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          const Row(
            children: [
              Icon(Icons.auto_graph_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('Entry Signal',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: 6),
              Text('· DCA',
                  style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          // ── Score + verdict ─────────────────────────────────────────────
          Row(
            children: [
              // Score dial
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: signal.score / 100,
                        strokeWidth: 6,
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Text(
                      signal.score.round().toString(),
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, color: color, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            _label,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _summary,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 12),
          // ── Factor breakdown ────────────────────────────────────────────
          ...signal.factors.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FactorRow(factor: f),
              )),
          const SizedBox(height: 2),
          const Text(
            'Heuristic guide, not financial advice.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  final SignalFactor factor;
  const _FactorRow({required this.factor});

  Color _scoreColor(double s) {
    if (s >= 70) return AppTheme.profit;
    if (s >= 45) return const Color(0xFFFFD700);
    if (s >= 30) return const Color(0xFFFF9800);
    return AppTheme.loss;
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(factor.score);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              factor.label,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            Text(
              factor.detail,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: factor.score / 100,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 5,
          ),
        ),
      ],
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
