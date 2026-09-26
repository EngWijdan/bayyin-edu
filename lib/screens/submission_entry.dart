import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/async_states.dart';
import '../widgets/evaluation_tone.dart';
import '../widgets/responsive.dart';
import 'ocr_answer_review.dart';
import 'ocr_text.dart';
import 'submission_result.dart';

/// Manual answer entry for one student's submission. Loads the submission so
/// the form is built from the server's answer sheet rather than from whatever
/// the previous screen happened to hold.
class SubmissionEntryPage extends StatefulWidget {
  const SubmissionEntryPage({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
    required this.assessmentId,
    required this.submissionId,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final String assessmentId;
  final String submissionId;

  @override
  State<SubmissionEntryPage> createState() => _SubmissionEntryPageState();
}

class _SubmissionEntryPageState extends State<SubmissionEntryPage> {
  late Future<SubmissionRecord> _submission;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _submission = widget.gateway.fetchSubmission(
      token: widget.token,
      assessmentId: widget.assessmentId,
      submissionId: widget.submissionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return FutureBuilder<SubmissionRecord>(
      future: _submission,
      builder: (context, snapshot) {
        final submission = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submission?.assessmentTitle ?? strings.loading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.appBarTheme.titleTextStyle?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (submission != null)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          submission.hasName
                              ? submission.studentName
                              : strings.unnamedStudent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.mutedText,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        submission.studentCode,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          body: switch (snapshot) {
            AsyncSnapshot(
              connectionState: ConnectionState.waiting,
              hasData: false,
            ) =>
              LoadingState(message: strings.loading),
            AsyncSnapshot(hasError: true, hasData: false, :final error) =>
              ErrorRetryState(
                message: strings.describeError(error),
                retryLabel: strings.retry,
                onRetry: () => setState(_reload),
              ),
            _ when snapshot.data != null => _AnswerSheet(
              // A fresh form whenever a different submission arrives.
              key: ValueKey(submission!.id),
              gateway: widget.gateway,
              picker: widget.picker,
              token: widget.token,
              assessmentId: widget.assessmentId,
              submission: snapshot.data!,
            ),
            _ => LoadingState(message: strings.loading),
          },
        );
      },
    );
  }
}

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
    required this.assessmentId,
    required this.submission,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final String assessmentId;
  final SubmissionRecord submission;

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  late List<AnswerRecord> _answers = widget.submission.answers;
  late final Map<String, TextEditingController> _controllers = {
    for (final answer in _answers)
      answer.questionId: TextEditingController(text: answer.answerText),
  };
  bool saving = false;
  bool evaluating = false;
  Object? error;
  SubmissionResultRecord? _result;
  Object? _resultError;
  bool _resultLoading = true;

