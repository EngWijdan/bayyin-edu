import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../theme/app_layout.dart';
import '../widgets/assessment_card.dart';
import '../widgets/async_states.dart';
import '../widgets/info_banner.dart';
import '../widgets/responsive.dart';
import '../widgets/teacher_home.dart';
import 'archived_assessments.dart';
import 'assessment_details.dart';
import 'exam_question_review.dart';

/// The assessments the signed-in teacher owns. The backend already scopes the
/// list to their own classrooms, so nothing is filtered here.
class TeacherAssessmentsPage extends StatefulWidget {
  const TeacherAssessmentsPage({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
    required this.classrooms,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;

  /// The only classrooms a new assessment may be attached to.
  final List<ClassroomRecord> classrooms;

  @override
  State<TeacherAssessmentsPage> createState() => _TeacherAssessmentsPageState();
}

class _TeacherAssessmentsPageState extends State<TeacherAssessmentsPage> {
  late Future<List<AssessmentRecord>> _assessments;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _assessments = widget.gateway.fetchAssessments(widget.token);
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
              strings.assessments,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            Text(
              strings.manageAssessmentsHint,
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
          await _assessments.catchError((_) => <AssessmentRecord>[]);
        },
        child: FutureBuilder<List<AssessmentRecord>>(
          future: _assessments,
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
            final assessments = snapshot.data ?? [];
            final compactButton = FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            );
            return ResponsivePage(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                CompactInfoBanner(message: strings.examWorkflowBanner),
                const SizedBox(height: 20),
                if (assessments.isNotEmpty) ...[
                  AdaptiveCta(
                    child: FilledButton.icon(
                      style: compactButton,
                      onPressed: _createAssessment,
                      icon: const Icon(Icons.post_add_rounded, size: 18),
                      label: Text(strings.createAssessment),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _openArchive,
                    icon: const Icon(Icons.inventory_2_rounded, size: 18),
                    label: Text(strings.archivedAssessments),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                if (assessments.isEmpty) ...[
                  const SizedBox(height: 24),
                  _EmptyAssessments(onCreate: _createAssessment),
                ] else ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.currentAssessments,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        strings.assessmentsCountLabel(assessments.length),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ResponsiveGrid(
                    spacing: 12,
                    children: [
                      for (final assessment in assessments)
                        SwipeableAssessmentCard(
                          assessment: assessment,
                          onTap: () => _openDetails(assessment),
                          confirmDelete: () => _confirmDelete(assessment),
                          onSwipeAway: (direction) =>
                              _handleSwipe(assessment, direction),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.swipeToArchiveOrDelete,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _createAssessment() async {
    if (widget.classrooms.isEmpty) {
      _notify(context.strings.noClassroomForAssessment);
      return;
    }
    final created = await Navigator.of(context).push<AssessmentRecord>(
      MaterialPageRoute(
        builder: (_) => CreateAssessmentPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
          classrooms: widget.classrooms,
        ),
      ),
    );
    if (created == null || !mounted) return;
    setState(_reload);
    _notify(context.strings.assessmentCreated);
    await _openDetails(created);
  }

  Future<void> _openArchive() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArchivedAssessmentsPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<bool> _confirmDelete(AssessmentRecord assessment) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteAssessment),
        content: Text('${assessment.title}\n\n${strings.deleteAssessmentConfirm}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.deleteAssessment),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleSwipe(
    AssessmentRecord assessment,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.endToStart) {
      await _delete(assessment);
      return;
    }
    await _archive(assessment);
  }

  Future<void> _archive(AssessmentRecord assessment) async {
    try {
      await widget.gateway.setAssessmentArchived(
        token: widget.token,
        assessmentId: assessment.id,
        archived: true,
      );
      if (!mounted) return;
      setState(_reload);
      _notify(context.strings.assessmentArchived);
    } catch (error) {
      if (!mounted) return;
      setState(_reload);
      _notify(context.strings.describeError(error));
    }
  }

  Future<void> _delete(AssessmentRecord assessment) async {
    try {
      await widget.gateway.deleteAssessment(
        token: widget.token,
        assessmentId: assessment.id,
      );
      if (!mounted) return;
      setState(_reload);
      _notify(context.strings.assessmentDeleted);
    } catch (error) {
      if (!mounted) return;
      setState(_reload);
      _notify(context.strings.describeError(error));
    }
  }

  Future<void> _openDetails(AssessmentRecord assessment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AssessmentDetailsPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
          assessment: assessment,
        ),
      ),
    );
    // Question counts and totals change inside the details screen.
    if (mounted) setState(_reload);
  }

  void _notify(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyAssessments extends StatelessWidget {
  const _EmptyAssessments({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              strings.noAssessments,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.noAssessmentsSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.post_add_rounded, size: 18),
              label: Text(strings.createAssessment),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pops with the created [AssessmentRecord], or null when the teacher backs out.
class CreateAssessmentPage extends StatefulWidget {
  const CreateAssessmentPage({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
    required this.classrooms,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;
  final List<ClassroomRecord> classrooms;

  @override
  State<CreateAssessmentPage> createState() => _CreateAssessmentPageState();
}

class _CreateAssessmentPageState extends State<CreateAssessmentPage> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  late String classroomId = widget.classrooms.first.id;
  bool saving = false;
  Object? error;
  Object? uploadError;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.classrooms.firstWhere(
      (classroom) => classroom.id == classroomId,
      orElse: () => widget.classrooms.first,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.createAssessment,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ResponsivePage(
            maxWidth: AppLayout.formMaxWidth,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              TeacherHomeSectionTitle(title: strings.assessmentDetails),
              const SizedBox(height: 12),
              _CreateSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.assessmentClassroom,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: classroomId,
                      isExpanded: true,
                      itemHeight: 64,
                      borderRadius: BorderRadius.circular(12),
                      decoration: _fieldDecoration(),
                      selectedItemBuilder: (context) => [
                        for (final classroom in widget.classrooms)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              classroom.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      items: [
                        for (final classroom in widget.classrooms)
                          DropdownMenuItem(
                            value: classroom.id,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    classroom.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    strings.classroomOptionDetail(
                                      classroom.subject,
                                      classroom.grade,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() => classroomId = value!),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.classroomOptionDetail(
                        selected.subject,
                        selected.grade,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.assessmentTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: title,
                      enabled: !saving,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                      decoration: _fieldDecoration(
                        hint: strings.assessmentTitleHint,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? strings.requiredField
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TeacherHomeSectionTitle(
                      title: strings.flowStepOriginalPaper,
                    ),
                  ),
                  Text(
                    strings.optional,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ExamPaperUploadCard(
                enabled: !saving,
                error: uploadError,
                onChooseFile: _submitWithExamPaper,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
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
                  child: FilledButton.icon(
                    onPressed: saving ? null : _submit,
                    icon: saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(saving ? strings.saving : strings.save),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
      uploadError = null;
    });
    try {
      final created = await widget.gateway.createAssessment(
        token: widget.token,
        classroomId: classroomId,
        title: title.text.trim(),
      );
      if (mounted) Navigator.pop(context, created);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception;
      });
    }
  }

  Future<void> _submitWithExamPaper() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
      uploadError = null;
    });
    try {
      final created = await widget.gateway.createAssessment(
        token: widget.token,
        classroomId: classroomId,
        title: title.text.trim(),
      );
      if (!mounted) return;
      await startExamPaperExtraction(
        context: context,
        gateway: widget.gateway,
        picker: widget.picker,
        token: widget.token,
        assessmentId: created.id,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        uploadError = exception;
      });
    }
  }
}

class _CreateSectionCard extends StatelessWidget {
  const _CreateSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: child,
      ),
    );
  }
}

class _ExamPaperUploadCard extends StatelessWidget {
  const _ExamPaperUploadCard({
    required this.enabled,
    required this.onChooseFile,
    this.error,
  });

  final bool enabled;
  final VoidCallback onChooseFile;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.upload_file_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.uploadExamPaper,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.uploadExamPaperHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.uploadExamPaperSupport,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              strings.supportedExamFormats,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: enabled ? onChooseFile : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(strings.chooseFile),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                strings.describeError(error),
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
