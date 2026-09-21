import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';

/// Topic Detail — a curriculum map for one topic. Shows WHAT to cover
/// (sections → subtopics) and the completion criteria, never study material.
class TopicDetailScreen extends ConsumerWidget {
  final String planId;
  final String topicId;
  const TopicDetailScreen(
      {super.key, required this.planId, required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(planId));
    final topic = plan?.topicById(topicId);
    if (plan == null || topic == null) {
      return const Scaffold(body: Center(child: Text('Topic not found.')));
    }

    int dayNo = 0;
    for (final w in plan.weeks) {
      for (final d in w.days) {
        if (d.topicIds.contains(topicId)) dayNo = d.dayNumber;
      }
    }
    final pos = plan.positionOf(topicId);
    final controller = ref.read(learningPlansProvider.notifier);
    final sections = topic.sections.isNotEmpty
        ? topic.sections
        : [
            TopicSection(
              title: "What you'll cover",
              minutes: topic.estMinutes,
              points: topic.objectives,
            ),
          ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 170),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Back',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                RoundIconButton(
                  icon: Icons.more_horiz_rounded,
                  semanticLabel: 'Topic options',
                  onTap: () => _topicMenu(context, ref, plan, topic),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(topic.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              dayNo > 0
                  ? 'Day $dayNo · Topic $pos of ${plan.totalTopics}'
                  : 'Topic $pos of ${plan.totalTopics}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            _MetaStrip(topic: topic),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _startFocus(context, ref, topic),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(topic.actualMinutes > 0
                    ? 'Continue focus session · ${topic.actualMinutes}m logged'
                    : 'Start focus session'),
              ),
            ),
            const SizedBox(height: 24),
            Text("What you'll cover", style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('A map of what to study — not the study material itself.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 14),
            _SectionsCard(sections: sections),
            if (topic.completionCriteria.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Completion criteria', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Before marking complete, you should be able to:',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 14),
              _CriteriaCard(criteria: topic.completionCriteria),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Study material is up to you — use your classes, textbooks, '
                    'videos or other resources.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _Actions(
        status: topic.status,
        onComplete: () async {
          await controller.setTopicStatus(
              planId, topicId, TopicStatus.completed);
          ref.read(analyticsProvider).plannerTopicCompleted();
          if (context.mounted) Navigator.of(context).maybePop();
        },
        onLearning: () => controller.setTopicStatus(
            planId, topicId, TopicStatus.learning),
        onNeedMoreTime: () => _needMoreTime(context, ref),
      ),
    );
  }

  Future<void> _needMoreTime(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(learningPlansProvider.notifier);
    await controller.setTopicStatus(planId, topicId, TopicStatus.learning);
    await controller.addTopicTime(planId, topicId, 15);
    await controller.replan(planId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Added time and rebalanced the remaining plan.')),
      );
    }
  }

  Future<void> _startFocus(
      BuildContext context, WidgetRef ref, LearningTopic topic) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FocusTimerSheet(topicTitle: topic.title),
    );
    if (minutes == null || minutes <= 0) return;
    final controller = ref.read(learningPlansProvider.notifier);
    await controller.logTopicTime(planId, topicId, minutes);
    ref.read(analyticsProvider).plannerFocusLogged(minutes);
    if (!context.mounted) return;
    // Offer to recalibrate future estimates from the student's real pace.
    final plan = ref.read(learningPlanByIdProvider(planId));
    final pace = plan?.paceFactor;
    final drift = pace != null && (pace - 1).abs() >= 0.15;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged $minutes min on ${topic.title}.'),
        action: drift
            ? SnackBarAction(
                label: 'Recalibrate',
                onPressed: () async {
                  final f = await controller.recalibrateRemaining(planId);
                  if (f != null) {
                    ref.read(analyticsProvider).plannerRecalibrated(f);
                  }
                  if (context.mounted && f != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Estimates updated to your pace (${(f * 100).round()}%).')),
                    );
                  }
                },
              )
            : null,
      ),
    );
  }

  void _topicMenu(BuildContext context, WidgetRef ref, LearningPlan plan,
      LearningTopic topic) {
    final controller = ref.read(learningPlansProvider.notifier);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _menuItem(ctx, Icons.check_circle_outline_rounded, 'Mark complete',
                () {
              controller.setTopicStatus(planId, topicId, TopicStatus.completed);
            }),
            _menuItem(ctx, Icons.today_rounded, 'Move to another day', () {
              _moveDay(context, ref, plan);
            }),
            _menuItem(ctx, Icons.add_alarm_rounded, 'Add 15 min', () {
              controller.addTopicTime(planId, topicId, 15);
            }),
            _menuItem(ctx, Icons.done_all_rounded, 'Mark as already known', () {
              controller.setTopicStatus(planId, topicId, TopicStatus.completed);
            }),
            _menuItem(ctx, Icons.skip_next_rounded, 'Skip this topic', () async {
              await controller.removeTopic(planId, topicId);
              if (context.mounted) Navigator.of(context).maybePop();
            }, danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? AppColors.danger : AppColors.primary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  Future<void> _moveDay(
      BuildContext context, WidgetRef ref, LearningPlan plan) async {
    final days = [for (final w in plan.weeks) ...w.days];
    final target = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final d in days)
              ListTile(
                leading: const Icon(Icons.calendar_today_rounded,
                    color: AppColors.primary, size: 20),
                title: Text('Day ${d.dayNumber}'),
                onTap: () => Navigator.pop(ctx, d.dayNumber),
              ),
          ],
        ),
      ),
    );
    if (target != null) {
      await ref
          .read(learningPlansProvider.notifier)
          .moveTopicToDay(planId, topicId, target);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to Day $target.')),
        );
      }
    }
  }
}