  bool get _hasConfirmedAnswers => _answers.any((answer) => answer.isConfirmed);
  bool get _hasEvaluation =>
      _answers.any((answer) => answer.evaluation != null);
  bool get _busy => saving || evaluating;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final attachments = _AttachmentsSection(
      gateway: widget.gateway,
      picker: widget.picker,
      token: widget.token,
      assessmentId: widget.assessmentId,
      submissionId: widget.submission.id,
      onAnswersConfirmed: _applyConfirmedAnswers,
    );
    final result = _CompactResultSummary(
      result: _result,
      loading: _resultLoading,
      error: _resultError,
      onOpenDetails: _openResult,
    );
    final questions = _answers.isEmpty
        ? EmptyState(
            icon: Icons.help_outline_rounded,
            message: strings.noQuestionsInAssessment,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuestionsHeading(count: _answers.length),
              const SizedBox(height: AppSpacing.sm),
              for (final answer in _answers)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.sm,
                  ),
                  child: _AnswerField(
                    answer: answer,
                    controller: _controllers[answer.questionId]!,
                  ),
                ),
            ],
          );
    return Column(
      children: [
        const _ReviewProgressStrip(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= AppLayout.tablet;
              final body = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              attachments,
                              const SizedBox(height: AppSpacing.md),
                              questions,
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(flex: 2, child: result),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        attachments,
                        const SizedBox(height: AppSpacing.md),
                        result,
                        const SizedBox(height: AppSpacing.md),
                        questions,
                      ],
                    );
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppLayout.pagePaddingOf(constraints.maxWidth),
                child: ResponsiveContent(child: body),
              );
            },
          ),
        ),
        if (_answers.isNotEmpty)
          _StickyAnswerBar(
            error: error,
            saving: saving,
            evaluating: evaluating,
            busy: _busy,
            canEvaluate: _hasConfirmedAnswers,
            hasEvaluation: _hasEvaluation,
            onSave: _save,
            onEvaluate: _evaluate,
          ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final payload = {
        for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
      };
      _debugAnswers('payload before save', payload);
      final updated = await widget.gateway.saveAnswers(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
        answersByQuestionId: payload,
      );
      _debugAnswers('API response after save', {
        for (final answer in updated.answers) answer.questionId: answer.answerText,
      });
      final latest = await widget.gateway.fetchSubmission(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
      );
      _debugAnswers('answer_text after re-fetch', {
        for (final answer in latest.answers) answer.questionId: answer.answerText,
      });
      if (!mounted) return;
      setState(() {
        saving = false;
        _answers = latest.answers;
        _writeControllerTexts(
          {
            for (final answer in latest.answers) answer.questionId: answer.answerText,
          },
          protectLocalNonEmpty: true,
        );
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.strings.answersSaved)));
      await _loadResult();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception;
      });
    }
  }

  Future<void> _evaluate() async {
    setState(() {
      evaluating = true;
      error = null;
    });
    try {
      final updated = await widget.gateway.evaluateAnswers(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
        locale: context.strings.evaluationLocale,
      );
      final result = await widget.gateway.fetchSubmissionResult(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
      );
      if (!mounted) return;
      final failed = updated.failedCount > 0;
      final evaluateError = failed
          ? const ApiException('تعذر تقييم الإجابة.')
          : null;
      setState(() {
        evaluating = false;
        _answers = updated.answers;
        for (final answer in _answers) {
          _controllers[answer.questionId]?.text = answer.answerText;
        }
        _result = result;
        _resultError = null;
        _resultLoading = false;
        error = evaluateError;
      });
      if (failed) {
        _showEvaluateError(evaluateError);
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        evaluating = false;
        error = exception;
      });
      _showEvaluateError(exception);
    }
  }

  void _showEvaluateError(Object? exception) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.describeError(exception))),
    );
  }

  Future<void> _applyConfirmedAnswers(Map<String, String> answers) async {
    setState(() {
      _writeControllerTexts(answers, protectLocalNonEmpty: false);
      _answers = [
        for (final answer in _answers)
          answer.copyWith(
            answerText: answers[answer.questionId] ?? answer.answerText,
          ),
      ];
    });
    _debugAnswers('controllers after OCR confirm', answers);
    await _reloadAnswers();
  }

  Future<void> _reloadAnswers() async {
    try {
      final updated = await widget.gateway.fetchSubmission(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
      );
      _debugAnswers('answer_text after re-fetch', {
        for (final answer in updated.answers) answer.questionId: answer.answerText,
      });
      if (!mounted) return;
      setState(() {
        _answers = updated.answers;
        _writeControllerTexts({
          for (final answer in updated.answers) answer.questionId: answer.answerText,
        }, protectLocalNonEmpty: true);
      });
      await _loadResult();
    } catch (_) {
      // Controllers already hold the confirmed text; a refresh failure must
      // not wipe them before the teacher saves.
    }
  }

  void _writeControllerTexts(
    Map<String, String> answers, {
    required bool protectLocalNonEmpty,
  }) {
    for (final entry in answers.entries) {
      final controller = _controllers.putIfAbsent(
        entry.key,
        TextEditingController.new,
      );
      if (protectLocalNonEmpty &&
          controller.text.trim().isNotEmpty &&
          entry.value.trim().isEmpty) {
        continue;
      }
      controller.text = entry.value;
    }
  }

  void _debugAnswers(String phase, Map<String, String> answers) {
    if (!kDebugMode) return;
    developer.log(
      '$phase ${answers.entries.map((entry) => '${entry.key}=${entry.value}').join(' | ')}',
      name: 'BayyinAnswers',
    );
  }

  void _openResult() {
    final result = _result;
    if (result == null) return;
    final submission = widget.submission;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubmissionResultPage(
          studentName: submission.hasName
              ? submission.studentName
              : '',
          studentCode: submission.studentCode,
          assessmentTitle: submission.assessmentTitle,
          answers: _answers,
          result: result,
        ),
      ),
    );
  }

  Future<void> _loadResult() async {
    try {
      final result = await widget.gateway.fetchSubmissionResult(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _resultError = null;
        _resultLoading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _resultError = exception;
        _resultLoading = false;
      });
    }
  }
}

