import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import 'assessment_submissions.dart';

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
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              strings.assessmentMeta(
                widget.assessment.classroomName,
                widget.assessment.subject,
              ),
              style: const TextStyle(fontSize: 12),
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
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: _openSubmissions,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: Text(strings.studentSubmissions),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.questions,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add),
                      label: Text(strings.addQuestion),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${strings.questionsLabel(assessment.questions.length)} • '
                  '${strings.totalScoreValue(assessment.totalScore)}',
                ),
                const SizedBox(height: 16),
                if (assessment.questions.isEmpty)
                  EmptyState(
                    icon: Icons.help_outline,
                    message: strings.noQuestions,
                  )
                else
                  ...assessment.questions.map(
                    (question) => Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: _QuestionTile(question: question),
                    ),
                  ),
              ],
            );
          },
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.questionAdded)));
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question});

  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${question.order}')),
        title: Text(
          question.text,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${strings.maximumScoreValue(question.maxScore)}\n'
          '${strings.modelAnswerValue(question.modelAnswer)}',
        ),
        isThreeLine: true,
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
