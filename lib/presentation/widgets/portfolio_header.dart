import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class PortfolioHeader extends StatelessWidget {
  final double totalValue;
  final double totalCost;
  final double totalPnl;
  final double totalPnlPercent;
  final int numAssets;
  final String? bestSymbol;
  final double? bestPercent;
  final String? worstSymbol;
  final double? worstPercent;
  final bool isLoaded;

  const PortfolioHeader({
    super.key,
    required this.totalValue,
    required this.totalCost,
    required this.totalPnl,
    required this.totalPnlPercent,
    required this.numAssets,
    required this.isLoaded,
    this.bestSymbol,
    this.bestPercent,
    this.worstSymbol,
    this.worstPercent,
  });

  @override
  Widget build(BuildContext context) {
    final isProfit = totalPnl >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;
    final pnlIcon = isProfit ? Icons.arrow_drop_up : Icons.arrow_drop_down;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Portfolio',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'v${AppConstants.appVersion}',
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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

          // ── Total balance ────────────────────────────────────────────────
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
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                const Text('All time',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 12)),
              ],
            ),
          const SizedBox(height: 20),

          // ── Stats chips row ─────────────────────────────────────────────
          if (isLoaded)
            Row(
              children: [
                _StatChip(
                  label: 'Invested',
                  value: Formatters.formatCurrency(totalCost),
                  icon: Icons.paid_outlined,
                ),
                const SizedBox(width: 10),
                _StatChip(
                  label: 'Assets',
                  value: '$numAssets coins',
                  icon: Icons.grid_view_rounded,
                ),
                const SizedBox(width: 10),
                if (bestSymbol != null)
                  _StatChip(
                    label: 'Best',
                    value:
                        '${bestSymbol!} ${bestPercent! >= 0 ? '+' : ''}${bestPercent!.toStringAsFixed(1)}%',
                    valueColor: AppTheme.profit,
                    icon: Icons.trending_up,
                  ),
              ],
            ),
          const SizedBox(height: 20),
          const Divider(color: AppTheme.divider),
          const SizedBox(height: 8),
          const Text(
            'ASSETS',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
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
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
