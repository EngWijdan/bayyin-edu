import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/branding.dart';

class TeacherHomeGreeting extends StatelessWidget {
  const TeacherHomeGreeting({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.welcomeBack,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          strings.greeting(name),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.teacherClassesSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class TeacherHomeOverview extends StatelessWidget {
  const TeacherHomeOverview({super.key, required this.classrooms});

  final List<ClassroomRecord> classrooms;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final studentTotal = classrooms.fold<int>(
      0,
      (sum, classroom) => sum + classroom.studentsCount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TeacherHomeSectionTitle(title: strings.overview),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OverviewTile(
                icon: Icons.school_rounded,
                label: strings.classroomsCount(classrooms.length),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverviewTile(
                icon: Icons.groups_rounded,
                label: strings.studentsLabel(studentTotal),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TeacherHomeActionCard extends StatelessWidget {
  const TeacherHomeActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            children: [
              BrandIconBox(icon: icon, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _chevronOf(context),
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TeacherClassroomCard extends StatelessWidget {
  const TeacherClassroomCard({
    super.key,
    required this.classroom,
    required this.onTap,
  });

  final ClassroomRecord classroom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: scheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Row(
                    children: [
                      const BrandIconBox(icon: Icons.school_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              classroom.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _MetaLine(
                              icon: Icons.menu_book_rounded,
                              text: strings.classroomMeta(
                                classroom.grade,
                                classroom.subject,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _MetaLine(
                              icon: Icons.calendar_today_rounded,
                              text: strings.classroomCounts(
                                classroom.academicYear,
                                classroom.studentsCount,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _chevronOf(context),
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TeacherHomeSectionTitle extends StatelessWidget {
  const TeacherHomeSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            BrandIconBox(icon: icon, size: 32, iconSize: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

IconData _chevronOf(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? Icons.chevron_left
    : Icons.chevron_right;
