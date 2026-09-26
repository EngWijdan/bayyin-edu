import 'package:flutter/material.dart';

import '../l10n/app_language.dart';

/// The three actions a teacher actually takes: original paper, student, then
/// match the student's paper against that original.
class TeacherFlowBanner extends StatelessWidget {
  const TeacherFlowBanner({super.key, required this.activeStep});

  /// 1 = original exam paper, 2 = choose student, 3 = student paper + analyze.
  final int activeStep;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final steps = [
      strings.flowStepOriginalPaper,
      strings.flowStepStudent,
      strings.flowStepAnalyze,
    ];
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.teacherWorkflow,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Divider(
                        color: activeStep > i
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                  _StepDot(
                    number: i + 1,
                    label: steps[i],
                    active: activeStep == i + 1,
                    done: activeStep > i + 1,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.active,
    required this.done,
  });

  final int number;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active || done
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: active || done
                ? theme.colorScheme.primary
                : theme.colorScheme.surface,
            foregroundColor: active || done
                ? theme.colorScheme.onPrimary
                : color,
            child: done
                ? const Icon(Icons.check_rounded, size: 16)
                : Text(
                    '$number',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class TeacherActionCard extends StatelessWidget {
  const TeacherActionCard({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.child,
  });

  final int step;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.strings.flowStepNumber(step),
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
