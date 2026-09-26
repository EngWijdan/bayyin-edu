import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../theme/app_colors.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';
import 'remediation_plan.dart';

/// Class-level summary, gaps, misconceptions, grouping, and remediation.
class ClassInsightsPage extends StatefulWidget {
  const ClassInsightsPage({
    super.key,
    required this.gateway,
    required this.token,
    required this.assessment,
  });

  final BayyinGateway gateway;
  final String token;
  final AssessmentRecord assessment;

  @override
  State<ClassInsightsPage> createState() => _ClassInsightsPageState();
}

class _ClassInsightsPageState extends State<ClassInsightsPage> {
  ClassInsightsRecord? _insights;
  List<RemediationPlanRecord> _plans = const [];
  Object? _error;
  bool _loading = true;
  String? _busyGroup;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final insights = await widget.gateway.fetchClassInsights(
        token: widget.token,
        assessmentId: widget.assessment.id,
      );
      final plans = await widget.gateway.fetchRemediationPlans(
        token: widget.token,
        assessmentId: widget.assessment.id,
      );
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _plans = plans;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  RemediationPlanRecord? _planFor(String group) {
    for (final plan in _plans) {
      if (plan.group == group) return plan;
    }
    return null;
  }

  void _upsert(RemediationPlanRecord plan) {
    setState(() {
      _plans = [
        for (final existing in _plans)
          if (existing.group != plan.group) existing,
        plan,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.classInsights)),
      body: RefreshIndicator(onRefresh: _reload, child: _body(strings)),
    );
  }

