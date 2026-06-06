import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/crypto_entity.dart';

class CryptoCard extends StatelessWidget {
  final CryptoEntity crypto;
  final VoidCallback? onTap;

  const CryptoCard({super.key, required this.crypto, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isProfit = crypto.totalProfitLoss >= 0;
    final pnlColor = isProfit ? AppTheme.profit : AppTheme.loss;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            // Coin icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(22),
              ),
              child: crypto.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.network(
                        crypto.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(),
                      ),
                    )
                  : _fallback(),
            ),
            const SizedBox(width: 12),
            // Coin name & holdings
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crypto.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.formatCrypto(crypto.totalHoldings, crypto.symbol),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            // Value & P&L
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.formatCurrency(crypto.holdingsValue),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isProfit ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: pnlColor,
                      size: 16,
                    ),
                    Text(
                      Formatters.formatPercent(crypto.totalProfitLossPercent).replaceAll('+', ''),
                      style: TextStyle(color: pnlColor, fontSize: 12),
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

  Widget _fallback() =>
      const Icon(Icons.currency_bitcoin, color: AppTheme.primary, size: 22);
}
