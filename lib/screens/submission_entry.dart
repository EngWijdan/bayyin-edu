import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';

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
              picker: widget.picker,
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
        _AttachmentsSection(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
          assessmentId: widget.assessmentId,
          submissionId: submission.id,
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
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final String assessmentId;
  final String submissionId;

  @override
  State<_AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<_AttachmentsSection> {
  List<AttachmentRecord>? _files;
  Object? _loadError;

  /// An upload or a delete is in flight.
  bool _busy = false;
  Object? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final files = _files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.studentPaper,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.supportedFileTypes,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (files == null && _loadError == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          _Message(strings.describeError(_loadError), isError: true)
        else if (files!.isEmpty)
          _Message(strings.noFilesAttached)
        else
          ...files.map(
            (file) => Card(
              child: ListTile(
                leading: Icon(
                  file.contentType == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                ),
                title: Text(file.filename),
                subtitle: Text(
                  '${strings.fileTypeLabel(file.contentType)}'
                  ' · ${strings.fileSizeLabel(file.fileSize)}',
                ),
                trailing: IconButton(
                  tooltip: strings.deleteFile,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _remove(file),
                ),
              ),
            ),
          ),
        if (_actionError != null) ...[
          const SizedBox(height: 4),
          _Message(_describe(strings, _actionError!), isError: true),
        ],
        const SizedBox(height: 8),
        if (_busy)
          Row(
            children: [
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(strings.uploading),
            ],
          )
        else
          FilledButton.tonalIcon(
            onPressed: _addFile,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(strings.addFile),
          ),
      ],
    );
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

  void _announce(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: isError
        ? TextStyle(color: Theme.of(context).colorScheme.error)
        : null,
  );
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
