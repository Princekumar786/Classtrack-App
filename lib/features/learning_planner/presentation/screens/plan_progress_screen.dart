import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'plan_adjustment_screen.dart';
import 'topic_detail_screen.dart';

/// Screen 11 — Progress / Adaptation. Shows how far along the student is,
/// whether they're on track for the deadline, and offers adaptive actions.
class PlanProgressScreen extends ConsumerWidget {
  final String planId;
  const PlanProgressScreen({super.key, required this.planId});

  /// Rough schedule-health check: compares actual completion against the
  /// fraction of the plan window that has elapsed. Returns how many percent
  /// points behind (positive) the student is, or <=0 when on/ahead of track.
  double _behindBy(LearningPlan plan) {
    final total = plan.targetDate.difference(plan.createdAt).inDays;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(plan.createdAt).inDays;
    final expected = (elapsed / total).clamp(0, 1) * 100;
    return expected - plan.percent;
  }

  /// Factual, three-state pace message (behind / on track / ahead).
  String _paceMessage(double behind, LearningPlan plan) {
    if (plan.completedTopics == 0) {
      return 'You haven\'t completed any topics yet. Start with Day 1 to get going.';
    }
    if (behind > 12) {
      return "You're slightly behind your original pace. Adjusting your plan can keep your deadline realistic.";
    }
    if (behind < -12) {
      return "You're ahead of schedule — you could finish early or add more depth.";
    }
    return "You're on track with your schedule.";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(planId));
    if (plan == null) {
      return const Scaffold(body: Center(child: Text('Plan not found.')));
    }
    final df = DateFormat('d MMM');
    final behind = _behindBy(plan);
    final isBehind = behind > 12;

    final completed = plan.topics.where((t) => t.isDone).toList();
    final inProgress = plan.topics
        .where((t) => t.status == TopicStatus.learning)
        .toList();
    final upcoming = plan.topics
        .where((t) => t.status == TopicStatus.notStarted)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.subject,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('${plan.percent.toStringAsFixed(0)}% complete',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: AppColors.primary)),
          const SizedBox(height: 14),
          ThinProgressBar(value: plan.percent / 100, height: 12),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '${plan.totalTopics}',
                  label: 'Total topics',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  value: '${plan.completedTopics}',
                  label: 'Completed',
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  value: '${plan.remainingTopics}',
                  label: 'Remaining',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimeCard(
                    label: 'Time done',
                    value:
                        '~${formatEstMinutes(plan.totalMinutes - plan.remainingMinutes)}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeCard(
                    label: 'Remaining',
                    value: '~${formatEstMinutes(plan.remainingMinutes)}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeCard(
                    label: 'Target', value: df.format(plan.targetDate)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Adaptive AI pace card — factual, not motivational fluff.
          AiInsightCard(message: _paceMessage(behind, plan)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      settings: const RouteSettings(name: 'Planner: Adjust'),
                      builder: (_) => PlanAdjustmentScreen(planId: planId))),
                  child: const Text('Adjust my plan',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
              if (isBehind) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _studyMoreToday(context, ref),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('I can study more'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          Text('Your plan', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _TopicGroup(
            title: 'In progress',
            color: AppColors.warning,
            topics: inProgress,
            plan: plan,
          ),
          _TopicGroup(
            title: 'Completed',
            color: AppColors.success,
            topics: completed,
            plan: plan,
          ),
          _TopicGroup(
            title: 'Upcoming',
            color: AppColors.primary,
            topics: upcoming,
            plan: plan,
          ),
        ],
      ),
    );
  }

  Future<void> _studyMoreToday(BuildContext context, WidgetRef ref) async {
    final plan = ref.read(learningPlanByIdProvider(planId));
    if (plan == null) return;
    // "I can study more today" → bump the daily budget and rebalance so the
    // remaining topics compress into fewer days.
    final boosted = (plan.dailyMinutes * 1.5).round();
    await ref
        .read(learningPlansProvider.notifier)
        .replan(planId, dailyMinutes: boosted);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Great — replanned at ~${formatEstMinutes(boosted)}/day.')),
      );
    }
  }
}

class _TimeCard extends StatelessWidget {
  final String label;
  final String value;
  const _TimeCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: softCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _MiniStat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: color ?? theme.textTheme.titleLarge?.color)),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _TopicGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<LearningTopic> topics;
  final LearningPlan plan;
  const _TopicGroup({
    required this.title,
    required this.color,
    required this.topics,
    required this.plan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (topics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
              const SizedBox(width: 6),
              Text('(${topics.length})', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        for (final t in topics)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: softCard(context, radius: 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: 'Planner: Topic'),
                    builder: (_) =>
                        TopicDetailScreen(planId: plan.id, topicId: t.id))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        t.isDone
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 18,
                        color: t.isDone ? AppColors.success : theme.dividerColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                      ),
                      Text('~${t.estMinutes}m',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