class _ReviewProgressStrip extends StatelessWidget {
  const _ReviewProgressStrip();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final steps = [
      (label: strings.flowStepOriginalPaper, done: true, active: false),
      (label: strings.flowStepStudent, done: true, active: false),
      (label: strings.flowStepAnalyze, done: false, active: true),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Divider(
                    height: 1,
                    color: steps[i].done || steps[i].active
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : AppColors.border,
                  ),
                ),
              ),
            _MiniStep(
              number: i + 1,
              label: steps[i].label,
              done: steps[i].done,
              active: steps[i].active,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStep extends StatelessWidget {
  const _MiniStep({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done || active ? AppColors.primary : AppColors.mutedText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? AppColors.primary : AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: color),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _QuestionsHeading extends StatelessWidget {
  const _QuestionsHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          strings.questions,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          strings.questionsLabel(count),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.mutedText,
          ),
        ),
      ],
    );
  }
}

class _StickyAnswerBar extends StatelessWidget {
  const _StickyAnswerBar({
    required this.error,
    required this.saving,
    required this.evaluating,
    required this.busy,
    required this.canEvaluate,
    required this.hasEvaluation,
    required this.onSave,
    required this.onEvaluate,
  });

  final Object? error;
  final bool saving;
  final bool evaluating;
  final bool busy;
  final bool canEvaluate;
  final bool hasEvaluation;
  final VoidCallback onSave;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Material(
      color: AppColors.card,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: ResponsiveBar(
            maxWidth: AppLayout.dashboardMaxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  Text(
                    strings.describeError(error),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                _AnswerActions(
                  saving: saving,
                  evaluating: evaluating,
                  busy: busy,
                  canEvaluate: canEvaluate,
                  hasEvaluation: hasEvaluation,
                  onSave: onSave,
                  onEvaluate: onEvaluate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerActions extends StatelessWidget {
  const _AnswerActions({
    required this.saving,
    required this.evaluating,
    required this.busy,
    required this.canEvaluate,
    required this.hasEvaluation,
    required this.onSave,
    required this.onEvaluate,
  });

  final bool saving;
  final bool evaluating;
  final bool busy;
  final bool canEvaluate;
  final bool hasEvaluation;
  final VoidCallback onSave;
  final VoidCallback onEvaluate;

  static final _saveStyle = FilledButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );

  static final _evaluateStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Flexible(
          child: FilledButton.icon(
            onPressed: busy ? null : onSave,
            style: _saveStyle,
            icon: saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(saving ? strings.saving : strings.saveAnswers),
          ),
        ),
        if (canEvaluate) ...[
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onEvaluate,
              style: _evaluateStyle,
              icon: evaluating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      hasEvaluation
                          ? Icons.refresh_rounded
                          : Icons.auto_awesome_rounded,
                      size: 16,
                    ),
              label: Text(
                evaluating
                    ? strings.evaluating
                    : hasEvaluation
                    ? strings.reevaluate
                    : strings.evaluateAnswers,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Rejections we make before an upload is even attempted. Held as a value
/// rather than a message so the text follows a language switch.
enum _LocalFileError { unsupportedType, tooLarge }

/// The photos or PDFs of the student's paper, which may run to several pages.
class _AttachmentsSection extends StatefulWidget {
  const _AttachmentsSection({
    required this.gateway,
    required this.picker,
    required this.token,
    required this.assessmentId,
    required this.submissionId,
    required this.onAnswersConfirmed,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final String assessmentId;
  final String submissionId;
  final Future<void> Function(Map<String, String> answers) onAnswersConfirmed;

  @override
  State<_AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<_AttachmentsSection> {
  List<AttachmentRecord>? _files;
  Object? _loadError;
  final Set<String> _completedOcr = {};
  int _ocrEpoch = 0;

  /// An upload or a delete is in flight.
  bool _busy = false;
  bool _analyzing = false;
  Object? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final files = _files;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  strings.studentPaper,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (files == null && _loadError == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_loadError != null)
              _Message(strings.describeError(_loadError), isError: true)
            else if (files!.isEmpty)
              const _EmptyFilesHint()
            else
              ...files.map(
                (file) => Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.xs,
                  ),
                  child: _AttachmentCard(
                    key: ValueKey('${file.id}-$_ocrEpoch'),
                    file: file,
                    gateway: widget.gateway,
                    token: widget.token,
                    assessmentId: widget.assessmentId,
                    submissionId: widget.submissionId,
                    busy: _busy || _analyzing,
                    onDelete: () => _remove(file),
                    onOcrChanged: (ocr) => _rememberOcr(file.id, ocr),
                  ),
                ),
              ),
            if (_actionError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _Message(_describe(strings, _actionError!), isError: true),
            ],
            const SizedBox(height: AppSpacing.sm),
            _StudentPaperActions(
              addLabel: _busy ? strings.uploading : strings.addFile,
              analyzeLabel: _analyzing
                  ? strings.analyzingPaper
                  : strings.analyzePaper,
              uploading: _busy,
              analyzing: _analyzing,
              onAddFile: _analyzing || _busy ? null : _addFile,
              onAnalyze: _busy || _analyzing ? null : _analyze,
            ),
            if (_completedOcr.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _openReview,
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: Text(strings.reviewExtractedAnswers),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _rememberOcr(String fileId, OcrRecord? ocr) {
    final completed = ocr?.isCompleted == true;
    if (completed == _completedOcr.contains(fileId)) return;
    setState(() {
      if (completed) {
        _completedOcr.add(fileId);
      } else {
        _completedOcr.remove(fileId);
      }
    });
  }

  Future<void> _openReview() async {
    final confirmed = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => OcrAnswerReviewPage(
          gateway: widget.gateway,
          token: widget.token,
          assessmentId: widget.assessmentId,
          submissionId: widget.submissionId,
        ),
      ),
    );
    if (confirmed != null && mounted) {
      await widget.onAnswersConfirmed(confirmed);
      if (mounted) _announce(context.strings.answersConfirmed);
    }
  }

  Future<void> _analyze() async {
    final files = _files;
    if (files == null || files.isEmpty) {
      _announce(context.strings.analyzeNeedsFile);
      return;
    }
    setState(() {
      _analyzing = true;
      _actionError = null;
    });
    try {
      for (final file in files) {
        final result = await widget.gateway.runOcr(
          token: widget.token,
          assessmentId: widget.assessmentId,
          submissionId: widget.submissionId,
          attachmentId: file.id,
        );
        if (!mounted) return;
        _rememberOcr(file.id, result);
      }
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _ocrEpoch++;
      });
      await _openReview();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _actionError = exception;
      });
    }
  }

  String _describe(AppStrings strings, Object error) => switch (error) {
    _LocalFileError.unsupportedType => strings.unsupportedFileType,
    _LocalFileError.tooLarge => strings.fileTooLarge,
    _ => strings.describeError(error),
  };

  Future<void> _load() async {
    try {
      final files = await widget.gateway.fetchAttachments(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
      );
      if (!mounted) return;
      setState(() => _files = files);
    } catch (exception) {
      if (!mounted) return;
      setState(() => _loadError = exception);
    }
  }

  Future<void> _addFile() async {
    final picked = await widget.picker.pick();
    if (picked == null || !mounted) return;
    // A courtesy check so an obviously bad file never leaves the device; the
    // server validates again and has the final say.
    if (!picked.hasSupportedExtension) {
      setState(() => _actionError = _LocalFileError.unsupportedType);
      return;
    }
    if (!picked.isWithinSizeLimit) {
      setState(() => _actionError = _LocalFileError.tooLarge);
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final uploaded = await widget.gateway.uploadAttachment(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
        filename: picked.filename,
        bytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _files = [...?_files, uploaded];
      });
      _announce(context.strings.fileUploaded);
    } catch (exception) {
      _reportFailure(exception);
    }
  }

  Future<void> _remove(AttachmentRecord file) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteFileQuestion),
        content: Text(file.filename),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.deleteFile),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await widget.gateway.deleteAttachment(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
        attachmentId: file.id,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _files = [...?_files]..removeWhere((item) => item.id == file.id);
        _completedOcr.remove(file.id);
      });
      _announce(context.strings.fileDeleted);
    } catch (exception) {
      _reportFailure(exception);
    }
  }

  void _reportFailure(Object exception) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _actionError = exception;
    });
  }

  void _announce(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _AttachmentCard extends StatefulWidget {
  const _AttachmentCard({
    super.key,
    required this.file,
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.submissionId,
    required this.busy,
    required this.onDelete,
    required this.onOcrChanged,
  });

  final AttachmentRecord file;
  final BayyinGateway gateway;
  final String token;
  final String assessmentId;
  final String submissionId;
  final bool busy;
  final VoidCallback onDelete;
  final ValueChanged<OcrRecord?> onOcrChanged;

  @override
  State<_AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<_AttachmentCard> {
  OcrRecord? _ocr;
  bool _loaded = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final file = widget.file;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.verySoftGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 4, 0),
            leading: Icon(
              file.contentType == 'application/pdf'
                  ? Icons.picture_as_pdf_rounded
                  : Icons.image_rounded,
              size: 22,
            ),
            title: Text(file.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${strings.fileTypeLabel(file.contentType)}'
              ' · ${strings.fileSizeLabel(file.fileSize)}',
            ),
            trailing: IconButton(
              tooltip: strings.deleteFile,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: widget.busy ? null : widget.onDelete,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
            child: _ocrBody(strings),
          ),
        ],
      ),
    );
  }

  Widget _ocrBody(AppStrings strings) {
    if (!_loaded) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_running) {
      return Row(
        children: [
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(strings.extractingText),
        ],
      );
    }
    final ocr = _ocr;
    if (ocr == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.textNotExtractedYet),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _extract,
              icon: const Icon(Icons.document_scanner_rounded, size: 18),
              label: Text(strings.extractText),
            ),
          ),
        ],
      );
    }
    if (ocr.isFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.ocrFailed,
            style: const TextStyle(color: AppColors.danger),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _extract,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(strings.retryExtraction),
            ),
          ),
        ],
      );
    }
    final preview = ocr.extractedText.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.isEmpty)
          Text(strings.noExtractedText)
        else
          Text(
            preview.length > 80 ? '${preview.substring(0, 80)}…' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _openText,
            icon: const Icon(Icons.notes_rounded, size: 18),
            label: Text(strings.viewExtractedText),
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final result = await widget.gateway.fetchOcr(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
        attachmentId: widget.file.id,
      );
      if (!mounted) return;
      setState(() {
        _ocr = result;
        _loaded = true;
      });
      widget.onOcrChanged(result);
    } catch (_) {
      if (!mounted) return;
      // A failed fetch is treated as "not started" so the teacher can still
      // press extract; the next POST is the source of truth.
      setState(() => _loaded = true);
    }
  }

  Future<void> _extract() async {
    setState(() => _running = true);
    try {
      final result = await widget.gateway.runOcr(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
        attachmentId: widget.file.id,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _ocr = result;
      });
      widget.onOcrChanged(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _ocr = const OcrRecord(id: '', status: 'failed', extractedText: '');
      });
    }
  }

  void _openText() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OcrTextPage(
          filename: widget.file.filename,
          text: _ocr?.extractedText ?? '',
        ),
      ),
    );
  }
}

