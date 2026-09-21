import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../../domain/learning_plan_generator.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'day_view_screen.dart';
import 'plan_adjustment_screen.dart';
import 'plan_progress_screen.dart';

/// Screen 8 — Plan Overview. The full learning roadmap: summary, progress ring,
/// headline stats and the week-by-week / day-by-day topic breakdown.
class PlanOverviewScreen extends ConsumerWidget {
  final String planId;
  const PlanOverviewScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(planId));
    if (plan == null) {
      return const Scaffold(
        body: Center(child: Text('This plan is no longer available.')),
      );
    }
    final nextDay = plan.nextIncompleteDay;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TopBar(plan: plan)),
            SliverToBoxAdapter(
                child: _SummaryHeader(plan: plan)
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic)),
            SliverToBoxAdapter(
                child: _StatsBlock(plan: plan)
                    .animate()
                    .fadeIn(delay: 90.ms, duration: 380.ms)
                    .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic)),
            if (plan.paused)
              const SliverToBoxAdapter(child: _PausedBanner()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Text('Your Learning Plan',
                        style: theme.textTheme.titleLarge),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          settings:
                              const RouteSettings(name: 'Planner: Progress'),
                          builder: (_) => PlanProgressScreen(planId: planId))),
                      child: Text('Progress',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _WhyOrderCard()),
            for (var wi = 0; wi < plan.weeks.length; wi++)
              SliverToBoxAdapter(
                child: _WeekBlock(plan: plan, week: plan.weeks[wi])
                    .animate()
                    .fadeIn(delay: (120 + wi * 80).ms, duration: 360.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      bottomNavigationBar: nextDay == null
          ? _AllDoneBar()
          : PlannerBottomBar(
              label: 'Start Day ${nextDay.dayNumber}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  settings: const RouteSettings(name: 'Planner: Day'),
                  builder: (_) => DayViewScreen(
                      planId: planId, dayNumber: nextDay.dayNumber))),
            ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final LearningPlan plan;
  const _TopBar({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          Expanded(
            flex: 6,
            child: Text(plan.subject,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Spacer(),
          RoundIconButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: 'Plan options',
            onTap: () => _showMenu(context, ref),
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    final controller = ref.read(learningPlansProvider.notifier);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _item(ctx, Icons.event_rounded, 'Adjust deadline', () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: plan.targetDate.isBefore(now) ? now : plan.targetDate,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 730)),
                );
                if (picked != null) controller.replan(plan.id, targetDate: picked);
              }),
              _item(ctx, Icons.timer_outlined, 'Change daily study time',
                  () => _pickMinutes(context, controller)),
              _item(ctx, Icons.calendar_view_week_rounded, 'Change study days',
                  () => _pickDays(context, controller)),
              _item(ctx, Icons.signal_cellular_alt_rounded, 'Change level',
                  () => _pickLevel(context, controller)),
              _item(ctx, Icons.add_rounded, 'Add a topic',
                  () => _addTopic(context, controller)),
              _item(ctx, Icons.refresh_rounded, 'Rebuild remaining plan',
                  () => controller.replan(plan.id)),
              _item(
                  ctx,
                  plan.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  plan.paused ? 'Resume plan' : 'Pause plan',
                  () => controller.setPaused(plan.id, !plan.paused)),
              _item(ctx, Icons.tune_rounded, 'Adjust my plan', () {
                Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: 'Planner: Adjust'),
                    builder: (_) => PlanAdjustmentScreen(planId: plan.id)));
              }),
              _item(ctx, Icons.insights_rounded, 'View progress', () {
                Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: 'Planner: Progress'),
                    builder: (_) => PlanProgressScreen(planId: plan.id)));
              }),
              _item(ctx, Icons.delete_outline_rounded, 'Delete plan', () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete this plan?'),
                    content: const Text(
                        'Your progress on this plan will be removed. This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await controller.deletePlan(plan.id);
                  ref.read(analyticsProvider).plannerDeleted();
                  if (context.mounted) Navigator.of(context).maybePop();
                }
              }, danger: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext ctx, IconData icon, String label,
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

  Future<void> _pickMinutes(
      BuildContext context, LearningPlannerController controller) async {
    const presets = {30: '30 minutes', 60: '1 hour', 90: '1h 30m', 120: '2 hours'};
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in presets.entries)
              ListTile(
                title: Text(e.value),
                trailing: plan.dailyMinutes == e.key
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (v != null) controller.replan(plan.id, dailyMinutes: v);
  }

  Future<void> _pickDays(
      BuildContext context, LearningPlannerController controller) async {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final selected = {...plan.studyDays};
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Which days will you study?',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 7; i++)
                      GestureDetector(
                        onTap: () => setSheet(() {
                          final day = i + 1;
                          if (selected.contains(day)) {
                            selected.remove(day);
                          } else {
                            selected.add(day);
                          }
                        }),
                        child: Container(
                          width: 40,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected.contains(i + 1)
                                ? AppColors.primary
                                : Theme.of(ctx).cardColor,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                                color: selected.contains(i + 1)
                                    ? AppColors.primary
                                    : Theme.of(ctx).dividerColor),
                          ),
                          child: Text(labels[i],
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: selected.contains(i + 1)
                                      ? Colors.white
                                      : null)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, selected),
                    child: const Text('Update',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      controller.replan(plan.id, studyDays: result);
    }
  }

  Future<void> _pickLevel(
      BuildContext context, LearningPlannerController controller) async {
    final v = await showModalBottomSheet<KnowledgeLevel>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in KnowledgeLevel.values)
              ListTile(
                title: Text(l.title),
                trailing: plan.level == l
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, l),
              ),
          ],
        ),
      ),
    );
    if (v != null) controller.setLevel(plan.id, v);
  }

  Future<void> _addTopic(
      BuildContext context, LearningPlannerController controller) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add a topic'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Topic title'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      controller.addCustomTopic(plan.id, title, 30);
    }
  }
}

