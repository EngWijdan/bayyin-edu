import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/branding.dart';
import '../widgets/language_switcher.dart';
import '../widgets/responsive.dart';
import 'classroom_students.dart';
import 'manager_insights.dart';

enum _ClassroomAction { viewStudents, addStudent, edit, changeTeacher, delete }

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
        title: BayyinBrandLockup(subtitle: strings.managerDashboard),
        actions: [
          LanguageSwitcher(onLocaleChanged: widget.onLocaleChanged),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: strings.logout,
            icon: const Icon(Icons.logout_rounded),
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
            return ResponsivePage(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  strings.welcomeBack,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.greeting(widget.session.displayName),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(strings.managerSubtitle),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: _openSchoolInsights,
                    icon: const Icon(Icons.insights_rounded),
                    label: Text(strings.schoolInsights),
                  ),
                ),
                const SizedBox(height: 24),
                SectionToolbar(
                  title: Text(
                    strings.teachersCount(teachers.length),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  action: FilledButton.icon(
                    onPressed: _showAddTeacher,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(strings.addTeacher),
                  ),
                ),
                const SizedBox(height: 12),
                if (teachers.isEmpty)
                  const _EmptyTeachers()
                else
                  ResponsiveGrid(
                    children: [
                      for (final teacher in teachers)
                        Card(
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
                    ],
                  ),
                const SizedBox(height: 18),
                _ClassroomsPanel(
                  future: _classrooms,
                  teachers: teachers,
                  onAddClassroom: () => _showAddClassroom(teachers),
                  onAction: (classroom, action) =>
                      _handleClassroomAction(classroom, action, teachers),
                  onRetry: () => setState(_reload),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openSchoolInsights() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerInsightsPage(
          gateway: widget.gateway,
          token: widget.session.token,
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

  Future<void> _handleClassroomAction(
    ClassroomRecord classroom,
    _ClassroomAction action,
    List<TeacherAccount> teachers,
  ) async {
    switch (action) {
      case _ClassroomAction.viewStudents:
        await _openStudents(classroom);
      case _ClassroomAction.addStudent:
        await _showAddStudent(classroom);
      case _ClassroomAction.edit:
        await _showClassroomForm(teachers, classroom: classroom);
      case _ClassroomAction.changeTeacher:
        await _showChangeTeacher(classroom, teachers);
      case _ClassroomAction.delete:
        await _confirmDeleteClassroom(classroom);
    }
  }

  Future<void> _openStudents(ClassroomRecord classroom) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassroomStudentsPage(
          gateway: widget.gateway,
          token: widget.session.token,
          classroom: classroom,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _showAddClassroom(List<TeacherAccount> teachers) async {
    if (teachers.isEmpty) {
      _notify(context.strings.addTeacherBeforeClassroom);
      return;
    }
    await _showClassroomForm(teachers);
  }

  Future<void> _showClassroomForm(
    List<TeacherAccount> teachers, {
    ClassroomRecord? classroom,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ClassroomFormDialog(
        gateway: widget.gateway,
        token: widget.session.token,
        teachers: teachers,
        classroom: classroom,
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _notify(
        classroom == null
            ? context.strings.classroomCreated
            : context.strings.classroomUpdated,
      );
    }
  }

  Future<void> _showChangeTeacher(
    ClassroomRecord classroom,
    List<TeacherAccount> teachers,
  ) async {
    if (teachers.isEmpty) {
      _notify(context.strings.addTeacherBeforeClassroom);
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ChangeTeacherDialog(
        gateway: widget.gateway,
        token: widget.session.token,
        teachers: teachers,
        classroom: classroom,
      ),
    );
    if (changed == true && mounted) {
      setState(_reload);
      _notify(context.strings.teacherReassigned);
    }
  }

  Future<void> _confirmDeleteClassroom(ClassroomRecord classroom) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteClassroom),
        content: Text(strings.deleteClassroomConfirm(classroom.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(strings.deleteClassroom),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.gateway.deleteClassroom(
        token: widget.session.token,
        classroomId: classroom.id,
      );
      if (!mounted) return;
      setState(_reload);
      _notify(strings.classroomDeleted);
    } catch (error) {
      if (!mounted) return;
      _notify(strings.describeError(error));
    }
  }

  Future<void> _showAddStudent(ClassroomRecord classroom) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AddStudentDialog(
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
    required this.teachers,
    required this.onAddClassroom,
    required this.onAction,
    required this.onRetry,
  });

  final Future<List<ClassroomRecord>> future;
  final List<TeacherAccount> teachers;
  final VoidCallback onAddClassroom;
  final void Function(ClassroomRecord classroom, _ClassroomAction action)
  onAction;
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
            SectionToolbar(
              title: Text(
                strings.classroomsCount(snapshot.data?.length ?? 0),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              action: FilledButton.tonalIcon(
                onPressed: onAddClassroom,
                icon: const Icon(Icons.add_business_rounded),
                label: Text(strings.addClassroom),
              ),
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
                  leading: const Icon(Icons.error_outline_rounded),
                  title: Text(strings.describeError(snapshot.error)),
                  trailing: IconButton(
                    tooltip: strings.retry,
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
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
              ResponsiveGrid(
                children: [
                  for (final classroom in snapshot.data ?? [])
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        onTap: () => onAction(
                          classroom,
                          _ClassroomAction.viewStudents,
                        ),
                        leading: const BrandIconBox(icon: Icons.school_rounded),
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
                        trailing: PopupMenuButton<_ClassroomAction>(
                          tooltip: strings.classroomActions,
                          onSelected: (action) => onAction(classroom, action),
                          itemBuilder: (context) {
                            final scheme = Theme.of(context).colorScheme;
                            return [
                              PopupMenuItem(
                                value: _ClassroomAction.viewStudents,
                                child: Text(strings.viewStudents),
                              ),
                              PopupMenuItem(
                                value: _ClassroomAction.addStudent,
                                child: Text(strings.addStudent),
                              ),
                              PopupMenuItem(
                                value: _ClassroomAction.edit,
                                child: Text(strings.editClassroom),
                              ),
                              PopupMenuItem(
                                value: _ClassroomAction.changeTeacher,
                                enabled: teachers.isNotEmpty,
                                child: Text(strings.changeTeacher),
                              ),
                              PopupMenuItem(
                                value: _ClassroomAction.delete,
                                child: Text(
                                  strings.deleteClassroom,
                                  style: TextStyle(color: scheme.error),
                                ),
                              ),
                            ];
                          },
                          icon: const Icon(Icons.more_horiz_rounded),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ClassroomFormDialog extends StatefulWidget {
  const _ClassroomFormDialog({
    required this.gateway,
    required this.token,
    required this.teachers,
    this.classroom,
  });
  final BayyinGateway gateway;
  final String token;
  final List<TeacherAccount> teachers;
  final ClassroomRecord? classroom;

  @override
  State<_ClassroomFormDialog> createState() => _ClassroomFormDialogState();
}

class _ClassroomFormDialogState extends State<_ClassroomFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController grade;
  late final TextEditingController subject;
  late final TextEditingController academicYear;
  late String teacherProfileId;
  bool saving = false;
  Object? error;

  bool get _isEditing => widget.classroom != null;

  @override
  void initState() {
    super.initState();
    final classroom = widget.classroom;
    name = TextEditingController(text: classroom?.name ?? '');
    grade = TextEditingController(text: classroom?.grade ?? '');
    subject = TextEditingController(text: classroom?.subject ?? '');
    academicYear = TextEditingController(
      text: classroom?.academicYear ?? '1448',
    );
    teacherProfileId = _initialTeacherId();
  }

  String _initialTeacherId() {
    final current = widget.classroom?.teacherProfileId ?? '';
    final ids = widget.teachers.map((teacher) => teacher.profileId).toSet();
    if (current.isNotEmpty) return current;
    if (ids.isNotEmpty) return widget.teachers.first.profileId;
    return current;
  }

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
      title: Text(_isEditing ? strings.editClassroom : strings.addClassroom),
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
                  initialValue: teacherProfileId.isEmpty
                      ? null
                      : teacherProfileId,
                  decoration: InputDecoration(
                    labelText: strings.assignedTeacher,
                  ),
                  items: _teacherItems(),
                  onChanged: (value) => teacherProfileId = value!,
                  validator: (value) => value == null || value.isEmpty
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
          child: Text(
            saving
                ? strings.saving
                : (_isEditing ? strings.saveClassroom : strings.createClassroom),
          ),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _teacherItems() {
    final items = <DropdownMenuItem<String>>[
      for (final teacher in widget.teachers)
        DropdownMenuItem(
          value: teacher.profileId,
          child: Text(teacher.displayName),
        ),
    ];
    final currentId = widget.classroom?.teacherProfileId ?? '';
    final currentName = widget.classroom?.teacherName ?? '';
    if (currentId.isNotEmpty &&
        !widget.teachers.any((teacher) => teacher.profileId == currentId)) {
      items.add(
        DropdownMenuItem(
          value: currentId,
          child: Text(currentName.isEmpty ? currentId : currentName),
        ),
      );
    }
    return items;
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
      if (_isEditing) {
        await widget.gateway.updateClassroom(
          token: widget.token,
          classroomId: widget.classroom!.id,
          name: name.text.trim(),
          grade: grade.text.trim(),
          subject: subject.text.trim(),
          academicYear: academicYear.text.trim(),
          teacherProfileId: teacherProfileId,
        );
      } else {
        await widget.gateway.createClassroom(
          token: widget.token,
          name: name.text.trim(),
          grade: grade.text.trim(),
          subject: subject.text.trim(),
          academicYear: academicYear.text.trim(),
          teacherProfileId: teacherProfileId,
        );
      }
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

class _ChangeTeacherDialog extends StatefulWidget {
  const _ChangeTeacherDialog({
    required this.gateway,
    required this.token,
    required this.teachers,
    required this.classroom,
  });

  final BayyinGateway gateway;
  final String token;
  final List<TeacherAccount> teachers;
  final ClassroomRecord classroom;

  @override
  State<_ChangeTeacherDialog> createState() => _ChangeTeacherDialogState();
}

class _ChangeTeacherDialogState extends State<_ChangeTeacherDialog> {
  late String teacherProfileId;
  bool saving = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    final current = widget.classroom.teacherProfileId;
    teacherProfileId = current.isNotEmpty
        ? current
        : widget.teachers.first.profileId;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.changeTeacher),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.classroomTitle(
                widget.classroom.name,
                widget.classroom.subject,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: teacherProfileId,
              decoration: InputDecoration(labelText: strings.assignedTeacher),
              items: [
                for (final teacher in widget.teachers)
                  DropdownMenuItem(
                    value: teacher.profileId,
                    child: Text(teacher.displayName),
                  ),
                if (widget.classroom.teacherProfileId.isNotEmpty &&
                    !widget.teachers.any(
                      (teacher) =>
                          teacher.profileId == widget.classroom.teacherProfileId,
                    ))
                  DropdownMenuItem(
                    value: widget.classroom.teacherProfileId,
                    child: Text(widget.classroom.teacherName),
                  ),
              ],
              onChanged: (value) => teacherProfileId = value!,
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
          child: Text(saving ? strings.saving : strings.save),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.gateway.updateClassroom(
        token: widget.token,
        classroomId: widget.classroom.id,
        name: widget.classroom.name,
        grade: widget.classroom.grade,
        subject: widget.classroom.subject,
        academicYear: widget.classroom.academicYear,
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
            const Icon(Icons.group_add_rounded, size: 48),
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
