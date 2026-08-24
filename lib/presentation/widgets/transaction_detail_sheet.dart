import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction_entity.dart';

/// Everything about one movement, including the unit price the list has no
/// room for.
///
/// The unit price is the number a DCA position is actually made of — the
/// average is nothing but a weighted pile of these — yet the list only ever
/// showed quantity and total.
Future<void> showTransactionDetail(
  BuildContext context, {
  required TransactionEntity transaction,
  required String symbol,
  required double currentPrice,
  required double avgBuyPrice,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _Detail(
      transaction: transaction,
      symbol: symbol,
      currentPrice: currentPrice,
      avgBuyPrice: avgBuyPrice,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

class _Detail extends StatelessWidget {
  final TransactionEntity transaction;
  final String symbol;
  final double currentPrice;
  final double avgBuyPrice;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _Detail({
    required this.transaction,
    required this.symbol,
    required this.currentPrice,
    required this.avgBuyPrice,
    this.onEdit,
    this.onDelete,
  });

  String get _label => switch (transaction.type) {
        TransactionType.buy => 'Buy',
        TransactionType.sell => 'Sell',
        TransactionType.transferIn => 'Transfer In',
        TransactionType.transferOut => 'Transfer Out',
        TransactionType.reward => 'Reward',
      };

  Color get _color => switch (transaction.type) {
        TransactionType.buy => AppTheme.profit,
        TransactionType.sell => AppTheme.loss,
        TransactionType.transferIn => const Color(0xFF3B82F6),
        TransactionType.transferOut => const Color(0xFFF97316),
        TransactionType.reward => const Color(0xFFA855F7),
      };

  bool get _isBuy => transaction.type == TransactionType.buy;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final priced = t.pricePerCoin > 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _label,
                    style: TextStyle(
                        color: _color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Text(
                  Formatters.formatDate(t.date),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // The unit price gets the headline: it is what the average is
            // built from, and what today's price is judged against.
            if (priced) ...[
              Text(
                Formatters.formatPrice(t.pricePerCoin),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'per coin',
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
              ),
            ] else
              const Text(
                'No cost basis recorded',
                style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 20),

            _Line(
              label: 'Quantity',
              value: '${Formatters.formatCryptoAmount(t.quantity)} $symbol',
            ),
            if (priced)
              _Line(
                label: 'Gross',
                value: Formatters.formatCurrency(t.totalValue),
              ),
            if (t.fee > 0)
              _Line(
                label: 'Fee',
                value: Formatters.formatCurrency(t.fee),
              ),
            _Line(
              label: t.type.removesHoldings ? 'Net proceeds' : 'Total cost',
              value: Formatters.formatCurrency(
                t.type.removesHoldings ? t.netProceeds : t.grossCost,
              ),
              strong: true,
            ),
            if (t.note != null && t.note!.isNotEmpty)
              _Line(label: 'Note', value: t.note!),

            // ── How this particular lot has fared ──────────────────────────
            if (_isBuy && priced && currentPrice > 0) ...[
              const SizedBox(height: 8),
              const Divider(color: AppTheme.divider),
              const SizedBox(height: 8),
              _Line(
                label: 'Price now',
                value: Formatters.formatPrice(currentPrice),
              ),
              _Change(
                label: 'This lot',
                percent:
                    (currentPrice - t.pricePerCoin) / t.pricePerCoin * 100,
                amount: (currentPrice - t.pricePerCoin) * t.quantity,
              ),
              if (avgBuyPrice > 0)
                _Change(
                  label: 'Versus your average',
                  percent:
                      (t.pricePerCoin - avgBuyPrice) / avgBuyPrice * 100,
                  invert: true,
                ),
              const SizedBox(height: 10),
              const Text(
                'Your position is one pile of coins at a single average cost. '
                'A lot in the red is not a separate loss you can act on.',
                style: TextStyle(
                    color: AppTheme.textTertiary, fontSize: 10, height: 1.4),
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                if (onEdit != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onEdit!();
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.cardBorder),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (onEdit != null && onDelete != null)
                  const SizedBox(width: 10),
                if (onDelete != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onDelete!();
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.loss,
                        side: BorderSide(color: AppTheme.loss.withOpacity(0.4)),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _Line({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  final String label;
  final double percent;
  final double? amount;

  /// When true a negative number is the good outcome — buying below your
  /// average pulls it down.
  final bool invert;

  const _Change({
    required this.label,
    required this.percent,
    this.amount,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    final good = invert ? percent <= 0 : percent >= 0;
    final colour = good ? AppTheme.profit : AppTheme.loss;
    final suffix = invert ? (percent <= 0 ? ' below' : ' above') : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(
            '${Formatters.formatPercent(percent)}$suffix',
            style: TextStyle(
                color: colour, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (amount != null) ...[
            const SizedBox(width: 8),
            Text(
              Formatters.formatCurrencyWithSign(amount!),
              style: TextStyle(
                  color: colour, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
