import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';

/// Read-only roster for one classroom. The backend returns 404 for a classroom
/// the caller is not assigned to, which surfaces here as the error state.
class ClassroomStudentsPage extends StatefulWidget {
  const ClassroomStudentsPage({
    super.key,
    required this.gateway,
    required this.token,
    required this.classroom,
  });

  final BayyinGateway gateway;
  final String token;
  final ClassroomRecord classroom;

  @override
  State<ClassroomStudentsPage> createState() => _ClassroomStudentsPageState();
}

class _ClassroomStudentsPageState extends State<ClassroomStudentsPage> {
  late Future<List<StudentRecord>> _students;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _students = widget.gateway.fetchStudents(
      token: widget.token,
      classroomId: widget.classroom.id,
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
              widget.classroom.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              strings.classroomMeta(
                widget.classroom.grade,
                widget.classroom.subject,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _students.catchError((_) => <StudentRecord>[]);
        },
        child: FutureBuilder<List<StudentRecord>>(
          future: _students,
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
            final students = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  strings.students,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(strings.studentsLabel(students.length)),
                const SizedBox(height: 16),
                if (students.isEmpty)
                  EmptyState(
                    icon: Icons.person_off_outlined,
                    message: strings.noStudentsInClass,
                  )
                else
                  ...students.map(
                    (student) => Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(student.internalCode.characters.first),
                          ),
                          title: Text(
                            student.internalCode,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            student.hasName
                                ? student.displayName
                                : strings.unnamedStudent,
                          ),
                        ),
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
}