class _EmptyFilesHint extends StatelessWidget {
  const _EmptyFilesHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.verySoftGreen.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.attach_file_rounded,
            size: 18,
            color: AppColors.mutedText,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              context.strings.noFilesAttached,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paired Add file / Analyze controls for the student paper section.
class _StudentPaperActions extends StatelessWidget {
  const _StudentPaperActions({
    required this.addLabel,
    required this.analyzeLabel,
    required this.onAddFile,
    required this.onAnalyze,
    required this.uploading,
    required this.analyzing,
  });

  final String addLabel;
  final String analyzeLabel;
  final VoidCallback? onAddFile;
  final VoidCallback? onAnalyze;
  final bool uploading;
  final bool analyzing;

  static const _gap = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final addButton = _PaperActionButton(
      label: addLabel,
      icon: Icons.upload_file_rounded,
      onPressed: onAddFile,
      loading: uploading,
      emphasized: false,
    );
    final analyzeButton = _PaperActionButton(
      label: analyzeLabel,
      icon: Icons.document_scanner_rounded,
      onPressed: onAnalyze,
      loading: analyzing,
      emphasized: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 300;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              addButton,
              const SizedBox(height: _gap),
              analyzeButton,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: addButton),
            const SizedBox(width: _gap),
            Expanded(child: analyzeButton),
          ],
        );
      },
    );
  }
}