class _SummaryHeader extends StatelessWidget {
  final LearningPlan plan;
  const _SummaryHeader({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          ProgressRing(
            percent: plan.percent,
            size: 92,
            strokeWidth: 9,
            color: AppColors.primary,
            centerLabel: '${plan.percent.toStringAsFixed(0)}%',
            subLabel: 'done',
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.subject,
                    style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PillTag(
                      label: plan.level.shortLabel,
                      background: AppColors.lavender,
                      foreground: AppColors.primary,
                    ),
                    PillTag(
                      label: plan.goal.title,
                      background: AppColors.lavenderSoft,
                      foreground: AppColors.primaryDark,
                    ),
                    PillTag(
                      label: plan.program.short,
                      icon: Icons.school_outlined,
                      background: AppColors.lavenderSoft,
                      foreground: AppColors.primaryDark,
                    ),
                    if (plan.region != StudyRegion.global)
                      PillTag(
                        label: plan.region.short,
                        icon: Icons.public_rounded,
                        background: AppColors.lavender,
                        foreground: AppColors.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBlock extends StatelessWidget {
  final LearningPlan plan;
  const _StatsBlock({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('d MMM');
    final perDay = plan.dailyMinutes >= 60 && plan.dailyMinutes % 60 == 0
        ? '${plan.dailyMinutes ~/ 60}h/day'
        : '${plan.dailyMinutes}m/day';
    final totalDays = plan.weeks.fold<int>(0, (s, w) => s + w.days.length);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: softCard(context, radius: 22),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: PlanStat(
                        icon: Icons.list_alt_rounded,
                        value: '${plan.totalTopics}',
                        label: 'Topics')),
                Expanded(
                    child: PlanStat(
                        icon: Icons.schedule_rounded,
                        value: '~${formatEstMinutes(plan.totalMinutes)}',
                        label: 'Est. time')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: PlanStat(
                        icon: Icons.calendar_today_rounded,
                        value: '$totalDays days',
                        label: 'Study days')),
                Expanded(
                    child: PlanStat(
                        icon: Icons.timer_outlined,
                        value: perDay,
                        label: 'Your pace')),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Complete by ${df.format(plan.targetDate)}',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.primary)),
                  const Spacer(),
                  Text('estimate', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekBlock extends ConsumerStatefulWidget {
  final LearningPlan plan;
  final WeekPlan week;
  const _WeekBlock({required this.plan, required this.week});

  @override
  ConsumerState<_WeekBlock> createState() => _WeekBlockState();
}

class _WeekBlockState extends ConsumerState<_WeekBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final week = widget.week;
    final topicCount =
        week.days.fold<int>(0, (s, d) => s + d.topicIds.length);
    final minutes = week.days.fold<int>(
        0,
        (s, d) =>
            s +
            d.topicIds
                .map(plan.topicById)
                .fold<int>(0, (a, t) => a + (t?.estMinutes ?? 0)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('WEEK ${week.weekNumber} — ${week.title.toUpperCase()}',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 13.5, letterSpacing: 0.3)),
                  ),
                  Text('$topicCount topics · ~${formatEstMinutes(minutes)}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: theme.textTheme.bodySmall?.color),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final day in week.days) _DayRow(plan: plan, day: day),
        ],
      ),
    );
  }
}

/// A subtle "why this order" explanation card.
class _WhyOrderCard extends StatefulWidget {
  const _WhyOrderCard();
  @override
  State<_WhyOrderCard> createState() => _WhyOrderCardState();
}

class _WhyOrderCardState extends State<_WhyOrderCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _open = !_open),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 17, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Why this order?',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.primary)),
                  const Spacer(),
                  Icon(_open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary, size: 20),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: 8),
                Text(
                  const LearningPlanGenerator().whyThisOrder(),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text('This plan is paused. Resume it from the menu.',
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final LearningPlan plan;
  final DayPlan day;
  const _DayRow({required this.plan, required this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics =
        day.topicIds.map(plan.topicById).whereType<LearningTopic>().toList();
    final allDone = topics.isNotEmpty && topics.every((t) => t.isDone);
    final df = DateFormat('EEE, d MMM');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: softCard(context, radius: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: 'Planner: Day'),
              builder: (_) =>
                  DayViewScreen(planId: plan.id, dayNumber: day.dayNumber))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: allDone
                            ? AppColors.success.withValues(alpha: 0.14)
                            : AppColors.lavenderSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (allDone) ...[
                            const Icon(Icons.check_circle_rounded,
                                size: 14, color: AppColors.success),
                            const SizedBox(width: 5),
                          ],
                          Text('Day ${day.dayNumber}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: allDone
                                    ? AppColors.success
                                    : AppColors.primary,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(df.format(day.date),
                        style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: theme.textTheme.bodySmall?.color),
                  ],
                ),
                const SizedBox(height: 10),
                for (final t in topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          t.isDone
                              ? Icons.check_circle_rounded
                              : (t.isReview
                                  ? Icons.replay_circle_filled_rounded
                                  : Icons.circle_outlined),
                          size: 17,
                          color: t.isDone
                              ? AppColors.success
                              : (t.isReview
                                  ? AppColors.accent
                                  : difficultyColor(t.difficulty)
                                      .withValues(alpha: 0.6)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                decoration: t.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: t.isDone
                                    ? theme.textTheme.bodySmall?.color
                                    : null,
                              )),
                        ),
                        const SizedBox(width: 8),
                        if (t.isReview)
                          const DifficultyChip(
                              difficulty: TopicDifficulty.easy, review: true)
                        else
                          Text('~${t.estMinutes} min',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDoneBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.celebration_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              Text('Plan complete — great work!',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.success)),
            ],
          ),
        ),
      ),
    );
  }
}
