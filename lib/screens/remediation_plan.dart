import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/bayyin_api.dart';
import '../theme/app_layout.dart';
import '../widgets/branding.dart';
import '../widgets/responsive.dart';

/// Renders one stored plan. Regenerating replaces the same record.
class RemediationPlanPage extends StatefulWidget {
  const RemediationPlanPage({
    super.key,
    required this.gateway,
    required this.token,
    required this.assessmentId,
    required this.plan,
  });

  final BayyinGateway gateway;
  final String token;
  final String assessmentId;
  final RemediationPlanRecord plan;

  @override
  State<RemediationPlanPage> createState() => _RemediationPlanPageState();
}

class _RemediationPlanPageState extends State<RemediationPlanPage> {
  late RemediationPlanRecord _plan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).pop(_plan),
        ),
        title: Text(strings.groupTitle(_plan.group)),
        actions: [
          TextButton(
            onPressed: _busy ? null : _regenerate,
            child: Text(_busy ? strings.generatingPlan : strings.regeneratePlan),
          ),
        ],
      ),
      body: ResponsivePage(
        maxWidth: AppLayout.compactMaxWidth,
        children: [
          AiGeneratedBadge(label: strings.aiGeneratedPlan),
          const SizedBox(height: 12),
          Text(
            _plan.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(_plan.summary),
          const SizedBox(height: 20),
          Text(
            strings.objectives,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ..._plan.objectives.map(
            (item) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 6),
              child: Text('• $item'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.activities,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
              ..._plan.activities.map(
                (activity) => Card(
                  child: ListTile(
                    title: Text(
                      activity.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(activity.description),
                    trailing: activity.durationMinutes == null
                        ? null
                        : Text(
                            strings.activityDuration(activity.durationMinutes!),
                          ),
                  ),
                ),
              ),
          const SizedBox(height: 16),
          Text(
            strings.teacherGuidance,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(_plan.teacherGuidance),
        ],
      ),
    );
  }

  Future<void> _regenerate() async {
    setState(() => _busy = true);
    try {
      final result = await widget.gateway.generateRemediationPlan(
        token: widget.token,
        assessmentId: widget.assessmentId,
        group: _plan.group,
        locale: context.strings.evaluationLocale,
      );
      final plan = result.plan;
      if (!mounted) return;
      if (plan == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _plan = plan;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.describeError(error))),
      );
    }
  }
}
