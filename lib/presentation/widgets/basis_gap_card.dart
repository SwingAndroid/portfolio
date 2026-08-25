import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/analytics/basis_gap.dart';
import '../pages/basis_gap_page.dart';

/// Surfaces holdings that sit at zero cost basis.
///
/// Renders nothing when there are none, so a tidy portfolio is not nagged
/// about a problem it does not have.
class BasisGapCard extends StatelessWidget {
  final List<CoinBasisGaps> gaps;

  const BasisGapCard({super.key, required this.gaps});

  @override
  Widget build(BuildContext context) {
    if (gaps.isEmpty) return const SizedBox.shrink();

    final rows = gaps.fold(0, (sum, g) => sum + g.count);

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
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  color: Color(0xFFF97316), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Missing cost basis',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('$rows rows',
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'These coins arrived without a price, so the app treats them as '
            'free. Any sale would look like pure profit.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 16),
          for (final coin in gaps) _CoinLine(coin: coin),
        ],
      ),
    );
  }
}

class _CoinLine extends StatelessWidget {
  final CoinBasisGaps coin;

  const _CoinLine({required this.coin});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BasisGapPage(coin: coin)),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                coin.symbol,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                '${Formatters.formatCryptoAmount(coin.quantity)} '
                'across ${coin.count} rows',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${coin.shareOfHoldings.toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: Color(0xFFF97316),
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
