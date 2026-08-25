import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/analytics/benchmark.dart';
import '../../domain/entities/crypto_entity.dart';
import '../bloc/benchmark/benchmark_cubit.dart';

/// Would simply holding one asset have done better?
///
/// The portfolio's own return says how it did, never whether that was good.
/// Both sides here start the window at the same value and receive the same
/// contributions on the same days, so the only variable left is what was held.
class BenchmarkCard extends StatelessWidget {
  final List<CryptoEntity> cryptos;

  const BenchmarkCard({super.key, required this.cryptos});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BenchmarkCubit, BenchmarkState>(
      builder: (context, state) {
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
                  Icon(Icons.compare_arrows_rounded,
                      color: AppTheme.primary, size: 18),
                  SizedBox(width: 6),
                  Text('Versus just holding',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              _body(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, BenchmarkState state) {
    if (state.isLoading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primary),
          ),
        ),
      );
    }

    final result = state.result!;
    if (!result.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.error != null
                ? 'Market data could not be loaded, so there is nothing to '
                    'compare against yet.'
                : 'Not enough history to compare a period yet.',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
          ),
          if (result.error != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () =>
                  context.read<BenchmarkCubit>().load(cryptos, force: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ],
      );
    }

    final first = result.outcomes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Same starting value, same contributions on the same days — only the '
          'choice of what to hold differs.',
          style: const TextStyle(
              color: AppTheme.textTertiary, fontSize: 10, height: 1.4),
        ),
        const SizedBox(height: 14),
        _Row(
          label: 'Your portfolio',
          value: Formatters.formatCurrency(first.actualValue),
          rate: first.actualRate,
          highlight: true,
        ),
        for (final outcome in result.outcomes)
          _Row(
            label: 'All in ${outcome.symbol}',
            value: Formatters.formatCurrency(outcome.benchmarkValue),
            rate: outcome.benchmarkRate,
            highlight: false,
          ),
        const SizedBox(height: 12),
        const Divider(color: AppTheme.divider, height: 1),
        const SizedBox(height: 12),
        for (final outcome in result.outcomes) _Verdict(outcome: outcome),
        const SizedBox(height: 10),
        Text(
          _scopeNote(result.windowCoverage, first),
          style: const TextStyle(
              color: AppTheme.textTertiary, fontSize: 10, height: 1.4),
        ),
      ],
    );
  }

  /// States the limits of the comparison rather than letting it look complete.
  static String _scopeNote(double coverage, BenchmarkOutcome outcome) {
    final days = outcome.to.difference(outcome.from).inDays;
    final pct = (coverage * 100).round();
    final period = 'Measured over the last $days days — '
        'free price history does not reach further back.';
    if (coverage >= 0.99) return period;
    return '$period It covers $pct% of everything you have ever put in; '
        'contributions before that window are excluded from both sides.';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final double? rate;
  final bool highlight;

  const _Row({
    required this.label,
    required this.value,
    required this.rate,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: highlight ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (rate != null) ...[
            Text(
              Formatters.formatPercent(rate! * 100),
              style: TextStyle(
                color: rate! >= 0 ? AppTheme.profit : AppTheme.loss,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final BenchmarkOutcome outcome;

  const _Verdict({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final ahead = outcome.aheadOfBenchmark;
    final colour = ahead ? AppTheme.profit : AppTheme.loss;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ahead ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 15, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ahead
                  ? 'Ahead of ${outcome.symbol}'
                  : 'Behind ${outcome.symbol}',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Text(
            Formatters.formatCurrencyWithSign(outcome.difference),
            style: TextStyle(
                color: colour, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (outcome.rateGap != null) ...[
            const SizedBox(width: 8),
            Text(
              '${outcome.rateGap! >= 0 ? '+' : ''}'
              '${outcome.rateGap!.toStringAsFixed(1)} pts',
              style: TextStyle(
                  color: colour, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
