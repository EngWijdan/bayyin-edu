import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/attachment_picker.dart';
import '../services/bayyin_api.dart';
import '../widgets/assessment_card.dart';
import '../widgets/async_states.dart';
import '../widgets/responsive.dart';
import 'assessment_details.dart';

enum ArchiveSort { newest, oldest }

/// Assessments kept aside so a teacher can reuse them in a later year.
class ArchivedAssessmentsPage extends StatefulWidget {
  const ArchivedAssessmentsPage({
    super.key,
    required this.gateway,
    required this.picker,
    required this.token,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final String token;

  @override
  State<ArchivedAssessmentsPage> createState() => _ArchivedAssessmentsPageState();
}

class _ArchivedAssessmentsPageState extends State<ArchivedAssessmentsPage> {
  late Future<List<AssessmentRecord>> _assessments;
  ArchiveSort _sort = ArchiveSort.newest;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _assessments = widget.gateway.fetchAssessments(
      widget.token,
      archived: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.archivedAssessments)),
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
            final assessments = _sorted(snapshot.data ?? []);
            return ResponsivePage(
              children: [
                Text(strings.archivedAssessmentsSubtitle),
                const SizedBox(height: 16),
                if (assessments.isEmpty)
                  const _EmptyArchive()
                else ...[
                  SegmentedButton<ArchiveSort>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ArchiveSort.newest,
                        label: Text(strings.newestFirst),
                      ),
                      ButtonSegment(
                        value: ArchiveSort.oldest,
                        label: Text(strings.oldestFirst),
                      ),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (value) {
                      setState(() => _sort = value.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  ResponsiveGrid(
                    children: [
                      for (final assessment in assessments)
                        SwipeableAssessmentCard(
                          assessment: assessment,
                          showCreatedDate: true,
                          onTap: () => _openDetails(assessment),
                          confirmDelete: () => _confirmDelete(assessment),
                          onSwipeAway: (direction) => _handleSwipe(
                            assessment,
                            direction,
                          ),
                          trailing: IconButton(
                            tooltip: strings.restoreAssessment,
                            onPressed: () => _restore(assessment),
                            icon: const Icon(Icons.unarchive_rounded),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<AssessmentRecord> _sorted(List<AssessmentRecord> assessments) {
    final items = [...assessments];
    items.sort((left, right) {
      final leftDate = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate =
          right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _sort == ArchiveSort.newest
          ? rightDate.compareTo(leftDate)
          : leftDate.compareTo(rightDate);
    });
    return items;
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
    await _restore(assessment);
  }

  Future<void> _restore(AssessmentRecord assessment) async {
    try {
      await widget.gateway.setAssessmentArchived(
        token: widget.token,
        assessmentId: assessment.id,
        archived: false,
      );
      if (!mounted) return;
      setState(_reload);
      _notify(context.strings.assessmentRestored);
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
    if (mounted) setState(_reload);
  }

  void _notify(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              strings.noArchivedAssessments,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              strings.noArchivedAssessmentsSubtitle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
