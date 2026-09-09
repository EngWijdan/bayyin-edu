import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/language_switcher.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({
    super.key,
    required this.gateway,
    required this.session,
    required this.onLogout,
    required this.onLocaleChanged,
  });

  final BayyinGateway gateway;
  final UserSession session;
  final VoidCallback onLogout;
  final ValueChanged<AppLocale> onLocaleChanged;

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  late Future<List<TeacherAccount>> _teachers;
  late Future<List<ClassroomRecord>> _classrooms;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _teachers = widget.gateway.fetchTeachers(widget.session.token);
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
            Text(
              strings.managerDashboard,
              style: const TextStyle(fontSize: 12),
            ),
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
          await Future.wait([_teachers, _classrooms]);
        },
        child: FutureBuilder<List<TeacherAccount>>(
          future: _teachers,
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
            final teachers = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  strings.greeting(widget.session.displayName),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(strings.managerSubtitle),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.teachersCount(teachers.length),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _showAddTeacher,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(strings.addTeacher),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (teachers.isEmpty)
                  const _EmptyTeachers()
                else
                  ...teachers.map(
                    (teacher) => Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(teacher.displayName.characters.first),
                          ),
                          title: Text(teacher.displayName),
                          subtitle: Text(
                            teacher.email.isEmpty
                                ? '@${teacher.username}'
                                : '${teacher.email} • @${teacher.username}',
                          ),
                          trailing: Chip(
                            label: Text(
                              teacher.isActive
                                  ? strings.teacherActive
                                  : strings.teacherSuspended,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                _ClassroomsPanel(
                  future: _classrooms,
                  onAddClassroom: () => _showAddClassroom(teachers),
                  onAddStudent: _showAddStudent,
                  onRetry: () => setState(_reload),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddTeacher() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AddTeacherDialog(
        gateway: widget.gateway,
        token: widget.session.token,
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      _notify(context.strings.teacherCreated);
    }
  }

  Future<void> _showAddClassroom(List<TeacherAccount> teachers) async {
    if (teachers.isEmpty) {
      _notify(context.strings.addTeacherBeforeClassroom);
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AddClassroomDialog(
        gateway: widget.gateway,
        token: widget.session.token,
        teachers: teachers,
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      _notify(context.strings.classroomCreated);
    }
  }

  Future<void> _showAddStudent(ClassroomRecord classroom) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _AddStudentDialog(
        gateway: widget.gateway,
        token: widget.session.token,
        classroom: classroom,
      ),
    );
    if (created == true && mounted) {
      setState(_reload);
      _notify(context.strings.studentCreated);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AddTeacherDialog extends StatefulWidget {
  const _AddTeacherDialog({required this.gateway, required this.token});
  final BayyinGateway gateway;
  final String token;

  @override
  State<_AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<_AddTeacherDialog> {
  final formKey = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  bool saving = false;
  Object? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.addTeacher),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: firstName,
                        decoration: InputDecoration(
                          labelText: strings.firstName,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: lastName,
                        decoration: InputDecoration(
                          labelText: strings.lastName,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: username,
                  decoration: InputDecoration(labelText: strings.username),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? strings.requiredField
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: strings.emailOptional),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.temporaryPassword,
                  ),
                  validator: (value) => value != null && value.length >= 8
                      ? null
                      : strings.passwordTooShort,
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
          child: Text(saving ? strings.saving : strings.createAccount),
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
      await widget.gateway.createTeacher(
        token: widget.token,
        username: username.text.trim(),
        password: password.text,
        firstName: firstName.text.trim(),
        lastName: lastName.text.trim(),
        email: email.text.trim(),
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

class _ClassroomsPanel extends StatelessWidget {
  const _ClassroomsPanel({
    required this.future,
    required this.onAddClassroom,
    required this.onAddStudent,
    required this.onRetry,
  });

  final Future<List<ClassroomRecord>> future;
  final VoidCallback onAddClassroom;
  final ValueChanged<ClassroomRecord> onAddStudent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return FutureBuilder<List<ClassroomRecord>>(
      future: future,
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.classroomsCount(snapshot.data?.length ?? 0),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAddClassroom,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(strings.addClassroom),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (snapshot.hasError)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(strings.describeError(snapshot.error)),
                  trailing: IconButton(
                    tooltip: strings.retry,
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              )
            else if ((snapshot.data ?? []).isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(strings.noClassrooms),
                ),
              )
            else
              ...(snapshot.data ?? []).map(
                (classroom) => Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.school_outlined),
                      ),
                      title: Text(
                        strings.classroomTitle(
                          classroom.name,
                          classroom.subject,
                        ),
                      ),
                      subtitle: Text(
                        strings.classroomSubtitle(
                          grade: classroom.grade,
                          teacherName: classroom.teacherName,
                          studentsCount: classroom.studentsCount,
                          academicYear: classroom.academicYear,
                        ),
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: strings.addStudent,
                        onPressed: () => onAddStudent(classroom),
                        icon: const Icon(Icons.person_add_outlined),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AddClassroomDialog extends StatefulWidget {
  const _AddClassroomDialog({
    required this.gateway,
    required this.token,
    required this.teachers,
  });
  final BayyinGateway gateway;
  final String token;
  final List<TeacherAccount> teachers;

  @override
  State<_AddClassroomDialog> createState() => _AddClassroomDialogState();
}

class _AddClassroomDialogState extends State<_AddClassroomDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final grade = TextEditingController();
  final subject = TextEditingController();
  final academicYear = TextEditingController(text: '1448');
  late String teacherProfileId = widget.teachers.first.profileId;
  bool saving = false;
  Object? error;

  @override
  void dispose() {
    name.dispose();
    grade.dispose();
    subject.dispose();
    academicYear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.addClassroom),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _requiredField(name, strings.classroomName, strings),
                const SizedBox(height: 10),
                _requiredField(grade, strings.grade, strings),
                const SizedBox(height: 10),
                _requiredField(subject, strings.subject, strings),
                const SizedBox(height: 10),
                _requiredField(academicYear, strings.academicYear, strings),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: teacherProfileId,
                  decoration: InputDecoration(
                    labelText: strings.assignedTeacher,
                  ),
                  items: widget.teachers
                      .map(
                        (teacher) => DropdownMenuItem(
                          value: teacher.profileId,
                          child: Text(teacher.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => teacherProfileId = value!,
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
          child: Text(saving ? strings.saving : strings.createClassroom),
        ),
      ],
    );
  }

  TextFormField _requiredField(
    TextEditingController controller,
    String label,
    AppStrings strings,
  ) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        value == null || value.trim().isEmpty ? strings.requiredField : null,
  );

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.gateway.createClassroom(
        token: widget.token,
        name: name.text.trim(),
        grade: grade.text.trim(),
        subject: subject.text.trim(),
        academicYear: academicYear.text.trim(),
        teacherProfileId: teacherProfileId,
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

class _AddStudentDialog extends StatefulWidget {
  const _AddStudentDialog({
    required this.gateway,
    required this.token,
    required this.classroom,
  });
  final BayyinGateway gateway;
  final String token;
  final ClassroomRecord classroom;

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
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

class _EmptyTeachers extends StatelessWidget {
  const _EmptyTeachers();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.group_add_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              strings.noTeachersTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(strings.noTeachersSubtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
