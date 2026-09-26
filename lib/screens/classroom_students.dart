import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';

/// Roster for one classroom. Teachers and managers can add students here.
/// The backend returns 404 for a classroom the caller is not assigned to.
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
        actions: [
          IconButton(
            tooltip: strings.addStudent,
            onPressed: _showAddStudent,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
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
            return ResponsivePage(
              children: [
                Text(
                  strings.students,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(strings.studentsLabel(students.length)),
                const SizedBox(height: 16),
                if (students.isEmpty) ...[
                  EmptyState(
                    icon: Icons.person_off_rounded,
                    message: strings.noStudentsInClass,
                  ),
                  const SizedBox(height: 16),
                  AdaptiveCta(
                    child: FilledButton.icon(
                      onPressed: _showAddStudent,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(strings.addStudent),
                    ),
                  ),
                ] else
                  ResponsiveGrid(
                    children: [
                      for (final student in students)
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                student.internalCode.characters.first,
                              ),
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
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddStudent() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AddStudentDialog(
        gateway: widget.gateway,
        token: widget.token,
        classroom: widget.classroom,
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.studentCreated)),
      );
    }
  }
}

class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({
    super.key,
    required this.gateway,
    required this.token,
    required this.classroom,
  });

  final BayyinGateway gateway;
  final String token;
  final ClassroomRecord classroom;

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  final displayName = TextEditingController();
  bool saving = false;
  Object? error;

  @override
  void dispose() {
    code.dispose();
    displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.addStudentTo(widget.classroom.name)),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: code,
              decoration: InputDecoration(labelText: strings.studentCode),
              validator: (value) => value == null || value.trim().isEmpty
                  ? strings.requiredField
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: displayName,
              decoration: InputDecoration(
                labelText: strings.studentNameOptional,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                strings.describeError(error),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: Text(saving ? strings.saving : strings.addStudent),
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
      await widget.gateway.createStudent(
        token: widget.token,
        classroomId: widget.classroom.id,
        internalCode: code.text.trim(),
        displayName: displayName.text.trim(),
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
