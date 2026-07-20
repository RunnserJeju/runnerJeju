import 'package:flutter/material.dart';

/// 거리/시간/페이스 같은 러닝 지표 한 칸.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.emphasized = false,
    this.alignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final String? unit;

  /// true면 값을 크게 표시한다. 러닝 중 화면의 메인 지표용.
  final bool emphasized;

  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: emphasized ? 56 : 24,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: emphasized ? 16 : 12,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
