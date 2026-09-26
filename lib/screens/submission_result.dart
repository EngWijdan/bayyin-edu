import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/evaluation_tone.dart';
import '../widgets/responsive.dart';

/// Dedicated result page: score first, then a colored breakdown per question.
class SubmissionResultPage extends StatelessWidget {
  const SubmissionResultPage({
    super.key,
    required this.studentName,
    required this.studentCode,
    required this.assessmentTitle,
    required this.answers,
    required this.result,
  });

  final String studentName;
  final String studentCode;
  final String assessmentTitle;
  final List<AnswerRecord> answers;
  final SubmissionResultRecord result;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.assessmentResult,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            if (assessmentTitle.trim().isNotEmpty)
              Text(
                assessmentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
      body: ResponsivePage(
        children: [
          _StudentHeader(name: studentName, code: studentCode),
          const SizedBox(height: 16),
          ResultScoreCard(result: result),
          const SizedBox(height: 16),
          ResultStatusCounts(result: result),
          if (result.canEvaluate && !result.isComplete) ...[
            const SizedBox(height: 12),
            ResultNotice(
              tone: EvaluationTone.pending,
              body: strings.resultIncompleteWarning,
            ),
          ],
          if (!result.canEvaluate) ...[
            const SizedBox(height: 12),
            ResultNotice(
              tone: EvaluationTone.incorrect,
              body: strings.resultNotEvaluableWarning,
            ),
          ],
          if (result.misconceptions.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeading(
              icon: Icons.auto_awesome_rounded,
              title: strings.misconceptions,
              tone: EvaluationTone.partial,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in result.misconceptions)
                  StatusChip(
                    label: '• $item',
                    tone: EvaluationTone.partial,
                  ),
              ],
            ),
          ],
          if (result.gaps.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeading(
              icon: Icons.flag_rounded,
              title: strings.gaps,
              tone: EvaluationTone.incorrect,
            ),
            const SizedBox(height: 10),
            ResponsiveGrid(
              children: [for (final gap in result.gaps) _GapCard(gap: gap)],
            ),
          ],
          const SizedBox(height: 16),
          _SectionHeading(
            icon: Icons.quiz_rounded,
            title: strings.questionDetails,
            tone: EvaluationTone.pending,
          ),
          const SizedBox(height: 4),
          Text(
            strings.questionsEvaluated(
              result.evaluatedQuestions,
              result.totalQuestions,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ResponsiveGrid(
            children: [
              for (final answer in answers) _QuestionResultCard(answer: answer),
            ],
          ),
        ],
      ),
    );
  }
}

class ResultScoreCard extends StatelessWidget {
  const ResultScoreCard({super.key, required this.result});

  final SubmissionResultRecord result;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final tone = result.canEvaluate
        ? EvaluationTone.forPercentage(result.percentage)
        : EvaluationTone.pending;
    return Card(
      color: tone.background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 104,
                    height: 104,
                    child: CircularProgressIndicator(
                      value: result.canEvaluate
                          ? (result.percentage / 100).clamp(0.0, 1.0)
                          : 0,
                      strokeWidth: 9,
                      color: tone.color,
                      backgroundColor: tone.color.withValues(alpha: 0.15),
                    ),
                  ),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.studentPercentage(result.percentage),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: tone.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.canEvaluate
                        ? (result.isComplete
                              ? strings.resultComplete
                              : strings.resultIncomplete)
                        : strings.resultNotEvaluable,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: result.isComplete
                          ? EvaluationTone.correct.color
                          : (result.canEvaluate
                                ? EvaluationTone.partial.color
                                : EvaluationTone.incorrect.color),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.awardedScoreValue(
                      result.awardedScoreTotal,
                      result.maxScoreTotal,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(strings.percentageValue(result.percentage)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultStatusCounts extends StatelessWidget {
  const ResultStatusCounts({super.key, required this.result});

  final SubmissionResultRecord result;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (!result.canEvaluate) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusChip(
          label: strings.evaluationStatus('correct'),
          tone: EvaluationTone.correct,
          count: result.correctCount,
        ),
        StatusChip(
          label: strings.evaluationStatus('partial'),
          tone: EvaluationTone.partial,
          count: result.partialCount,
        ),
        StatusChip(
          label: strings.evaluationStatus('incorrect'),
          tone: EvaluationTone.incorrect,
          count: result.incorrectCount,
        ),
        StatusChip(
          label: strings.unevaluated,
          tone: EvaluationTone.pending,
          count: result.unevaluatedCount,
        ),
      ],
    );
  }
}

class ResultNotice extends StatelessWidget {
  const ResultNotice({
    super.key,
    required this.tone,
    required this.body,
    this.title,
  });

  final EvaluationTone tone;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: tone.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: tone.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentHeader extends StatelessWidget {
  const _StudentHeader({required this.name, required this.code});

  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final displayName = name.trim().isEmpty ? strings.unnamedStudent : name;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(_initial(displayName, code)),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(code),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final EvaluationTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: tone.color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.gap});

  final GapRecord gap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final tone = EvaluationTone.of(gap.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.questionPosition(gap.questionOrder),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              StatusChip(
                label: strings.evaluationStatus(gap.status),
                tone: tone,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.awardedScoreValue(gap.awardedScore, gap.maxScore),
            style: TextStyle(fontWeight: FontWeight.w700, color: tone.color),
          ),
          const SizedBox(height: 6),
          Text(strings.evaluationFeedback(gap.feedback)),
          if (gap.hasMisconception) ...[
            const SizedBox(height: 6),
            Text(gap.misconception),
          ],
        ],
      ),
    );
  }
}

class _QuestionResultCard extends StatelessWidget {
  const _QuestionResultCard({required this.answer});

  final AnswerRecord answer;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final evaluation = answer.evaluation;
    final tone = EvaluationTone.of(evaluation?.status);
    final statusLabel = evaluation == null
        ? strings.unevaluated
        : strings.evaluationStatus(evaluation.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: tone.color),
            Expanded(
              child: ColoredBox(
                color: tone.background.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.questionPosition(answer.order),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          StatusChip(label: statusLabel, tone: tone),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _LabeledBlock(
                        label: strings.questionText,
                        value: answer.text,
                      ),
                      const SizedBox(height: 10),
                      _LabeledBlock(
                        label: strings.studentAnswer,
                        value: answer.answerText.trim().isEmpty
                            ? strings.noAnswerDetected
                            : answer.answerText,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        strings.awardedScoreValue(
                          evaluation?.awardedScore ?? 0,
                          answer.maxScore,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: tone.color,
                        ),
                      ),
                      if (evaluation != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          strings.feedback,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(strings.evaluationFeedback(evaluation.feedback)),
                        if (evaluation.hasMisconception) ...[
                          const SizedBox(height: 8),
                          Text(
                            strings.misconception,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: EvaluationTone.partial.color,
                            ),
                          ),
                          Text(evaluation.misconception),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value),
      ],
    );
  }
}

String _initial(String name, String code) {
  final source = name.trim().isNotEmpty ? name.trim() : code.trim();
  if (source.isEmpty) return '?';
  return String.fromCharCode(source.runes.first);
}