  Widget _body(AppStrings strings) {
    if (_loading && _insights == null) {
      return LoadingState(message: strings.loading);
    }
    if (_error != null && _insights == null) {
      return ErrorRetryState(
        message: strings.describeError(_error),
        retryLabel: strings.retry,
        onRetry: _reload,
      );
    }
    final insights = _insights ?? _emptyInsights;
    return ResponsivePage(
      children: [
        _SummaryCard(summary: insights.summary),
        const SizedBox(height: 20),
        _SectionTitle(strings.highestGapQuestions),
        if (insights.questionGaps.isEmpty)
          EmptyState(icon: Icons.help_outline_rounded, message: strings.noQuestions)
        else
          ResponsiveGrid(
            children: [
              for (final gap in insights.questionGaps) _GapTile(gap: gap),
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
        const SizedBox(height: 12),
        ResponsiveGrid(
          maxColumns: 3,
          minTileWidth: 280,
          children: [
            _GroupSection(
              title: strings.foundationGroup,
              students: insights.foundation,
            ),
            _GroupSection(
              title: strings.practiceGroup,
              students: insights.practice,
            ),
            _GroupSection(title: strings.readyGroup, students: insights.ready),
          ],
        ),
        const SizedBox(height: 8),
        _SectionTitle(strings.remediationPlan),
        ResponsiveGrid(
          maxColumns: 3,
          minTileWidth: 280,
          children: [
            _RemediationCard(
              title: strings.foundationGroup,
              empty: insights.foundation.isEmpty,
              plan: _planFor('foundation'),
              busy: _busyGroup == 'foundation',
              onGenerate: () => _generate('foundation'),
              onView: () => _openPlan(_planFor('foundation')),
            ),
            _RemediationCard(
              title: strings.practiceGroup,
              empty: insights.practice.isEmpty,
              plan: _planFor('practice'),
              busy: _busyGroup == 'practice',
              onGenerate: () => _generate('practice'),
              onView: () => _openPlan(_planFor('practice')),
            ),
            _RemediationCard(
              title: strings.readyGroup,
              empty: insights.ready.isEmpty,
              plan: _planFor('ready'),
              busy: _busyGroup == 'ready',
              onGenerate: () => _generate('ready'),
              onView: () => _openPlan(_planFor('ready')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (insights.pendingStudents.isNotEmpty) ...[
          _SectionTitle(strings.pendingEvaluation),
          ResponsiveGrid(
            children: [
              for (final student in insights.pendingStudents)
                Card(
                  child: ListTile(
                    title: Text(
                      student.hasName
                          ? student.displayName
                          : strings.unnamedStudent,
                    ),
                    subtitle: Text(
                      '${student.studentCode}\n'
                      '${strings.pendingReason(student.reason)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _generate(String group) async {
    setState(() => _busyGroup = group);
    try {
      final result = await widget.gateway.generateRemediationPlan(
        token: widget.token,
        assessmentId: widget.assessment.id,
        group: group,
        locale: context.strings.evaluationLocale,
      );
      if (!mounted) return;
      setState(() => _busyGroup = null);
      final plan = result.plan;
      if (result.groupEmpty || plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.noStudentsInGroup)),
        );
        return;
      }
      _upsert(plan);
      await _openPlan(plan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyGroup = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.describeError(error))),
      );
    }
  }

  Future<void> _openPlan(RemediationPlanRecord? plan) async {
    if (plan == null) return;
    final updated = await Navigator.of(context).push<RemediationPlanRecord>(
      MaterialPageRoute(
        builder: (_) => RemediationPlanPage(
          gateway: widget.gateway,
          token: widget.token,
          assessmentId: widget.assessment.id,
          plan: plan,
        ),
      ),
    );
    if (updated != null && mounted) _upsert(updated);
  }
}

const _emptyInsights = ClassInsightsRecord(
  summary: ClassInsightsSummary(
    totalStudentsInClass: 0,
    studentsWithSubmission: 0,
    studentsWithoutSubmission: 0,
    completeResults: 0,
    incompleteResults: 0,
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ClassInsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.averagePercentage == null)
              Text(
                strings.noCompleteResultsYet,
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            else
              Text(
                strings.classAverageValue(summary.averagePercentage!),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            const SizedBox(height: 8),
            Text(strings.completeResultsCount(summary.completeResults)),
            Text(strings.incompleteResultsCount(summary.incompleteResults)),
            Text(strings.noSubmissionCount(summary.studentsWithoutSubmission)),
          ],
        ),
      ),
    );
  }
}

class _GapTile extends StatelessWidget {
  const _GapTile({required this.gap});

  final ClassQuestionGapRecord gap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final text = gap.questionText.trim();
    final short = text.length <= 72 ? text : '${text.substring(0, 72)}…';
    return Card(
      child: ListTile(
        title: Text(
          strings.questionGapHeadline(gap.questionOrder, gap.gapPercentage),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$short\n'
          '${strings.gapStatusCounts(correct: gap.correctCount, partial: gap.partialCount, incorrect: gap.incorrectCount)}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.title, required this.students});

  final String title;
  final List<GroupedStudentRecord> students;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          if (students.isEmpty)
            const SizedBox.shrink()
          else
            ...students.map(
              (student) => Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(
                      student.hasName
                          ? student.displayName
                          : strings.unnamedStudent,
                    ),
                    subtitle: Text(student.studentCode),
                    trailing: Text(
                      strings.studentPercentage(student.percentage),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RemediationCard extends StatelessWidget {
  const _RemediationCard({
    required this.title,
    required this.empty,
    required this.plan,
    required this.busy,
    required this.onGenerate,
    required this.onView,
  });

  final String title;
  final bool empty;
  final RemediationPlanRecord? plan;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppColors.primarySoft,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (empty)
                Text(strings.noStudentsInGroup)
              else if (busy)
                Text(strings.generatingPlan)
              else if (plan == null)
                FilledButton.tonal(
                  onPressed: onGenerate,
                  child: Text(strings.generatePlan),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: onView,
                      child: Text(strings.viewPlan),
                    ),
                    OutlinedButton(
                      onPressed: onGenerate,
                      child: Text(strings.regeneratePlan),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
