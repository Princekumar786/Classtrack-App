import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';

/// The adjustment options the student can choose.
enum _Adjust {
  moreToday,
  lessThisWeek,
  moveDeadline,
  knowSome,
  skipSome,
  rebuild,
}

extension _AdjustX on _Adjust {
  String get title {
    switch (this) {
      case _Adjust.moreToday:
        return 'I have more time';
      case _Adjust.lessThisWeek:
        return 'I have less time';
      case _Adjust.moveDeadline:
        return 'Change my deadline';
      case _Adjust.knowSome:
        return 'I already know some topics';
      case _Adjust.skipSome:
        return 'I want to skip some topics';
      case _Adjust.rebuild:
        return 'Rebuild the remaining plan';
    }
  }

  String get subtitle {
    switch (this) {
      case _Adjust.moreToday:
        return 'Study more per day and finish sooner.';
      case _Adjust.lessThisWeek:
        return 'Ease the pace — spread topics further out.';
      case _Adjust.moveDeadline:
        return 'Pick a new target completion date.';
      case _Adjust.knowSome:
        return 'Mark topics complete and shorten the plan.';
      case _Adjust.skipSome:
        return 'Remove topics you don\'t need.';
      case _Adjust.rebuild:
        return 'Recreate the schedule for what\'s left.';
    }
  }

  IconData get icon {
    switch (this) {
      case _Adjust.moreToday:
        return Icons.bolt_rounded;
      case _Adjust.lessThisWeek:
        return Icons.spa_outlined;
      case _Adjust.moveDeadline:
        return Icons.event_rounded;
      case _Adjust.knowSome:
        return Icons.done_all_rounded;
      case _Adjust.skipSome:
        return Icons.skip_next_rounded;
      case _Adjust.rebuild:
        return Icons.refresh_rounded;
    }
  }
}

/// Screen 12 — Plan Adjustment. Lets the student pick an adaptation, previews
/// the new estimated completion, then rebuilds the remaining schedule.
class PlanAdjustmentScreen extends ConsumerStatefulWidget {
  final String planId;
  const PlanAdjustmentScreen({super.key, required this.planId});

  @override
  ConsumerState<PlanAdjustmentScreen> createState() =>
      _PlanAdjustmentScreenState();
}

class _PlanAdjustmentScreenState extends ConsumerState<PlanAdjustmentScreen> {
  _Adjust _selected = _Adjust.moreToday;
  DateTime? _newDeadline;

  /// The daily-minutes the current selection would set (for pace comparison).
  int _updatedMinutes(LearningPlan plan) {
    switch (_selected) {
      case _Adjust.moreToday:
        return (plan.dailyMinutes * 1.5).round();
      case _Adjust.lessThisWeek:
        return (plan.dailyMinutes * 0.6).round().clamp(15, 100000);
      default:
        return plan.dailyMinutes;
    }
  }

  /// Computes the projected finish date for the current selection without
  /// mutating the stored plan (a dry-run of the generator).
  DateTime _projectedFinish(LearningPlan plan) {
    const generator = LearningPlanGenerator();
    final minutes = _updatedMinutes(plan);
    final Set<int> days = plan.studyDays;
    final DateTime target =
        _selected == _Adjust.moveDeadline ? (_newDeadline ?? plan.targetDate) : plan.targetDate;
    final preview = generator.replan(plan,
        dailyMinutes: minutes, studyDays: days, targetDate: target);
    DateTime last = DateTime.now();
    for (final w in preview.weeks) {
      for (final d in w.days) {
        if (d.date.isAfter(last)) last = d.date;
      }
    }
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(widget.planId));
    if (plan == null) {
      return const Scaffold(body: Center(child: Text('Plan not found.')));
    }
    final df = DateFormat('EEE, d MMM');
    final projected = _projectedFinish(plan);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Adjust your plan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lavenderSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You have ${plan.remainingTopics} topics remaining and '
                    '~${formatEstMinutes(plan.remainingMinutes)} estimated study time.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('What changed?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final a in _Adjust.values) ...[
            SelectableOptionCard(
              icon: a.icon,
              title: a.title,
              subtitle: a.subtitle,
              selected: _selected == a,
              onTap: () async {
                setState(() => _selected = a);
                if (a == _Adjust.moveDeadline) {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _newDeadline ?? plan.targetDate,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => _newDeadline = picked);
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          // Current vs updated pace + new completion date.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: softCard(context, radius: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current plan', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 3),
                          Text(_pace(plan.dailyMinutes),
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded,
                        size: 18, color: theme.textTheme.bodySmall?.color),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Updated plan',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 3),
                          Text(_pace(_updatedMinutes(plan)),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: theme.dividerColor),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.event_available_rounded,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('New estimated completion',
                        style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Text(df.format(projected),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: 'Update Plan',
        trailingIcon: Icons.check_rounded,
        onTap: () => _apply(context, plan),
      ),
    );
  }

  Future<void> _apply(BuildContext context, LearningPlan plan) async {
    final controller = ref.read(learningPlansProvider.notifier);
    switch (_selected) {
      case _Adjust.moreToday:
        await controller.replan(widget.planId,
            dailyMinutes: (plan.dailyMinutes * 1.5).round());
        break;
      case _Adjust.lessThisWeek:
        await controller.replan(widget.planId,
            dailyMinutes:
                (plan.dailyMinutes * 0.6).round().clamp(15, 100000));
        break;
      case _Adjust.moveDeadline:
        await controller.replan(widget.planId,
            targetDate: _newDeadline ?? plan.targetDate);
        break;
      case _Adjust.knowSome:
        if (context.mounted) {
          await _pickKnownTopics(context, plan, controller, skip: false);
        }
        break;
      case _Adjust.skipSome:
        if (context.mounted) {
          await _pickKnownTopics(context, plan, controller, skip: true);
        }
        break;
      case _Adjust.rebuild:
        await controller.replan(widget.planId);
        break;
    }
    if (context.mounted) {
      ref.read(analyticsProvider).plannerAdjusted(_selected.name);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your plan has been updated.')),
      );
      Navigator.of(context).maybePop();
    }
  }

  String _pace(int minutes) => minutes >= 60 && minutes % 60 == 0
      ? '${minutes ~/ 60}h/day'
      : minutes >= 60
          ? '${minutes ~/ 60}h ${minutes % 60}m/day'
          : '${minutes}m/day';

  Future<void> _pickKnownTopics(
    BuildContext context,
    LearningPlan plan,
    LearningPlannerController controller, {
    required bool skip,
  }) async {
    final selected = <String>{};
    final open = plan.topics.where((t) => !t.isDone).toList();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skip
                    ? 'Which topics do you want to skip?'
                    : 'Which topics do you already know?',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                    skip
                        ? 'These will be removed from your plan.'
                        : 'These will be marked complete and removed from your schedule.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in open)
                        CheckboxListTile(
                          value: selected.contains(t.id),
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.title,
                              style: theme.textTheme.bodyMedium),
                          onChanged: (v) => setSheet(() {
                            if (v == true) {
                              selected.add(t.id);
                            } else {
                              selected.remove(t.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx, selected),
                    child: const Text('Apply',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      for (final id in result) {
        if (skip) {
          await controller.removeTopic(widget.planId, id);
        } else {
          await controller.setTopicStatus(
              widget.planId, id, TopicStatus.completed);
        }
      }
      await controller.replan(widget.planId);
    }
  }
}