/// A live count-up focus timer. Returns elapsed whole minutes on finish.
class _FocusTimerSheet extends StatefulWidget {
  final String topicTitle;
  const _FocusTimerSheet({required this.topicTitle});

  @override
  State<_FocusTimerSheet> createState() => _FocusTimerSheetState();
}

class _FocusTimerSheetState extends State<_FocusTimerSheet> {
  Timer? _timer;
  int _seconds = 0;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _running = true;
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _display {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = (_seconds / 60).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Focusing on',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(widget.topicTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 20),
          Text(_display,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  height: 1)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running ? _pause : _start,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(_running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_running ? 'Pause' : 'Resume'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, minutes < 1 ? 1 : minutes),
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  label: const Text('Log & finish',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

class _MetaStrip extends StatelessWidget {
  final LearningTopic topic;
  const _MetaStrip({required this.topic});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, Widget value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 5),
              value,
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: softCard(context, radius: 20),
      child: Row(
        children: [
          cell(
            'Status',
            Text(topic.status.label,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
          ),
          Container(width: 1, height: 34, color: theme.dividerColor),
          const SizedBox(width: 14),
          cell(
            'Estimated',
            Text('~${topic.estMinutes} min',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
          ),
          Container(width: 1, height: 34, color: theme.dividerColor),
          const SizedBox(width: 14),
          cell('Difficulty',
              DifficultyChip(difficulty: topic.difficulty, review: topic.isReview)),
        ],
      ),
    );
  }
}

class _SectionsCard extends StatelessWidget {
  final List<TopicSection> sections;
  const _SectionsCard({required this.sections});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: softCard(context, radius: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++)
            Column(
              children: [
                if (i > 0) Divider(height: 1, color: theme.dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('SECTION ${i + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                fontSize: 11,
                              )),
                          const Spacer(),
                          Text('~${sections[i].minutes} min',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(sections[i].title,
                          style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                      const SizedBox(height: 10),
                      for (final p in sections[i].points)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 7),
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(p,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(height: 1.35)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CriteriaCard extends StatelessWidget {
  final List<String> criteria;
  const _CriteriaCard({required this.criteria});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < criteria.length; i++)
            Padding(
              padding:
                  EdgeInsets.only(bottom: i == criteria.length - 1 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(criteria[i],
                        style:
                            theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final TopicStatus status;
  final VoidCallback onComplete;
  final VoidCallback onLearning;
  final VoidCallback onNeedMoreTime;
  const _Actions({
    required this.status,
    required this.onComplete,
    required this.onLearning,
    required this.onNeedMoreTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = status == TopicStatus.completed;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        done ? AppColors.success : AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onComplete,
                  icon: Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.check_rounded,
                      color: Colors.white),
                  label: Text(done ? 'Completed' : 'Mark as Complete',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onLearning,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Still learning'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onNeedMoreTime,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Need more time'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
