import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../theme/app_layout.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';

/// Teacher review of OCR suggestions before they become SubmissionAnswers.
class OcrAnswerReviewPage extends StatefulWidget {
  const OcrAnswerReviewPage({
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
  State<OcrAnswerReviewPage> createState() => _OcrAnswerReviewPageState();
}

class _OcrAnswerReviewPageState extends State<OcrAnswerReviewPage> {
  Future<OcrMappingRecord>? _mapping;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    _mapping = widget.gateway.runOcrMapping(
      token: widget.token,
      assessmentId: widget.assessmentId,
      submissionId: widget.submissionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return FutureBuilder<OcrMappingRecord>(
      future: _mapping,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              strings.reviewExtractedAnswers,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: switch (snapshot) {
            AsyncSnapshot(connectionState: ConnectionState.waiting) =>
              LoadingState(message: strings.extractAnswers),
            AsyncSnapshot(hasError: true, :final error) => ErrorRetryState(
              message: strings.describeError(error),
              retryLabel: strings.retry,
              onRetry: () => setState(_run),
            ),
            _ => _ReviewSheet(
              key: ValueKey(snapshot.data!.candidates.map((c) => c.id).join()),
              gateway: widget.gateway,
              token: widget.token,
              assessmentId: widget.assessmentId,
              submissionId: widget.submissionId,
              mapping: snapshot.data!,
            ),
          },
        );
      },
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({
    super.key,
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.submissionId,
    required this.mapping,
  });

  final BayyinGateway gateway;
  final String token;
  final String assessmentId;
  final String submissionId;
  final OcrMappingRecord mapping;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final candidate in widget.mapping.candidates)
      candidate.questionId: TextEditingController(text: candidate.fieldText),
  };
  bool _saving = false;
  Object? _error;

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
    final candidates = widget.mapping.candidates;
    return ResponsivePage(
      maxWidth: AppLayout.compactMaxWidth,
      children: [
        if (widget.mapping.incompleteOcr) ...[
          _Banner(strings.someFilesNotProcessed),
          const SizedBox(height: 16),
        ],
        if (candidates.isEmpty)
          EmptyState(
            icon: Icons.help_outline_rounded,
            message: strings.noQuestionsInAssessment,
          )
        else ...[
          ...candidates.map(
            (candidate) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: _CandidateCard(
                candidate: candidate,
                controller: _controllers[candidate.questionId]!,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              strings.describeError(_error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          AdaptiveCta(
            child: FilledButton(
              onPressed: _saving ? null : _confirm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _saving ? strings.confirming : strings.confirmAnswers,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = {
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      };
      if (kDebugMode) {
        developer.log(
          'OCR confirm payload ${payload.entries.map((entry) => '${entry.key}=${entry.value}').join(' | ')}',
          name: 'BayyinAnswers',
        );
      }
      await widget.gateway.confirmOcrMapping(
        token: widget.token,
        assessmentId: widget.assessmentId,
        submissionId: widget.submissionId,
        answersByQuestionId: payload,
      );
      if (!mounted) return;
      Navigator.of(context).pop(payload);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = exception;
      });
    }
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.controller});

  final OcrCandidateRecord candidate;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final extracted = candidate.extractedText.trim();
    final hasManual = candidate.currentAnswer.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.questionPosition(candidate.order),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(candidate.questionText),
            const SizedBox(height: 4),
            Text(strings.maximumScoreValue(candidate.maxScore)),
            const SizedBox(height: 12),
            if (extracted.isEmpty)
              Text(
                strings.noAnswerDetected,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (hasManual)
              Text(
                '${strings.extractedAnswer}: $extracted',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Text(
                strings.extractedAnswer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
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

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
