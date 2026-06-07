import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/crypto_entity.dart';

// ── Colour palette assigned by rank (largest holding = first colour) ──────────
const List<Color> _palette = [
  Color(0xFF9EF542), // lime-green  (primary)
  Color(0xFF3D8BFF), // blue
  Color(0xFFFFD700), // gold
  Color(0xFFFF6B35), // orange
  Color(0xFFB14BF4), // purple
  Color(0xFF00D2FF), // cyan
  Color(0xFFE91E63), // pink
  Color(0xFF4CAF50), // green
  Color(0xFFFFAB40), // amber
  Color(0xFF607D8B), // blue-grey
];

Color _colorFor(int index) => _palette[index % _palette.length];

// ─────────────────────────────────────────────────────────────────────────────

class PortfolioAllocationCard extends StatefulWidget {
  final List<CryptoEntity> cryptos;
  final double totalValue;

  const PortfolioAllocationCard({
    super.key,
    required this.cryptos,
    required this.totalValue,
  });

  @override
  State<PortfolioAllocationCard> createState() =>
      _PortfolioAllocationCardState();
}

class _PortfolioAllocationCardState extends State<PortfolioAllocationCard> {
  int _touched = -1;

  List<CryptoEntity> get _sorted {
    final list = [...widget.cryptos];
    list.sort((a, b) => b.holdingsValue.compareTo(a.holdingsValue));
    return list;
  }

  double _pct(CryptoEntity c) {
    if (widget.totalValue == 0) return 0;
    return (c.holdingsValue / widget.totalValue) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    if (sorted.isEmpty || widget.totalValue == 0) return const SizedBox();

    final isWide = MediaQuery.of(context).size.width >= 700;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          const Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded,
                  color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Portfolio Allocation',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Chart + List ─────────────────────────────────────────────────
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _DonutChart(
                      sorted: sorted,
                      totalValue: widget.totalValue,
                      pct: _pct,
                      touched: _touched,
                      onTouch: (i) => setState(() => _touched = i),
                      size: 200,
                    ),
                    const SizedBox(width: 32),
                    Expanded(child: _AllocationList(sorted: sorted, pct: _pct, touched: _touched)),
                  ],
                )
              : Column(
                  children: [
                    _DonutChart(
                      sorted: sorted,
                      totalValue: widget.totalValue,
                      pct: _pct,
                      touched: _touched,
                      onTouch: (i) => setState(() => _touched = i),
                      size: 180,
                    ),
                    const SizedBox(height: 24),
                    _AllocationList(sorted: sorted, pct: _pct, touched: _touched),
                  ],
                ),
        ],
      ),
    );
  }
}

// ── Donut chart ───────────────────────────────────────────────────────────────

class _DonutChart extends StatelessWidget {
  final List<CryptoEntity> sorted;
  final double totalValue;
  final double Function(CryptoEntity) pct;
  final int touched;
  final ValueChanged<int> onTouch;
  final double size;

  const _DonutChart({
    required this.sorted,
    required this.totalValue,
    required this.pct,
    required this.touched,
    required this.onTouch,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final selected = touched >= 0 && touched < sorted.length
        ? sorted[touched]
        : null;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.30,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response == null ||
                      response.touchedSection == null) {
                    onTouch(-1);
                    return;
                  }
                  onTouch(response.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: List.generate(sorted.length, (i) {
                final c = sorted[i];
                final p = pct(c);
                final isTouched = i == touched;
                return PieChartSectionData(
                  value: p,
                  color: _colorFor(i),
                  radius: isTouched ? size * 0.30 : size * 0.26,
                  title: p >= 8 ? '${p.toStringAsFixed(1)}%' : '',
                  titleStyle: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                  badgeWidget: null,
                );
              }),
            ),
          ),
          // ── Centre label ─────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: selected != null
                ? _CentreLabel(
                    key: ValueKey(selected.id),
                    symbol: selected.symbol,
                    value: Formatters.formatCurrency(selected.holdingsValue),
                    pct: pct(selected),
                    color: _colorFor(sorted.indexOf(selected)),
                  )
                : _CentreLabel(
                    key: const ValueKey('total'),
                    symbol: 'TOTAL',
                    value: Formatters.formatCurrency(totalValue),
                    pct: 100,
                    color: AppTheme.primary,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CentreLabel extends StatelessWidget {
  final String symbol;
  final String value;
  final double pct;
  final Color color;

  const _CentreLabel({
    super.key,
    required this.symbol,
    required this.value,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          symbol,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        if (pct < 100)
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

// ── Allocation list ───────────────────────────────────────────────────────────

class _AllocationList extends StatelessWidget {
  final List<CryptoEntity> sorted;
  final double Function(CryptoEntity) pct;
  final int touched;

  const _AllocationList({
    required this.sorted,
    required this.pct,
    required this.touched,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(sorted.length, (i) {
        final c = sorted[i];
        final p = pct(c);
        final isHighlighted = i == touched;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted
                ? _colorFor(i).withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHighlighted
                  ? _colorFor(i).withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Colour dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _colorFor(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              // Coin name
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.symbol.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      c.name,
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Progress bar
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p / 100,
                        backgroundColor: AppTheme.surfaceVariant,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_colorFor(i)),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${p.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: _colorFor(i),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Value
              Text(
                Formatters.formatCurrency(c.holdingsValue),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
