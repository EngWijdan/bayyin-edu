import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import 'assessment_details.dart';

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
      appBar: AppBar(title: Text(strings.assessments)),
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
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(strings.assessmentsSubtitle),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: _createAssessment,
                    icon: const Icon(Icons.post_add_outlined),
                    label: Text(strings.createAssessment),
                  ),
                ),
                const SizedBox(height: 16),
                if (assessments.isEmpty)
                  const _EmptyAssessments()
                else
                  ...assessments.map(
                    (assessment) => Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: _AssessmentTile(
                        assessment: assessment,
                        onTap: () => _openDetails(assessment),
                      ),
                    ),
                  ),
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

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment, required this.onTap});

  final AssessmentRecord assessment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.assignment_outlined)),
        title: Text(
          assessment.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${strings.assessmentMeta(assessment.classroomName, assessment.subject)}\n'
          '${strings.questionsLabel(assessment.questionsCount)} • '
          '${strings.totalScoreValue(assessment.totalScore)}',
        ),
        isThreeLine: true,
        trailing: Icon(
          Directionality.of(context) == TextDirection.rtl
              ? Icons.chevron_left
              : Icons.chevron_right,
        ),
      ),
    );
  }
}

class _EmptyAssessments extends StatelessWidget {
  const _EmptyAssessments();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.assignment_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              strings.noAssessments,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(strings.noAssessmentsSubtitle, textAlign: TextAlign.center),
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
    required this.token,
    required this.classrooms,
  });

  final BayyinGateway gateway;
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

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.createAssessment)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: classroomId,
                  decoration: InputDecoration(
                    labelText: strings.assessmentClassroom,
                    border: const OutlineInputBorder(),
                  ),
                  items: widget.classrooms
                      .map(
                        (classroom) => DropdownMenuItem(
                          value: classroom.id,
                          child: Text(
                            strings.assessmentMeta(
                              classroom.name,
                              classroom.subject,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => classroomId = value!,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: strings.assessmentTitle,
                    hintText: strings.assessmentTitleHint,
                    border: const OutlineInputBorder(),
                  ),
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
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(saving ? strings.saving : strings.save),
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
}
