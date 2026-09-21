import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'topic_detail_screen.dart';

/// Screen 9 — Day View. A focused daily execution view: the day's topics as a
/// simple checklist, with actions to complete or reschedule the day.
class DayViewScreen extends ConsumerWidget {
  final String planId;
  final int dayNumber;
  const DayViewScreen(
      {super.key, required this.planId, required this.dayNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(planId));
    if (plan == null) {
      return const Scaffold(body: Center(child: Text('Plan not found.')));
    }
    DayPlan? day;
    for (final w in plan.weeks) {
      for (final d in w.days) {
        if (d.dayNumber == dayNumber) day = d;
      }
    }
    if (day == null) {
      return const Scaffold(body: Center(child: Text('Day not found.')));
    }
    final topics =
        day.topicIds.map(plan.topicById).whereType<LearningTopic>().toList();
    final doneCount = topics.where((t) => t.isDone).length;
    final estMinutes = topics.fold<int>(0, (s, t) => s + t.estMinutes);
    final df = DateFormat('EEEE, d MMM');
    final controller = ref.read(learningPlansProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Day $dayNumber', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(df.format(day.date), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            // Summary strip
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$doneCount/${topics.length} completed',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: AppColors.primary)),
                        const SizedBox(height: 8),
                        ThinProgressBar(
                          value: topics.isEmpty
                              ? 0
                              : doneCount / topics.length,
                          height: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('~${formatEstMinutes(estMinutes)}',
                          style: theme.textTheme.titleMedium),
                      Text('estimated', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (topics.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Today's topics are part of ${topics.first.unit}.",
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text("Today's topics", style: theme.textTheme.titleMedium),
                const Spacer(),
                if (doneCount > 0)
                  Text(
                    '${formatEstMinutes(_doneMinutes(topics))} done · '
                    '~${formatEstMinutes(_remainingMinutes(topics))} left',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < topics.length; i++) ...[
              _TaskRow(
                topic: topics[i],
                onToggle: () {
                  final t = topics[i];
                  final next = t.isDone
                      ? TopicStatus.notStarted
                      : TopicStatus.completed;
                  controller.setTopicStatus(planId, t.id, next);
                },
                onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: 'Planner: Topic'),
                    builder: (_) => TopicDetailScreen(
                        planId: planId, topicId: topics[i].id))),
              )
                  .animate()
                  .fadeIn(delay: (i * 70).ms, duration: 340.ms)
                  .slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: day.completed ? 'Day completed ✓' : 'Mark Day as Complete',
        trailingIcon: day.completed ? null : Icons.check_rounded,
        onTap: () async {
          final completing = !day!.completed;
          await controller.markDayComplete(planId, dayNumber, completing);
          if (completing) ref.read(analyticsProvider).plannerDayCompleted();
        },
        secondary: OutlinedButton.icon(
          onPressed: () => _reschedule(context, ref),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.event_repeat_rounded, size: 18),
          label: const Text('Reschedule this day'),
        ),
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    // Rescheduling a day recomputes the remaining plan so everything after it
    // shifts consistently. We nudge the whole remaining schedule by one study
    // slot by re-running the planner from today.
    await ref.read(learningPlansProvider.notifier).replan(planId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remaining plan rescheduled.')),
      );
      Navigator.of(context).maybePop();
    }
  }
}

int _doneMinutes(List<LearningTopic> topics) =>
    topics.where((t) => t.isDone).fold(0, (s, t) => s + t.estMinutes);

int _remainingMinutes(List<LearningTopic> topics) =>
    topics.where((t) => !t.isDone).fold(0, (s, t) => s + t.estMinutes);

class _TaskRow extends StatelessWidget {
  final LearningTopic topic;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _TaskRow(
      {required this.topic, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: softCard(context, radius: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TopicTick(status: topic.status, onTap: onToggle),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(topic.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            decoration: topic.isDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: topic.isDone
                                ? theme.textTheme.bodySmall?.color
                                : null,
                          )),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text('~${topic.estMinutes} min',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(width: 8),
                          DifficultyChip(
                              difficulty: topic.difficulty,
                              review: topic.isReview),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: theme.textTheme.bodySmall?.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
