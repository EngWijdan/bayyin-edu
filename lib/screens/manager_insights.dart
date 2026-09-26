import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';

/// Read-only school overview for the manager. No student roster and no ranking.
class ManagerInsightsPage extends StatefulWidget {
  const ManagerInsightsPage({
    super.key,
    required this.gateway,
    required this.token,
  });

  final BayyinGateway gateway;
  final String token;

  @override
  State<ManagerInsightsPage> createState() => _ManagerInsightsPageState();
}

class _ManagerInsightsPageState extends State<ManagerInsightsPage> {
  late Future<ManagerInsightsRecord> _insights;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _insights = widget.gateway.fetchManagerInsights(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.schoolInsights)),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _insights.catchError((_) => _empty);
        },
        child: FutureBuilder<ManagerInsightsRecord>(
          future: _insights,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return LoadingState(message: strings.loading);
            }
            if (snapshot.hasError) {
              return ErrorRetryState(
                message: strings.describeError(snapshot.error),
                retryLabel: strings.retry,
                onRetry: () => setState(_reload),
              );
            }
            final insights = snapshot.data ?? _empty;
            return ResponsivePage(
              children: [
                _SectionTitle(strings.overview),
                _SummaryGrid(summary: insights.summary),
                const SizedBox(height: 20),
                _SectionTitle(strings.classrooms),
                if (insights.classrooms.isEmpty)
                  EmptyState(
                    icon: Icons.class_rounded,
                    message: strings.notEnoughDataYet,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final row in insights.classrooms)
                        _ClassroomCard(row: row),
                    ],
                  ),
                const SizedBox(height: 12),
                _SectionTitle(strings.teachers),
                if (insights.teachers.isEmpty)
                  EmptyState(
                    icon: Icons.people_rounded,
                    message: strings.notEnoughDataYet,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final row in insights.teachers) _TeacherCard(row: row),
                    ],
                  ),
                const SizedBox(height: 12),
                _SectionTitle(strings.assessments),
                if (insights.assessments.isEmpty)
                  EmptyState(
                    icon: Icons.assignment_rounded,
                    message: strings.notEnoughDataYet,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final row in insights.assessments)
                        _AssessmentCard(row: row),
                    ],
                  ),
                const SizedBox(height: 12),
                _SectionTitle(strings.highestGaps),
                if (insights.highestGapQuestions.isEmpty)
                  EmptyState(
                    icon: Icons.insights_rounded,
                    message: strings.notEnoughDataYet,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final gap in insights.highestGapQuestions)
                        _GapCard(gap: gap),
                    ],
                  ),
                const SizedBox(height: 12),
                _SectionTitle(strings.commonMisconceptions),
                if (insights.misconceptions.isEmpty)
                  EmptyState(
                    icon: Icons.lightbulb_outline_rounded,
                    message: strings.noMisconceptions,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final item in insights.misconceptions)
                        Card(
                          child: ListTile(
                            title: Text(item.text),
                            trailing: Text(
                              strings.misconceptionOccurrences(item.count),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _empty = ManagerInsightsRecord(
  summary: ManagerInsightsSummary(
    totalTeachers: 0,
    totalClassrooms: 0,
    totalStudents: 0,
    totalAssessments: 0,
    assessmentsWithCompleteResults: 0,
    assessmentsWithIncompleteResults: 0,
  ),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ManagerInsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveGrid(
          maxColumns: 4,
          minTileWidth: 160,
          spacing: 8,
          children: [
            _StatChip(
              label: strings.teachers,
              value: '${summary.totalTeachers}',
            ),
            _StatChip(
              label: strings.classrooms,
              value: '${summary.totalClassrooms}',
            ),
            _StatChip(
              label: strings.students,
              value: '${summary.totalStudents}',
            ),
            _StatChip(
              label: strings.assessments,
              value: '${summary.totalAssessments}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.overallAveragePercentage == null)
                  Text(
                    strings.notEnoughDataYet,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )
                else
                  Text(
                    strings.averagePerformanceValue(
                      summary.overallAveragePercentage!,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  strings.completeResultsCount(
                    summary.assessmentsWithCompleteResults,
                  ),
                ),
                Text(
                  strings.incompleteResultsCount(
                    summary.assessmentsWithIncompleteResults,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassroomCard extends StatelessWidget {
  const _ClassroomCard({required this.row});

  final ManagerClassroomInsight row;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        title: Text(row.classroomName),
        subtitle: Text(
          '${row.teacherName}\n'
          '${strings.countWithLabel(strings.students, row.studentCount)}  •  '
          '${strings.countWithLabel(strings.assessments, row.assessmentCount)}\n'
          '${strings.completeResultsCount(row.completedResultsCount)}  •  '
          '${strings.incompleteResultsCount(row.incompleteResultsCount)}',
        ),
        trailing: _CompactMetric(
          text: row.averagePercentage == null
              ? strings.notEnoughDataYet
              : strings.studentPercentage(row.averagePercentage!),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.row});

  final ManagerTeacherInsight row;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        title: Text(row.displayName),
        subtitle: Text(
          '${strings.countWithLabel(strings.classrooms, row.classroomsCount)}  •  '
          '${strings.countWithLabel(strings.students, row.studentsCount)}\n'
          '${strings.countWithLabel(strings.assessments, row.assessmentsCount)}',
        ),
        trailing: _CompactMetric(
          text: row.averagePercentage == null
              ? strings.notEnoughDataYet
              : strings.studentPercentage(row.averagePercentage!),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.row});

  final ManagerAssessmentInsight row;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        title: Text(row.title),
        subtitle: Text(
          '${row.classroom}  •  ${row.teacher}\n'
          '${strings.completeResultsCount(row.completeResults)}  •  '
          '${strings.incompleteResultsCount(row.incompleteResults)}',
        ),
        trailing: _CompactMetric(
          text: row.averagePercentage == null
              ? strings.notEnoughDataYet
              : strings.studentPercentage(row.averagePercentage!),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.gap});

  final ManagerGapInsight gap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final text = gap.questionText.trim();
    final short = text.length <= 72 ? text : '${text.substring(0, 72)}…';
    return Card(
      child: ListTile(
        title: Text(
          strings.questionGapHeadline(gap.questionOrder, gap.gapPercentage),
        ),
        subtitle: Text('$short\n${gap.assessmentTitle}  •  ${gap.classroom}'),
        isThreeLine: true,
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, textAlign: TextAlign.end),
    );
  }
}
