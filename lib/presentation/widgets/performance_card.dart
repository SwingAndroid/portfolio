import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../bloc/portfolio/portfolio_state.dart';

/// Shows the total return next to the annualised one.
///
/// The app's headline figure has always been `(value − cost) / cost`, which
/// weights a euro invested four years ago the same as one invested last week.
/// Placing the money-weighted rate beside it is the point of this card: when
/// most capital arrived recently, the two numbers tell very different stories.
class PerformanceCard extends StatelessWidget {
  final PortfolioLoaded state;

  const PerformanceCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final simple = state.totalProfitLossPercent;
    final annualised = state.moneyWeightedReturn;
    final start = state.firstTransactionDate;

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
              Icon(Icons.query_stats_rounded,
                  color: AppTheme.primary, size: 18),
              SizedBox(width: 6),
              Text('Performance',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Metric(
                  label: 'Total return',
                  value: Formatters.formatPercent(simple),
                  positive: simple >= 0,
                  caption: start == null
                      ? 'since inception'
                      : 'since ${Formatters.formatShortDate(start)}',
                ),
              ),
              Container(
                width: 1,
                height: 54,
                color: AppTheme.divider,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: _Metric(
                  label: 'Annualised (XIRR)',
                  value: annualised == null
                      ? '—'
                      : Formatters.formatPercent(annualised * 100),
                  positive: (annualised ?? 0) >= 0,
                  caption: 'per year, money-weighted',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            annualised == null
                ? 'Not enough cash flow history to annualise a rate yet.'
                : 'Total return spreads the result across the whole period. '
                    'The annualised rate weights each contribution by how long '
                    'it was actually invested.',
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 11, height: 1.4),
          ),
          if (state.cryptos.length > 1) ...[
            const SizedBox(height: 14),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 12),
            _ConcentrationRow(index: state.concentrationIndex),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool positive;
  final String caption;

  const _Metric({
    required this.label,
    required this.value,
    required this.positive,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: value == '—'
                ? AppTheme.textTertiary
                : (positive ? AppTheme.profit : AppTheme.loss),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(caption,
            style:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
      ],
    );
  }
}

/// Herfindahl index of the allocation. Reported, not judged: it says how
/// spread the book is, nothing about whether that is right for you.
class _ConcentrationRow extends StatelessWidget {
  final double index;

  const _ConcentrationRow({required this.index});

  String get _label {
    if (index >= 2500) return 'concentrated';
    if (index >= 1500) return 'moderately concentrated';
    return 'spread out';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.pie_chart_outline_rounded,
            color: AppTheme.textTertiary, size: 15),
        const SizedBox(width: 8),
        const Text('Concentration',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(width: 12),
        // The label grows with the verdict; an unconstrained Text after a
        // Spacer overflowed the card by 217 pixels on a phone.
        Expanded(
          child: Text(
            '${index.toStringAsFixed(0)} · $_label',
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
