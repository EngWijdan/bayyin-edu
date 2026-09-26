import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/async_states.dart';
import '../widgets/branding.dart';
import '../widgets/language_switcher.dart';
import '../widgets/responsive.dart';
import '../widgets/teacher_home.dart';
import 'classroom_students.dart';
import 'teacher_assessments.dart';

/// The classrooms assigned to the signed-in teacher. Tapping a class opens
/// its roster, where the teacher can add students.
class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({
    super.key,
    required this.gateway,
    required this.picker,
    required this.session,
    this.onLogout,
    required this.onLocaleChanged,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
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
        titleSpacing: 16,
        title: const BayyinBrandLockup(),
        actions: [
          LanguageSwitcher(onLocaleChanged: widget.onLocaleChanged),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: strings.logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 4),
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
            return ResponsivePage(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                TeacherHomeGreeting(name: widget.session.displayName),
                const SizedBox(height: 20),
                TeacherHomeOverview(classrooms: classrooms),
                const SizedBox(height: 22),
                TeacherHomeSectionTitle(title: strings.quickActions),
                const SizedBox(height: 10),
                TeacherHomeActionCard(
                  icon: Icons.assignment_rounded,
                  title: strings.assessments,
                  subtitle: strings.openAssessmentsHint,
                  onTap: () => _openAssessments(classrooms),
                ),
                const SizedBox(height: 22),
                TeacherHomeSectionTitle(title: strings.myClasses),
                const SizedBox(height: 10),
                if (classrooms.isEmpty)
                  EmptyState(
                    icon: Icons.school_rounded,
                    message: strings.noAssignedClasses,
                  )
                else
                  ResponsiveGrid(
                    children: [
                      for (final classroom in classrooms)
                        TeacherClassroomCard(
                          classroom: classroom,
                          onTap: () => _openClassroom(classroom),
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

  Future<void> _openClassroom(ClassroomRecord classroom) async {
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

  /// The loaded classrooms travel with the teacher so the create form can offer
  /// them without a second round trip.
  void _openAssessments(List<ClassroomRecord> classrooms) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeacherAssessmentsPage(
          gateway: widget.gateway,
          picker: widget.picker,
          token: widget.session.token,
          classrooms: classrooms,
        ),
      ),
    );
  }
}
