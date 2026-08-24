import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction_entity.dart';

class TransactionTile extends StatelessWidget {
  final TransactionEntity transaction;
  final String cryptoSymbol;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.cryptoSymbol,
    this.onDelete,
    this.onEdit,
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  Color _typeColor() {
    switch (transaction.type) {
      case TransactionType.buy:
        return AppTheme.profit;
      case TransactionType.sell:
        return AppTheme.loss;
      case TransactionType.transferIn:
        return const Color(0xFF3B82F6); // blue
      case TransactionType.transferOut:
        return const Color(0xFFF97316); // orange
      case TransactionType.reward:
        return const Color(0xFFA855F7); // violet — income, not a trade
    }
  }

  String _typeLabel() {
    switch (transaction.type) {
      case TransactionType.buy:
        return 'Buy';
      case TransactionType.sell:
        return 'Sell';
      case TransactionType.transferIn:
        return 'Transfer In';
      case TransactionType.transferOut:
        return 'Transfer Out';
      case TransactionType.reward:
        return 'Reward';
    }
  }

  IconData _typeIcon() {
    switch (transaction.type) {
      case TransactionType.buy:
        return Icons.arrow_downward_rounded;
      case TransactionType.sell:
        return Icons.arrow_upward_rounded;
      case TransactionType.transferIn:
        return Icons.call_received_rounded;
      case TransactionType.transferOut:
        return Icons.call_made_rounded;
      case TransactionType.reward:
        return Icons.card_giftcard_rounded;
    }
  }

  String _amountPrefix() =>
      transaction.type.addsHoldings ? '+' : '-';

  @override
  Widget build(BuildContext context) {
    final color = _typeColor();

    return Dismissible(
      key: Key(transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => false,
      background: Container(
        alignment: Alignment.centerRight,
        color: AppTheme.loss.withValues(alpha: 0.1),
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: AppTheme.loss),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(), color: color, size: 18),
            ),
            const SizedBox(width: 12),
            // Label + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _typeLabel(),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.formatShortDate(transaction.date),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Amount + value
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_amountPrefix()}${Formatters.formatCryptoAmount(transaction.quantity)} $cryptoSymbol',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                transaction.pricePerCoin > 0
                    ? Text(
                        Formatters.formatCurrency(transaction.totalValue),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      )
                    : const Text(
                        'No cost basis',
                        style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
              ],
            ),
            // A "more" icon that deleted on a single tap, with no menu and no
            // way back, was one slip away from losing a row.
            if (onDelete != null || onEdit != null) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: AppTheme.textTertiary, size: 18),
                color: AppTheme.surfaceVariant,
                padding: EdgeInsets.zero,
                splashRadius: 18,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (choice) {
                  if (choice == 'edit') onEdit?.call();
                  if (choice == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 16, color: AppTheme.textSecondary),
                          SizedBox(width: 10),
                          Text('Edit',
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: AppTheme.loss),
                          SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(
                                  color: AppTheme.loss, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
