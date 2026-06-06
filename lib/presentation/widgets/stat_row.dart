import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool hasInfo;

  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.hasInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            if (hasInfo) ...[
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, color: AppTheme.textTertiary, size: 12),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
