import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/async_states.dart';
import '../widgets/branding.dart';
import '../widgets/responsive.dart';
import 'assessment_submissions.dart';
import 'class_insights.dart';
import 'exam_question_review.dart';

/// One assessment and its questions. The list handed over by the previous
/// screen is only a summary, so the questions are fetched here.
class AssessmentDetailsPage extends StatefulWidget {
  const AssessmentDetailsPage({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
    required this.assessment,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final AssessmentRecord assessment;

  @override
  State<AssessmentDetailsPage> createState() => _AssessmentDetailsPageState();
}

class _AssessmentDetailsPageState extends State<AssessmentDetailsPage> {
  late Future<AssessmentRecord> _details;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _details = widget.gateway.fetchAssessment(
      token: widget.token,
      assessmentId: widget.assessment.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.assessment.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            Text(
              strings.assessmentMeta(
                widget.assessment.classroomName,
                widget.assessment.subject,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _details.catchError((_) => widget.assessment);
        },
        child: FutureBuilder<AssessmentRecord>(
          future: _details,
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
            final assessment = snapshot.data ?? widget.assessment;
            final hasQuestions = assessment.questions.isNotEmpty;
            return ResponsiveScroll(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OverviewCard(
                    assessment: assessment,
                    activeStep: hasQuestions ? 2 : 1,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _NextActions(
                    hasQuestions: hasQuestions,
                    busy: _busy,
                    onUpload: _uploadExamPaper,
                    onStudents: _openSubmissions,
                    onAddQuestion: _addQuestion,
                    onInsights: _openClassInsights,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _QuestionsHeader(
                    count: assessment.questions.length,
                    totalScore: assessment.totalScore,
                    busy: _busy,
                    onDeleteAll: hasQuestions ? _deleteAllQuestions : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!hasQuestions)
                    const _QuestionsEmpty()
                  else
                    ...assessment.questions.map(
                      (question) => Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: AppSpacing.sm,
                        ),
                        child: _QuestionTile(
                          question: question,
                          busy: _busy,
                          onDelete: () => _deleteQuestion(question),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openClassInsights() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassInsightsPage(
          gateway: widget.gateway,
          token: widget.token,
          assessment: widget.assessment,
        ),
      ),
    );
  }

  void _openSubmissions() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentSubmissionsPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
          assessment: widget.assessment,
        ),
      ),
    );
  }

  Future<void> _addQuestion() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => _AddQuestionDialog(
        gateway: widget.gateway,
        token: widget.token,
        assessmentId: widget.assessment.id,
      ),
    );
    if (added != true || !mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.strings.questionAdded)));
  }

  Future<void> _uploadExamPaper() async {
    final confirmed = await startExamPaperExtraction(
      context: context,
      gateway: widget.gateway,
      picker: widget.picker,
      token: widget.token,
      assessmentId: widget.assessment.id,
    );
    if (confirmed != true || !mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.questionsConfirmed)));
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(title),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteQuestion(QuestionRecord question) async {
    final strings = context.strings;
    final confirmed = await _confirmDelete(
      strings.removeQuestion,
      strings.deleteQuestionConfirm,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.deleteQuestion(
        token: widget.token,
        assessmentId: widget.assessment.id,
        questionId: question.id,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.questionDeleted)));
    } catch (exception) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.describeError(exception))));
    }
  }

  Future<void> _deleteAllQuestions() async {
    final strings = context.strings;
    final snapshot = await _details.catchError((_) => widget.assessment);
    final questions = snapshot.questions;
    if (questions.isEmpty) return;
    final confirmed = await _confirmDelete(
      strings.deleteQuestions,
      strings.deleteQuestionsConfirm,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final question in questions) {
        await widget.gateway.deleteQuestion(
          token: widget.token,
          assessmentId: widget.assessment.id,
          questionId: question.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.questionsDeleted)));
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.describeError(exception))));
    }
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.assessment, required this.activeStep});

  final AssessmentRecord assessment;
  final int activeStep;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.softMint, AppColors.verySoftGreen],
        ),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.school_rounded,
                label: assessment.classroomName,
              ),
              if (assessment.grade.isNotEmpty)
                _MetaChip(
                  icon: Icons.layers_rounded,
                  label: assessment.grade,
                ),
              _MetaChip(
                icon: Icons.menu_book_rounded,
                label: assessment.subject,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            strings.teacherWorkflow,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.teacherWorkflowHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primaryDark.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AssessmentWorkflow(activeStep: activeStep),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.quiz_rounded,
                  value: '${assessment.questions.length}',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _StatTile(
                  icon: Icons.star_rounded,
                  value: strings.totalScoreValue(assessment.totalScore),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: AppRadius.input,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentWorkflow extends StatelessWidget {
  const _AssessmentWorkflow({required this.activeStep});

  final int activeStep;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final steps = [
      strings.flowExamSetup,
      strings.flowStudentWork,
      strings.flowInsightsStep,
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: activeStep > i
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: _WorkflowStep(
              number: i + 1,
              label: steps[i],
              active: activeStep == i + 1,
              done: activeStep > i + 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
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
    final color = active || done ? AppColors.primary : AppColors.mutedSage;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : done
                ? Colors.white
                : Colors.white.withValues(alpha: 0.7),
            border: Border.all(
              color: active || done ? AppColors.primary : AppColors.border,
              width: active ? 0 : 1.5,
            ),
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: done && !active
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.primary,
                )
              : Text(
                  '$number',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: active ? Colors.white : color,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: color,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _NextActions extends StatelessWidget {
  const _NextActions({
    required this.hasQuestions,
    required this.busy,
    required this.onUpload,
    required this.onStudents,
    required this.onAddQuestion,
    required this.onInsights,
  });

  final bool hasQuestions;
  final bool busy;
  final VoidCallback onUpload;
  final VoidCallback onStudents;
  final VoidCallback onAddQuestion;
  final VoidCallback onInsights;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final primary = hasQuestions
        ? (
            icon: Icons.people_alt_rounded,
            label: strings.studentSubmissions,
            hint: strings.submissionsActionHint,
            onTap: onStudents,
          )
        : (
            icon: Icons.upload_file_rounded,
            label: strings.uploadExamPaper,
            hint: strings.uploadExamPaperHint,
            onTap: busy ? null : onUpload,
          );
    final secondary = hasQuestions
        ? [
            (
              icon: Icons.upload_file_rounded,
              label: strings.uploadExamPaper,
              onTap: busy ? null : onUpload,
            ),
            (
              icon: Icons.add_rounded,
              label: strings.addQuestion,
              onTap: busy ? null : onAddQuestion,
            ),
            (
              icon: Icons.insights_rounded,
              label: strings.classInsights,
              onTap: onInsights,
            ),
          ]
        : [
            (
              icon: Icons.add_rounded,
              label: strings.addQuestion,
              onTap: busy ? null : onAddQuestion,
            ),
            (
              icon: Icons.people_alt_rounded,
              label: strings.studentSubmissions,
              onTap: onStudents,
            ),
            (
              icon: Icons.insights_rounded,
              label: strings.classInsights,
              onTap: onInsights,
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasQuestions ? strings.nextStep : strings.startHere,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _PrimaryActionCard(
          icon: primary.icon,
          label: primary.label,
          hint: primary.hint,
          onTap: primary.onTap,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                children: [
                  for (var i = 0; i < secondary.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.xs),
                    _SecondaryActionCard(
                      icon: secondary[i].icon,
                      label: secondary[i].label,
                      onTap: secondary[i].onTap,
                    ),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < secondary.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _SecondaryActionCard(
                      icon: secondary[i].icon,
                      label: secondary[i].label,
                      onTap: secondary[i].onTap,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: AppRadius.chip,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                trailingChevronOf(context),
                size: 16,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionCard extends StatelessWidget {
  const _SecondaryActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              BrandIconBox(icon: icon, size: 36, iconSize: 18),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionsHeader extends StatelessWidget {
  const _QuestionsHeader({
    required this.count,
    required this.totalScore,
    required this.busy,
    required this.onDeleteAll,
  });

  final int count;
  final double totalScore;
  final bool busy;
  final VoidCallback? onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 4, height: 28, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    strings.questions,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softMint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${strings.questionsLabel(count)} • '
                '${strings.totalScoreValue(totalScore)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (onDeleteAll != null)
          PopupMenuButton<String>(
            tooltip: strings.questionsMenu,
            enabled: !busy,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
            onSelected: (_) => onDeleteAll!(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'deleteAll',
                child: Text(
                  strings.deleteAllQuestions,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _QuestionsEmpty extends StatelessWidget {
  const _QuestionsEmpty();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const BrandIconBox(
            icon: Icons.document_scanner_rounded,
            size: 52,
            iconSize: 26,
          ),
          const SizedBox(height: 14),
          Text(
            strings.noQuestions,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.noQuestionsHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatefulWidget {
  const _QuestionTile({
    required this.question,
    required this.busy,
    required this.onDelete,
  });

  final QuestionRecord question;
  final bool busy;
  final VoidCallback onDelete;

  @override
  State<_QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<_QuestionTile> {
  bool expanded = false;

  static const _previewLimit = 90;

  bool get _isLong =>
      widget.question.modelAnswer.trim().length > _previewLimit ||
      widget.question.modelAnswer.contains('\n');

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final answer = strings.modelAnswerValue(widget.question.modelAnswer);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: AppColors.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.softMint,
                        borderRadius: AppRadius.chip,
                      ),
                      child: Text(
                        '${widget.question.order}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.question.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.verySoftGreen,
                              borderRadius: AppRadius.chip,
                            ),
                            child: Text(
                              strings.maximumScoreValue(
                                widget.question.maxScore,
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.warmBackground,
                              borderRadius: AppRadius.input,
                            ),
                            child: Text(
                              answer,
                              maxLines: expanded ? null : 2,
                              overflow: expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.mutedText,
                                height: 1.4,
                              ),
                            ),
                          ),
                          if (_isLong)
                            TextButton(
                              onPressed: () =>
                                  setState(() => expanded = !expanded),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                expanded ? strings.showLess : strings.showMore,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings.removeQuestion,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      color: scheme.error.withValues(alpha: 0.72),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: widget.busy ? null : widget.onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddQuestionDialog extends StatefulWidget {
  const _AddQuestionDialog({
    required this.gateway,
    required this.token,
    required this.assessmentId,
  });

  final BayyinGateway gateway;
  final String token;
  final String assessmentId;

  @override
  State<_AddQuestionDialog> createState() => _AddQuestionDialogState();
}

class _AddQuestionDialogState extends State<_AddQuestionDialog> {
  final formKey = GlobalKey<FormState>();
  final text = TextEditingController();
  final maxScore = TextEditingController();
  final modelAnswer = TextEditingController();
  bool saving = false;
  Object? error;

  @override
  void dispose() {
    text.dispose();
    maxScore.dispose();
    modelAnswer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.addQuestion),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: text,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: strings.questionText),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.requiredField
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: maxScore,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: strings.maximumScore),
                  validator: (value) {
                    final score = double.tryParse(value?.trim() ?? '');
                    return score == null || score <= 0
                        ? strings.invalidScore
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: modelAnswer,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: strings.modelAnswer),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.requiredField
                      : null,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.describeError(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: Text(saving ? strings.saving : strings.save),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.gateway.createQuestion(
        token: widget.token,
        assessmentId: widget.assessmentId,
        text: text.text.trim(),
        maxScore: double.parse(maxScore.text.trim()),
        modelAnswer: modelAnswer.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception;
      });
    }
  }
}
