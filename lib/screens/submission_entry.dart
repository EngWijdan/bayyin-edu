import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';

/// Manual answer entry for one student's submission. Loads the submission so
/// the form is built from the server's answer sheet rather than from whatever
/// the previous screen happened to hold.
class SubmissionEntryPage extends StatefulWidget {
  const SubmissionEntryPage({
    super.key,
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.submissionId,
  });

  final BayyinGateway gateway;
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
    return FutureBuilder<SubmissionRecord>(
      future: _submission,
      builder: (context, snapshot) {
        final submission = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submission?.assessmentTitle ?? strings.loading,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  strings.studentSubmissions,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          body: switch (snapshot) {
            AsyncSnapshot(connectionState: ConnectionState.waiting) =>
              LoadingState(message: strings.loading),
            AsyncSnapshot(hasError: true, :final error) => ErrorRetryState(
              message: strings.describeError(error),
              retryLabel: strings.retry,
              onRetry: () => setState(_reload),
            ),
            _ => _AnswerSheet(
              // A fresh form whenever a different submission arrives.
              key: ValueKey(submission!.id),
              gateway: widget.gateway,
              token: widget.token,
              assessmentId: widget.assessmentId,
              submission: submission,
            ),
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
    required this.token,
    required this.assessmentId,
    required this.submission,
  });

  final BayyinGateway gateway;
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
  Object? error;

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
    final submission = widget.submission;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(submission.studentCode.characters.first),
            ),
            title: Text(
              submission.hasName
                  ? submission.studentName
                  : strings.unnamedStudent,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(submission.studentCode),
          ),
        ),
        const SizedBox(height: 16),
        if (_answers.isEmpty)
          EmptyState(
            icon: Icons.help_outline,
            message: strings.noQuestionsInAssessment,
          )
        else ...[
          ..._answers.map(
            (answer) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: _AnswerField(
                answer: answer,
                controller: _controllers[answer.questionId]!,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              strings.describeError(error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(saving ? strings.saving : strings.saveAnswers),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final updated = await widget.gateway.saveAnswers(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submission.id,
        answersByQuestionId: {
          for (final entry in _controllers.entries)
            entry.key: entry.value.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() {
        saving = false;
        _answers = updated.answers;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.answersSaved)));
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception;
      });
    }
  }
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({required this.answer, required this.controller});

  final AnswerRecord answer;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.questionPosition(answer.order),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(answer.text),
            const SizedBox(height: 4),
            Text(strings.maximumScoreValue(answer.maxScore)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: strings.studentAnswer,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
