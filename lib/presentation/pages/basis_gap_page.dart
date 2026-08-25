import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/analytics/basis_gap.dart';
import '../../injection_container.dart';
import '../bloc/basis_gap/basis_gap_cubit.dart';

/// Review screen for one coin's holdings that carry no recorded price.
///
/// Every row is priced from the day it arrived and shown before anything is
/// written. The user ticks what was genuinely income; a transfer between two
/// of their own wallets stays untouched.
class BasisGapPage extends StatelessWidget {
  final CoinBasisGaps coin;

  /// Supplied by tests. The app resolves it from the container, which a widget
  /// test cannot reach without standing up the whole graph.
  final BasisGapCubit? cubit;

  const BasisGapPage({super.key, required this.coin, this.cubit});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => (cubit ?? sl<BasisGapCubit>())..load(coin),
      child: _BasisGapView(coin: coin),
    );
  }
}

class _BasisGapView extends StatelessWidget {
  final CoinBasisGaps coin;

  const _BasisGapView({required this.coin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text('${coin.symbol} · missing cost',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: BlocBuilder<BasisGapCubit, BasisGapState>(
        builder: (context, state) {
          if (state.error != null) return _Failed(error: state.error!);
          if (state.isLoading || state.ready == null) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary));
          }
          return _Review(ready: state.ready!);
        },
      ),
    );
  }
}

class _Review extends StatelessWidget {
  final BasisGapReady ready;

  const _Review({required this.ready});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BasisGapCubit>();

    if (ready.gaps.isEmpty) {
      return const _AllDone();
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _Explainer(ready: ready),
              if (ready.unreachable > 0) ...[
                const SizedBox(height: 12),
                _OutOfReach(count: ready.unreachable),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('${ready.gaps.length} rows',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const Spacer(),
                  TextButton(
                      onPressed: cubit.selectAll,
                      child: const Text('All',
                          style: TextStyle(color: AppTheme.primary))),
                  TextButton(
                      onPressed: cubit.selectNone,
                      child: const Text('None',
                          style: TextStyle(color: AppTheme.textSecondary))),
                ],
              ),
              const SizedBox(height: 4),
              for (final gap in ready.gaps)
                _GapRow(
                  gap: gap,
                  symbol: ready.coin.symbol,
                  selected: ready.selected.contains(gap.transaction.id),
                  onTap: () => cubit.toggle(gap.transaction.id),
                ),
            ],
          ),
        ),
        _ConfirmBar(ready: ready),
      ],
    );
  }
}

class _Explainer extends StatelessWidget {
  final BasisGapReady ready;

  const _Explainer({required this.ready});

  @override
  Widget build(BuildContext context) {
    final coin = ready.coin;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Formatters.formatCryptoAmount(coin.quantity)} ${coin.symbol} '
            'entered your portfolio without a price',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'That is ${coin.shareOfHoldings.toStringAsFixed(0)}% of what you '
            'hold, sitting at zero cost. Selling it would book every cent as '
            'gain. Tick the rows that were staking or airdrop income and they '
            'will be recorded at the price of the day they arrived.',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'Leave a plain wallet-to-wallet transfer unticked — it was never '
            'income.',
            style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _OutOfReach extends StatelessWidget {
  final int count;

  const _OutOfReach({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF97316).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_rounded,
              color: Color(0xFFF97316), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'row is' : 'rows are'} older than the '
              'year of price history available, so they cannot be valued.',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  final ResolvedGap gap;
  final String symbol;
  final bool selected;
  final VoidCallback onTap;

  const _GapRow({
    required this.gap,
    required this.symbol,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reachable = gap.resolvable;

    return Opacity(
      opacity: reachable ? 1 : 0.45,
      child: InkWell(
        onTap: reachable ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: selected ? AppTheme.primary : AppTheme.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Formatters.formatShortDate(gap.transaction.date),
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.formatCryptoAmount(gap.transaction.quantity)} '
                      '$symbol',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    reachable
                        ? Formatters.formatCurrency(gap.value)
                        : 'no price',
                    style: TextStyle(
                        color: reachable
                            ? AppTheme.textPrimary
                            : AppTheme.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  if (reachable) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@ ${gap.price!.toStringAsFixed(4)}',
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final BasisGapReady ready;

  const _ConfirmBar({required this.ready});

  @override
  Widget build(BuildContext context) {
    final count = ready.chosen.length;
    final enabled = count > 0 && !ready.isApplying;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Income to record',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.formatCurrency(ready.selectedIncome),
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: enabled ? () => _confirm(context) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppTheme.surfaceVariant,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: ready.isApplying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2),
                  )
                : Text(
                    count == 0
                        ? 'Nothing selected'
                        : 'Record $count as reward${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final cubit = context.read<BasisGapCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await cubit.applySelection();
    if (result == null) return;

    messenger.showSnackBar(
      SnackBar(
        backgroundColor:
            result.hasFailures ? AppTheme.loss : AppTheme.surfaceVariant,
        content: Text(
          result.hasFailures
              ? '${result.written} recorded, ${result.failedIds.length} '
                  'could not be saved — they are still listed'
              : '${result.written} recorded as income',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppTheme.profit, size: 40),
            SizedBox(height: 12),
            Text('Every holding here has a recorded cost',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final Object error;

  const _Failed({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppTheme.textTertiary, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Could not load the price history',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing was changed. Try again in a minute — the price service '
              'limits how often it can be asked.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
