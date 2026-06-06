import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class PortfolioHeader extends StatelessWidget {
  final double totalValue;
  final double totalPnl;
  final double totalPnlPercent;
  final bool isLoaded;

  const PortfolioHeader({
    super.key,
    required this.totalValue,
    required this.totalPnl,
    required this.totalPnlPercent,
    required this.isLoaded,
  });

  @override
  Widget build(BuildContext context) {
    final isProfit = totalPnl >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;
    final pnlIcon = isProfit ? Icons.arrow_drop_up : Icons.arrow_drop_down;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Portfolio',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Icon(Icons.settings_outlined,
                    color: AppTheme.textSecondary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Total Balance',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            isLoaded ? Formatters.formatCurrency(totalValue) : '--',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (isLoaded)
            Row(
              children: [
                Icon(pnlIcon, color: pnlColor, size: 20),
                Text(
                  '${Formatters.formatCurrencyWithSign(totalPnl)}  (${Formatters.formatPercent(totalPnlPercent)})',
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('All time',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
              ],
            ),
          const SizedBox(height: 20),
          const Divider(color: AppTheme.divider),
          const SizedBox(height: 8),
          const Text(
            'Assets',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
