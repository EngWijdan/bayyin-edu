import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Semantic colors for evaluation outcomes. Kept off the theme seed so
/// correct / partial / incorrect stay readable in both locales.
class EvaluationTone {
  const EvaluationTone({
    required this.color,
    required this.background,
    required this.icon,
  });

  final Color color;
  final Color background;
  final IconData icon;

  static const correct = EvaluationTone(
    color: AppColors.success,
    background: AppColors.successSoft,
    icon: Icons.check_circle_rounded,
  );
  static const partial = EvaluationTone(
    color: AppColors.warning,
    background: AppColors.warningSoft,
    icon: Icons.change_circle_rounded,
  );
  static const incorrect = EvaluationTone(
    color: AppColors.danger,
    background: AppColors.dangerSoft,
    icon: Icons.cancel_rounded,
  );
  static const pending = EvaluationTone(
    color: AppColors.pending,
    background: AppColors.pendingSoft,
    icon: Icons.hourglass_empty_rounded,
  );

  static EvaluationTone of(String? status) => switch (status) {
    'correct' => correct,
    'partial' => partial,
    'incorrect' => incorrect,
    _ => pending,
  };

  static EvaluationTone forPercentage(double percentage) {
    if (percentage >= 80) return correct;
    if (percentage >= 50) return partial;
    return incorrect;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.count,
  });

  final String label;
  final EvaluationTone tone;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tone.icon, size: 16, color: tone.color),
          const SizedBox(width: 6),
          Text(
            count == null ? label : '$label: $count',
            style: TextStyle(
              color: tone.color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
