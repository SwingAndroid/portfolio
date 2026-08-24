import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/datasources/cloud/sync_service.dart';
import '../../domain/analytics/tax_report.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../injection_container.dart';
import '../bloc/portfolio/portfolio_bloc.dart';
import '../bloc/portfolio/portfolio_state.dart';

/// Everything that gets data out of the app: a local backup, the realized
/// gains a return asks for, and CSV for a spreadsheet.
///
/// Deliberately offline-first — it reads Hive and computes from local
/// transactions, so it still works when every network path is broken.
Future<void> showBackupSheet(BuildContext context) async {
  final json = await sl<SyncService>().exportJson();
  if (!context.mounted) return;

  final portfolioState = context.read<PortfolioBloc>().state;
  final cryptos = portfolioState is PortfolioLoaded
      ? portfolioState.cryptos
      : const <CryptoEntity>[];
  final report = TaxReport.from(cryptos);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.save_alt_rounded, color: AppTheme.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  'Data & tax',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Computed on this device. Works with no network.',
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (!report.isEmpty) ...[
                    _RealizedGains(report: report),
                    const SizedBox(height: 20),
                  ],
                  _ExportButton(
                    icon: Icons.data_object_rounded,
                    label: 'Backup (JSON)',
                    hint: 'Everything held locally, including anything the '
                        'cloud never received',
                    payload: json,
                    filled: true,
                  ),
                  const SizedBox(height: 10),
                  _ExportButton(
                    icon: Icons.table_chart_outlined,
                    label: 'Transactions (CSV)',
                    hint: 'Every movement, for a spreadsheet',
                    payload: transactionsCsv(cryptos),
                  ),
                  const SizedBox(height: 10),
                  _ExportButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'Realized gains (CSV)',
                    hint: report.isEmpty
                        ? 'No sales recorded yet'
                        : '${report.disposals.length} disposals, for a return',
                    payload: disposalsCsv(report),
                    enabled: !report.isEmpty,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Backup preview',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: SelectableText(
                      json,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Realized gains per calendar year — what a return actually asks for.
class _RealizedGains extends StatelessWidget {
  final TaxReport report;

  const _RealizedGains({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Realized gains by year',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sales only. Moving coins between wallets is not a disposal.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
          ),
          const SizedBox(height: 12),
          for (final year in report.years)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${year.year}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _describe(year),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    Formatters.formatCurrencyWithSign(year.gain),
                    style: TextStyle(
                      color: year.gain >= 0 ? AppTheme.profit : AppTheme.loss,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: AppTheme.divider, height: 20),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                Formatters.formatCurrencyWithSign(report.totalGain),
                style: TextStyle(
                  color:
                      report.totalGain >= 0 ? AppTheme.profit : AppTheme.loss,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _describe(TaxYearSummary year) {
    final plural = year.disposalCount == 1 ? 'sale' : 'sales';
    return '${year.disposalCount} $plural · '
        '${Formatters.formatCurrency(year.proceeds)} in';
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final String payload;
  final bool filled;
  final bool enabled;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.payload,
    this.filled = false,
    this.enabled = true,
  });

  String get _size {
    final kb = payload.length / 1024;
    if (kb < 1) return '${payload.length} B';
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => _copy(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:
                filled ? AppTheme.primary.withOpacity(0.10) : AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: filled ? AppTheme.primary : AppTheme.cardBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _size,
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.copy_rounded,
                  size: 16, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.surface,
        content: Text(
          '$label copied to clipboard',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}