class _PaperActionButton extends StatelessWidget {
  const _PaperActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.emphasized,
    required this.loading,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool loading;

  static const _height = 40.0;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized ? Colors.white : AppColors.primary;
    final background = emphasized ? AppColors.primary : AppColors.softMint;
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: loading
              ? background
              : (emphasized
                    ? AppColors.primary.withValues(alpha: 0.38)
                    : AppColors.softMint.withValues(alpha: 0.72)),
          disabledForegroundColor: loading
              ? foreground
              : foreground.withValues(alpha: 0.62),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
          minimumSize: const Size(0, _height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          alignment: AlignmentDirectional.center,
          overlayColor: (emphasized ? Colors.white : AppColors.primary)
              .withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
            side: emphasized
                ? BorderSide.none
                : BorderSide(color: AppColors.primary.withValues(alpha: 0.14)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            height: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: isError ? const TextStyle(color: AppColors.danger) : null,
  );
}

class _AnswerField extends StatefulWidget {
  const _AnswerField({required this.answer, required this.controller});

  final AnswerRecord answer;
  final TextEditingController controller;

  @override
  State<_AnswerField> createState() => _AnswerFieldState();
}

class _AnswerFieldState extends State<_AnswerField> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final answer = widget.answer;
    final evaluation = answer.evaluation;
    final tone = EvaluationTone.of(evaluation?.status);
    return Card(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: evaluation == null
              ? AppColors.border
              : tone.color.withValues(alpha: 0.32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: evaluation == null
                        ? AppColors.border
                        : tone.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    strings.questionPosition(answer.order),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  strings.maximumScoreValue(answer.maxScore),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(answer.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: strings.studentAnswer,
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  12,
                  10,
                  12,
                  10,
                ),
              ),
            ),
            if (evaluation != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  StatusChip(
                    label: strings.evaluationStatus(evaluation.status),
                    tone: tone,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        strings.awardedScoreValue(
                          evaluation.awardedScore,
                          answer.maxScore,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tone.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
                  child: Text(
                    _detailsOpen
                        ? strings.hideEvaluationDetails
                        : strings.viewEvaluationDetails,
                  ),
                ),
              ),
              if (_detailsOpen) _EvaluationDetails(evaluation: evaluation),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvaluationDetails extends StatelessWidget {
  const _EvaluationDetails({required this.evaluation});

  final EvaluationRecord evaluation;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final tone = EvaluationTone.of(evaluation.status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warmBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.aiEvaluation,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tone.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.feedback,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(strings.evaluationFeedback(evaluation.feedback)),
          if (evaluation.hasMisconception) ...[
            const SizedBox(height: AppSpacing.xs),
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
      ),
    );
  }
}

class _CompactResultSummary extends StatelessWidget {
  const _CompactResultSummary({
    required this.result,
    required this.loading,
    required this.error,
    required this.onOpenDetails,
  });

