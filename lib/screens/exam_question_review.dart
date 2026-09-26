import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../theme/app_layout.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';

/// Upload an exam paper, extract suggested questions, then let the teacher
/// edit them before they become real [QuestionRecord]s.
class ExamQuestionReviewPage extends StatefulWidget {
  const ExamQuestionReviewPage({
    super.key,
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.paper,
  });

  final BayyinGateway gateway;
  final String token;
  final String assessmentId;
  final PickedAttachment paper;

  @override
  State<ExamQuestionReviewPage> createState() => _ExamQuestionReviewPageState();
}

enum _ExtractPhase { uploading, extracting, ready, empty, error }

class _ExamQuestionReviewPageState extends State<ExamQuestionReviewPage> {
  _ExtractPhase phase = _ExtractPhase.uploading;
  Object? error;
  List<QuestionCandidateRecord> candidates = const [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      phase = _ExtractPhase.uploading;
      error = null;
    });
    try {
      await widget.gateway.uploadExamPaper(
        token: widget.token,
        assessmentId: widget.assessmentId,
        filename: widget.paper.filename,
        bytes: widget.paper.bytes,
      );
      if (!mounted) return;
      await _extract();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        phase = _ExtractPhase.error;
        error = exception;
      });
    }
  }

  Future<void> _extract() async {
    setState(() {
      phase = _ExtractPhase.extracting;
      error = null;
    });
    try {
      final extracted = await widget.gateway.extractQuestions(
        token: widget.token,
        assessmentId: widget.assessmentId,
      );
      if (!mounted) return;
      setState(() {
        candidates = extracted;
        phase = extracted.isEmpty ? _ExtractPhase.empty : _ExtractPhase.ready;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        phase = _ExtractPhase.error;
        error = exception;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.reviewQuestions,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: switch (phase) {
        _ExtractPhase.uploading => LoadingState(
          message: strings.uploadingExamPaper,
        ),
        _ExtractPhase.extracting => LoadingState(
          message: strings.extractingQuestions,
        ),
        _ExtractPhase.error => ErrorRetryState(
          message: strings.couldNotExtractQuestions,
          retryLabel: strings.retry,
          onRetry: _start,
        ),
        _ExtractPhase.empty => ErrorRetryState(
          message: strings.noQuestionsFound,
          retryLabel: strings.retry,
          onRetry: _extract,
        ),
        _ExtractPhase.ready => _ReviewForm(
          gateway: widget.gateway,
          token: widget.token,
          assessmentId: widget.assessmentId,
          initial: candidates,
        ),
      },
    );
  }
}

class _Draft {
  _Draft({
    required this.id,
    required this.order,
    required this.text,
    required this.maxScore,
    required this.modelAnswer,
  });

  factory _Draft.fromCandidate(QuestionCandidateRecord candidate) => _Draft(
    id: candidate.id,
    order: candidate.order,
    text: TextEditingController(text: candidate.extractedText),
    maxScore: TextEditingController(
      text: candidate.proposedMaxScore == null
          ? ''
          : _scoreText(candidate.proposedMaxScore!),
    ),
    modelAnswer: TextEditingController(text: candidate.proposedModelAnswer),
  );

  factory _Draft.blank(int order) => _Draft(
    id: '',
    order: order,
    text: TextEditingController(),
    maxScore: TextEditingController(),
    modelAnswer: TextEditingController(),
  );

  final String id;
  int order;
  final TextEditingController text;
  final TextEditingController maxScore;
  final TextEditingController modelAnswer;

  void dispose() {
    text.dispose();
    maxScore.dispose();
    modelAnswer.dispose();
  }
}

String _scoreText(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

class _ReviewForm extends StatefulWidget {
  const _ReviewForm({
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.initial,
  });

  final BayyinGateway gateway;
  final String token;
  final String assessmentId;
  final List<QuestionCandidateRecord> initial;

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  final formKey = GlobalKey<FormState>();
  late List<_Draft> drafts;
  bool saving = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    drafts = [
      for (final candidate in widget.initial) _Draft.fromCandidate(candidate),
    ];
  }

  @override
  void dispose() {
    for (final draft in drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Form(
      key: formKey,
      child: Column(
        children: [
          Expanded(
            child: ResponsivePage(
              maxWidth: AppLayout.formMaxWidth,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  strings.reviewQuestionsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.extractedQuestionsFound(drafts.length),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < drafts.length; index++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 12),
                    child: _CandidateCard(
                      draft: drafts[index],
                      onRemove: () => _removeAt(index),
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: saving ? null : _add,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(strings.addQuestionManually),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: ResponsiveBar(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      Text(
                        strings.describeError(error),
                        style: TextStyle(color: scheme.error),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: saving ? null : _confirm,
                        child: Text(
                          saving
                              ? strings.confirming
                              : strings.confirmQuestions,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _add() {
    final next = drafts.isEmpty
        ? 1
        : drafts.map((draft) => draft.order).reduce((a, b) => a > b ? a : b) +
              1;
    setState(() => drafts.add(_Draft.blank(next)));
  }

  void _removeAt(int index) {
    setState(() {
      drafts.removeAt(index).dispose();
    });
  }

  Future<void> _confirm() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.gateway.confirmQuestionCandidates(
        token: widget.token,
        assessmentId: widget.assessmentId,
        candidates: [
          for (final draft in drafts)
            QuestionCandidateRecord(
              id: draft.id,
              order: draft.order,
              extractedText: draft.text.text.trim(),
              proposedMaxScore: double.parse(draft.maxScore.text.trim()),
              proposedModelAnswer: draft.modelAnswer.text.trim(),
            ),
        ],
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

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.draft, required this.onRemove});

  final _Draft draft;
  final VoidCallback onRemove;

  InputDecoration _fieldDecoration(ColorScheme scheme) {
    final radius = BorderRadius.circular(10);
    final idle = BorderSide(color: scheme.outlineVariant);
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      errorMaxLines: 2,
      errorStyle: const TextStyle(fontSize: 11, height: 1.2),
      border: OutlineInputBorder(borderRadius: radius, borderSide: idle),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: idle),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  Widget _label(String text, TextStyle? style) {
    return Text(text, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final decoration = _fieldDecoration(scheme);
    final secondaryLabel = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${draft.order}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.questionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.removeQuestion,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                  color: scheme.error.withValues(alpha: 0.72),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            _label(
              strings.extractedQuestion,
              theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: draft.text,
              minLines: 1,
              maxLines: 6,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textInputAction: TextInputAction.next,
              decoration: decoration,
              validator: (value) => value == null || value.trim().isEmpty
                  ? strings.requiredField
                  : null,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 340;
                final scoreField = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(strings.suggestedScore, secondaryLabel),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: draft.maxScore,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.next,
                      decoration: decoration,
                      validator: (value) {
                        final score = double.tryParse(value?.trim() ?? '');
                        return score == null || score <= 0
                            ? strings.invalidScore
                            : null;
                      },
                    ),
                  ],
                );
                final answerField = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(
                      strings.modelAnswer,
                      secondaryLabel?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: draft.modelAnswer,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      decoration: decoration,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? strings.requiredField
                          : null,
                    ),
                  ],
                );
                if (!sideBySide) {
                  return Column(
                    children: [
                      scoreField,
                      const SizedBox(height: 8),
                      answerField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 96, child: scoreField),
                    const SizedBox(width: 10),
                    Expanded(child: answerField),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> startExamPaperExtraction({
  required BuildContext context,
  required BayyinGateway gateway,
  required AttachmentPicker picker,
  required String token,
  required String assessmentId,
}) async {
  final strings = context.strings;
  final picked = await picker.pick();
  if (picked == null || !context.mounted) return false;
  if (!picked.hasSupportedExtension) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.unsupportedFileType)));
    return false;
  }
  if (!picked.isWithinSizeLimit) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.fileTooLarge)));
    return false;
  }
  final confirmed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ExamQuestionReviewPage(
        gateway: gateway,
        token: token,
        assessmentId: assessmentId,
        paper: picked,
      ),
    ),
  );
  return confirmed == true;
}
