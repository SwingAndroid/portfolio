import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/crypto_entity.dart';
import '../../domain/entities/value_snapshot.dart';
import '../bloc/history/portfolio_history_cubit.dart';
import '../bloc/history/portfolio_history_state.dart';

/// Portfolio value over time, against the capital actually engaged.
///
/// The gap between the two lines is the P&L, drawn rather than stated.
class PortfolioValueChart extends StatelessWidget {
  final List<CryptoEntity> cryptos;

  const PortfolioValueChart({super.key, required this.cryptos});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PortfolioHistoryCubit, PortfolioHistoryState>(
      builder: (context, state) {
        final days = switch (state) {
          PortfolioHistoryLoading(:final days) => days,
          PortfolioHistoryLoaded(:final days) => days,
          _ => 90,
        };

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
                  const Icon(Icons.show_chart_rounded,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 6),
                  const Text('Portfolio Value',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  ...PortfolioHistoryCubit.ranges.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _RangeChip(
                        label: r.$2,
                        selected: days == r.$1,
                        onTap: () => context
                            .read<PortfolioHistoryCubit>()
                            .load(cryptos, days: r.$1),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(height: 190, child: _body(context, state)),
              if (state is PortfolioHistoryLoaded && state.isDrawable) ...[
                const SizedBox(height: 14),
                _Summary(points: state.history.points),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, PortfolioHistoryState state) {
    if (state is PortfolioHistoryLoading || state is PortfolioHistoryInitial) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
        ),
      );
    }

    final loaded = state as PortfolioHistoryLoaded;
    if (loaded.isDrawable) return _Chart(points: loaded.history.points, days: loaded.days);

    final failed = loaded.history.backfillError != null;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(failed ? Icons.cloud_off_rounded : Icons.timeline_rounded,
              color: AppTheme.textTertiary, size: 26),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              failed
                  ? 'Market data could not be loaded, so past days could not '
                      'be rebuilt. Only days recorded live are shown.'
                  : 'Not enough history yet. A value is recorded each day the '
                      'app is opened online.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
          if (failed) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => context
                  .read<PortfolioHistoryCubit>()
                  .load(cryptos, days: loaded.days, force: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  final List<ValueSnapshot> points;
  final int days;

  const _Chart({required this.points, required this.days});

  String _yLabel(double v) {
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final value = [
      for (final p in points)
        FlSpot(p.date.millisecondsSinceEpoch.toDouble(), p.value)
    ];
    final invested = [
      for (final p in points)
        FlSpot(p.date.millisecondsSinceEpoch.toDouble(), p.invested)
    ];

    final minX = value.first.x;
    final maxX = value.last.x;

    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      minY = math.min(minY, math.min(p.value, p.invested));
      maxY = math.max(maxY, math.max(p.value, p.invested));
    }
    final span = maxY - minY;
    final pad = span == 0 ? (maxY == 0 ? 1 : maxY * 0.1) : span * 0.12;
    minY = math.max(0, minY - pad);
    maxY = maxY + pad;

    final yInterval = (maxY - minY) / 3;
    final dateFmt = days >= 365 ? DateFormat('MMM yy') : DateFormat('MMM d');

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval > 0 ? yInterval : null,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.divider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yInterval > 0 ? yInterval : null,
              getTitlesWidget: (v, meta) {
                if (v <= minY || v >= maxY) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(_yLabel(v),
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 9)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (maxX - minX) / 3,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  dateFmt.format(
                      DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 9),
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surfaceVariant,
            getTooltipItems: (spots) => spots.map((s) {
              final isValue = s.barIndex == 0;
              return LineTooltipItem(
                '${isValue ? 'Value' : 'Invested'} '
                '${Formatters.formatCurrency(s.y)}',
                TextStyle(
                  color: isValue ? AppTheme.primary : AppTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: value,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppTheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withOpacity(0.10),
            ),
          ),
          LineChartBarData(
            spots: invested,
            isCurved: false,
            color: AppTheme.accent,
            barWidth: 1.5,
            dashArray: const [4, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final List<ValueSnapshot> points;

  const _Summary({required this.points});

  @override
  Widget build(BuildContext context) {
    final last = points.last;
    final profit = last.profitLoss >= 0;

    return Row(
      children: [
        const _LegendDot(color: AppTheme.primary, label: 'Value'),
        const SizedBox(width: 14),
        const _LegendDot(
            color: AppTheme.accent, label: 'Invested', dashed: true),
        const Spacer(),
        Text(
          Formatters.formatCurrencyWithSign(last.profitLoss),
          style: TextStyle(
            color: profit ? AppTheme.profit : AppTheme.loss,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: dashed ? 0 : 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed ? Border(top: BorderSide(color: color, width: 2)) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 10)),
      ],
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.15)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
