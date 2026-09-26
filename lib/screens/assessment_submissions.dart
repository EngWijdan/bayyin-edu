import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';
import '../widgets/teacher_flow.dart';
import 'submission_entry.dart';

/// The classroom roster for one assessment, marking which students already
/// have a submission. Tapping a student opens their submission, creating it
/// first when this is their first entry.
class AssessmentSubmissionsPage extends StatefulWidget {
  const AssessmentSubmissionsPage({
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
  State<AssessmentSubmissionsPage> createState() =>
      _AssessmentSubmissionsPageState();
}

class _AssessmentSubmissionsPageState extends State<AssessmentSubmissionsPage> {
  late Future<_Roster> _roster;

  /// Guards against a double tap creating two submissions for one student.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _roster = _load();
  }

  /// The roster comes from the classroom, the submissions from the assessment;
  /// both endpoints are already scoped to the caller by the backend.
  Future<_Roster> _load() async {
    final students = await widget.gateway.fetchStudents(
      token: widget.token,
      classroomId: widget.assessment.classroomId,
    );
    final submissions = await widget.gateway.fetchSubmissions(
      token: widget.token,
      assessmentId: widget.assessment.id,
    );
    final byStudent = {
      for (final submission in submissions) submission.studentId: submission,
    };
    return _Roster([
      for (final student in students)
        _RosterEntry(student: student, submission: byStudent[student.id]),
    ]);
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
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            Text(
              strings.studentSubmissions,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _roster.catchError((_) => const _Roster([]));
        },
        child: FutureBuilder<_Roster>(
          future: _roster,
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
            final roster = snapshot.data ?? const _Roster([]);
            return ResponsivePage(
              children: [
                const TeacherFlowBanner(activeStep: 2),
                const SizedBox(height: 16),
                Text(strings.studentsLabel(roster.total)),
                const SizedBox(height: 4),
                Text(
                  roster.enteredCount == 0
                      ? strings.noSubmissionsYet
                      : strings.submissionsProgress(
                          roster.enteredCount,
                          roster.total,
                        ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(strings.submissionsHint),
                const SizedBox(height: 16),
                if (roster.entries.isEmpty)
                  EmptyState(
                    icon: Icons.person_off_rounded,
                    message: strings.noStudentsInClass,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final entry in roster.entries)
                        _RosterTile(
                          entry: entry,
                          onTap: () => _openEntry(entry),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openEntry(_RosterEntry entry) async {
    if (_busy) return;
    final submission = entry.submission ?? await _createFor(entry.student);
    if (submission == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SubmissionEntryPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.token,
          assessmentId: widget.assessment.id,
          submissionId: submission.id,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<SubmissionRecord?> _createFor(StudentRecord student) async {
    _busy = true;
    try {
      return await widget.gateway.createSubmission(
        token: widget.token,
        assessmentId: widget.assessment.id,
        studentId: student.id,
      );
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.describeError(exception))),
        );
      }
      return null;
    } finally {
      _busy = false;
    }
  }
}

class _RosterEntry {
  const _RosterEntry({required this.student, this.submission});

  final StudentRecord student;
  final SubmissionRecord? submission;

  bool get isEntered => submission != null;
}

class _Roster {
  const _Roster(this.entries);

  final List<_RosterEntry> entries;

  int get total => entries.length;
  int get enteredCount => entries.where((entry) => entry.isEntered).length;
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({required this.entry, required this.onTap});

  final _RosterEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final student = entry.student;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Text(student.internalCode.characters.first)),
        title: Text(
          student.hasName ? student.displayName : strings.unnamedStudent,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(student.internalCode),
        trailing: Chip(
          label: Text(
            entry.isEntered
                ? strings.submissionEntered
                : strings.submissionNotEntered,
          ),
        ),
      ),
    );
  }
}