  final SubmissionResultRecord? result;
  final bool loading;
  final Object? error;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.assessmentResult,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (error != null)
              Text(
                strings.describeError(error),
                style: const TextStyle(color: AppColors.danger),
              )
            else if (result != null) ...[
              Row(
                children: [
                  _CompactScoreRing(result: result!),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result!.canEvaluate
                              ? (result!.isComplete
                                    ? strings.resultComplete
                                    : strings.resultIncomplete)
                              : strings.resultNotEvaluable,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: result!.isComplete
                                ? EvaluationTone.correct.color
                                : (result!.canEvaluate
                                      ? EvaluationTone.partial.color
                                      : EvaluationTone.incorrect.color),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings.awardedScoreValue(
                            result!.awardedScoreTotal,
                            result!.maxScoreTotal,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(strings.percentageValue(result!.percentage)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ResultStatusCounts(result: result!),
              if (result!.canEvaluate && !result!.isComplete) ...[
                const SizedBox(height: AppSpacing.sm),
                ResultNotice(
                  tone: EvaluationTone.pending,
                  body: strings.resultIncompleteWarning,
                ),
              ],
              if (!result!.canEvaluate) ...[
                const SizedBox(height: AppSpacing.sm),
                ResultNotice(
                  tone: EvaluationTone.incorrect,
                  body: strings.resultNotEvaluableWarning,
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onOpenDetails,
                  child: Text(strings.viewResultDetails),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactScoreRing extends StatelessWidget {
  const _CompactScoreRing({required this.result});

  final SubmissionResultRecord result;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final tone = result.canEvaluate
        ? EvaluationTone.forPercentage(result.percentage)
        : EvaluationTone.pending;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: _size,
            height: _size,
            child: CircularProgressIndicator(
              value: result.canEvaluate
                  ? (result.percentage / 100).clamp(0.0, 1.0)
                  : 0,
              strokeWidth: 5,
              color: tone.color,
              backgroundColor: tone.color.withValues(alpha: 0.14),
            ),
          ),
          FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                strings.studentPercentage(result.percentage),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: tone.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
