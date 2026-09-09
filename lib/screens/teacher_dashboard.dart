import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/language_switcher.dart';
import 'classroom_students.dart';
import 'teacher_assessments.dart';

/// Read-only view of the classrooms the signed-in teacher is assigned to.
/// The backend already scopes the list, so no filtering happens here.
class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({
    super.key,
    required this.gateway,
    required this.session,
    this.onLogout,
    required this.onLocaleChanged,
  });

  final BayyinGateway gateway;
  final UserSession session;
  final VoidCallback? onLogout;
  final ValueChanged<AppLocale> onLocaleChanged;

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  late Future<List<ClassroomRecord>> _classrooms;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _classrooms = widget.gateway.fetchClassrooms(widget.session.token);
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
              strings.appName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(strings.appTagline, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          LanguageSwitcher(onLocaleChanged: widget.onLocaleChanged),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: strings.logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _classrooms.catchError((_) => <ClassroomRecord>[]);
        },
        child: FutureBuilder<List<ClassroomRecord>>(
          future: _classrooms,
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
            final classrooms = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  strings.greeting(widget.session.displayName),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(strings.teacherClassesSubtitle),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openAssessments(classrooms),
                    icon: const Icon(Icons.assignment_outlined),
                    label: Text(strings.assessments),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  strings.myClasses,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (classrooms.isEmpty)
                  EmptyState(
                    icon: Icons.school_outlined,
                    message: strings.noAssignedClasses,
                  )
                else
                  ...classrooms.map(
                    (classroom) => Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: _ClassroomTile(
                        classroom: classroom,
                        onTap: () => _openClassroom(classroom),
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

  void _openClassroom(ClassroomRecord classroom) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassroomStudentsPage(
          gateway: widget.gateway,
          token: widget.session.token,
          classroom: classroom,
        ),
      ),
    );
  }

  /// The loaded classrooms travel with the teacher so the create form can offer
  /// them without a second round trip.
  void _openAssessments(List<ClassroomRecord> classrooms) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeacherAssessmentsPage(
          gateway: widget.gateway,
          token: widget.session.token,
          classrooms: classrooms,
        ),
      ),
    );
  }
}

class _ClassroomTile extends StatelessWidget {
  const _ClassroomTile({required this.classroom, required this.onTap});

  final ClassroomRecord classroom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
        title: Text(
          classroom.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${strings.classroomMeta(classroom.grade, classroom.subject)}\n'
          '${strings.classroomCounts(classroom.academicYear, classroom.studentsCount)}',
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
