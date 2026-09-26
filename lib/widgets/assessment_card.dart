import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../theme/app_colors.dart';
import '../widgets/branding.dart';

class SwipeableAssessmentCard extends StatelessWidget {
  const SwipeableAssessmentCard({
    super.key,
    required this.assessment,
    required this.onTap,
    required this.onSwipeAway,
    required this.confirmDelete,
    this.trailing,
    this.showCreatedDate = false,
  });

  final AssessmentRecord assessment;
  final VoidCallback onTap;
  final Future<void> Function(DismissDirection direction) onSwipeAway;
  final Future<bool> Function() confirmDelete;
  final Widget? trailing;
  final bool showCreatedDate;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final scheme = Theme.of(context).colorScheme;
    final archived = assessment.isArchived;
    return Dismissible(
      key: ValueKey('assessment-${assessment.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          return confirmDelete();
        }
        return true;
      },
      onDismissed: (direction) => onSwipeAway(direction),
      background: _SwipeBanner(
        alignment: AlignmentDirectional.centerStart,
        icon: archived ? Icons.unarchive_rounded : Icons.archive_rounded,
        label: archived ? strings.restoreAssessment : strings.archiveAssessment,
        background: archived
            ? AppColors.successSoft
            : AppColors.warningSoft,
        foreground: archived ? AppColors.success : AppColors.warning,
      ),
      secondaryBackground: _SwipeBanner(
        alignment: AlignmentDirectional.centerEnd,
        icon: Icons.delete_outline_rounded,
        label: strings.deleteAssessment,
        background: scheme.errorContainer,
        foreground: scheme.error,
      ),
      child: AssessmentCard(
        assessment: assessment,
        onTap: onTap,
        trailing: trailing,
        showCreatedDate: showCreatedDate,
      ),
    );
  }
}

class AssessmentCard extends StatelessWidget {
  const AssessmentCard({
    super.key,
    required this.assessment,
    required this.onTap,
    this.trailing,
    this.showCreatedDate = false,
  });

  final AssessmentRecord assessment;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showCreatedDate;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final created = assessment.createdAt;
    final dateLabel = created == null
        ? null
        : strings.createdOn(
            MaterialLocalizations.of(
              context,
            ).formatMediumDate(created.toLocal()),
          );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              BrandIconBox(
                icon: assessment.isArchived
                    ? Icons.inventory_2_rounded
                    : Icons.assignment_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assessment.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.assessmentMeta(
                        assessment.classroomName,
                        assessment.subject,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (assessment.grade.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        assessment.grade,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaChip(
                          text: strings.questionsLabel(
                            assessment.questionsCount,
                          ),
                        ),
                        _MetaChip(
                          text: strings.totalScoreValue(assessment.totalScore),
                        ),
                      ],
                    ),
                    if (showCreatedDate && dateLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dateLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SwipeBanner extends StatelessWidget {
  const _SwipeBanner({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final AlignmentGeometry alignment;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
