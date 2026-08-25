import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/analytics/diversification.dart';
import '../../domain/entities/crypto_entity.dart';
import '../bloc/diversification/diversification_cubit.dart';

/// Whether the spread of holdings actually spreads any risk.
///
/// The allocation donut shows how the money is split. It cannot show that the
/// slices rise and fall together, which is the difference between owning
/// several positions and owning one position several times.
class DiversificationCard extends StatelessWidget {
  final List<CryptoEntity> cryptos;

  const DiversificationCard({super.key, required this.cryptos});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiversificationCubit, DiversificationState>(
      builder: (context, state) {
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
                  Icon(Icons.hub_outlined, color: AppTheme.primary, size: 18),
                  SizedBox(width: 6),
                  Text('Diversification',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              _body(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, DiversificationState state) {
    if (state.isLoading) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.primary),
          ),
        ),
      );
    }

    final result = state.result!;
    if (!result.hasAnything) {
      return Text(
        result.error != null
            ? 'Market data could not be loaded, so the spread of your holdings '
                'cannot be measured yet.'
            : 'At least two priced holdings are needed to measure whether they '
                'move together.',
        style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
      );
    }

    final report = result.report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.hasData) ...[
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Real benefit',
                  value: '${(report.benefit * 100).toStringAsFixed(0)}%',
                  hint: 'volatility removed',
                  emphasis: report.benefit < 0.25,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Avg correlation',
                  value: report.averageCorrelation.toStringAsFixed(2),
                  hint: '1.00 = one position',
                  emphasis: report.averageCorrelation > 0.7,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Volatility',
                  value:
                      '${(report.portfolioVolatility * 100).toStringAsFixed(0)}%',
                  hint: 'per year',
                  emphasis: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (report.strongest != null)
            _PairLine(
              label: 'Move together most',
              pair: report.strongest!,
              warn: report.strongest!.value > 0.8,
            ),
          if (report.weakest != null)
            _PairLine(
              label: 'Most independent',
              pair: report.weakest!,
              warn: false,
            ),
          const SizedBox(height: 10),
          Text(
            _verdict(report),
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 10, height: 1.45),
          ),
          if (!report.isReliable) ...[
            const SizedBox(height: 6),
            Text(
              'Measured over ${report.observations} days — indicative.',
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 10),
            ),
          ],
        ],
        if (result.sectors.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 12),
          const Text('Sector exposure',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text(
            'A coin sits in several sectors, so these overlap and do not total '
            '100%.',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
          ),
          const SizedBox(height: 10),
          for (final sector in result.sectors.take(5))
            _SectorBar(sector: sector),
        ],
      ],
    );
  }

  /// States what the numbers mean, without telling anyone what to do about it.
  static String _verdict(DiversificationReport report) {
    if (report.benefit < 0.15) {
      return 'These holdings move almost as one: spreading across them removes '
          'very little of the swing a single position would have had.';
    }
    if (report.benefit < 0.35) {
      return 'The spread offsets some movement, but the holdings still largely '
          'rise and fall together.';
    }
    return 'The holdings move independently enough that the mix meaningfully '
        'damps the swings.';
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final bool emphasis;

  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    required this.emphasis,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: emphasis ? AppTheme.loss : AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(hint,
            style:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
      ],
    );
  }
}

class _PairLine extends StatelessWidget {
  final String label;
  final CorrelationPair pair;
  final bool warn;

  const _PairLine({
    required this.label,
    required this.pair,
    required this.warn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 11)),
          const Spacer(),
          Text('${pair.a} · ${pair.b}',
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text(
            pair.value.toStringAsFixed(2),
            style: TextStyle(
              color: warn ? AppTheme.loss : AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorBar extends StatelessWidget {
  final SectorWeight sector;

  const _SectorBar({required this.sector});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sector.sector,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(sector.weight * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: sector.weight > 0.6
                      ? AppTheme.loss
                      : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: sector.weight.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(
                sector.weight > 0.6 ? AppTheme.loss : AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sector.symbols.join(', '),
            style:
                const TextStyle(color: AppTheme.textTertiary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
