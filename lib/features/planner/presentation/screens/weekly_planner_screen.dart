import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../domain/weekly_plan.dart';
import '../providers/planner_providers.dart';

/// AI Smart Weekly Planner (Pro): a Gemini-generated study & revision plan
/// built from the user's exams, deadlines and free timetable slots.
class WeeklyPlannerScreen extends ConsumerWidget {
  const WeeklyPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final state = ref.watch(weeklyPlannerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly planner'),
        actions: [
          if (isPro && state.plan != null && !state.loading)
            IconButton(
              tooltip: 'Regenerate',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () =>
                  ref.read(weeklyPlannerControllerProvider.notifier).generate(),
            ),
        ],
      ),
      body: !isPro
          ? _LockedView(
              onUnlock: () async {
                final ok =
                    await showUpgradePrompt(context, UpgradeReason.weeklyPlanner);
                if (ok && context.mounted) {
                  ref.read(weeklyPlannerControllerProvider.notifier).generate();
                }
              },
            )
          : _ProBody(state: state),
      floatingActionButton: (isPro && state.plan != null && !state.loading)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Add to tasks'),
              onPressed: () => _addToTasks(context, ref),
            )
          : null,
    );
  }

  Future<void> _addToTasks(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(weeklyPlannerControllerProvider.notifier).addToTasks();
    messenger.showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'Nothing to add.'
          : 'Added $n study block${n == 1 ? '' : 's'} to your Tasks.'),
    ));
  }
}

class _ProBody extends ConsumerWidget {
  const _ProBody({required this.state});
  final WeeklyPlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Building your week…'),
          ],
        ),
      );
    }
    if (state.error != null) {
      return _MessageView(
        icon: Icons.error_outline_rounded,
        title: 'Couldn\'t build your plan',
        message: state.error!,
        actionLabel: 'Try again',
        onAction: () =>
            ref.read(weeklyPlannerControllerProvider.notifier).generate(),
      );
    }
    final plan = state.plan;
    if (plan == null) {
      return _MessageView(
        icon: Icons.auto_awesome_rounded,
        title: 'Plan your week with AI',
        message:
            'I\'ll turn your exams, deadlines and free time into a focused '
            'study & revision plan for the next 7 days.',
        actionLabel: 'Generate my week',
        onAction: () =>
            ref.read(weeklyPlannerControllerProvider.notifier).generate(),
      );
    }
    return _PlanView(plan: plan);
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({required this.plan});
  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = plan.byDay;
    final days = byDay.keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (plan.summary != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(plan.summary!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(height: 1.35)),
                ),
              ],
            ),
          ),
        for (final day in days) ...[
          _dayHeader(theme, day),
          const SizedBox(height: 8),
          for (final block in byDay[day]!) _blockCard(theme, block),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _dayHeader(ThemeData theme, String ymd) {
    final d = DateTime.tryParse(ymd);
    final label = d != null ? DateUtilsX.prettyFullDate(d) : ymd;
    return Text(label,
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800));
  }

  Widget _blockCard(ThemeData theme, PlanBlock block) {
    final color = _kindColor(block.kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_kindIcon(block.kind), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (block.timeRange.isNotEmpty)
                      Text(block.timeRange,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: color, fontWeight: FontWeight.w800)),
                    if (block.timeRange.isNotEmpty) const SizedBox(width: 8),
                    if (block.subject != null)
                      Flexible(
                        child: Text(block.subject!,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.hintColor)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(block.title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                if (block.reason != null) ...[
                  const SizedBox(height: 2),
                  Text(block.reason!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(PlanBlockKind kind) => switch (kind) {
        PlanBlockKind.study => Icons.menu_book_rounded,
        PlanBlockKind.revision => Icons.repeat_rounded,
        PlanBlockKind.task => Icons.check_circle_outline_rounded,
        PlanBlockKind.exam => Icons.event_note_rounded,
        PlanBlockKind.review => Icons.fact_check_rounded,
        PlanBlockKind.breakTime => Icons.free_breakfast_rounded,
        PlanBlockKind.other => Icons.circle_outlined,
      };

  Color _kindColor(PlanBlockKind kind) => switch (kind) {
        PlanBlockKind.study => AppColors.primary,
        PlanBlockKind.revision => AppColors.info,
        PlanBlockKind.task => AppColors.success,
        PlanBlockKind.exam => AppColors.danger,
        PlanBlockKind.review => AppColors.accent,
        PlanBlockKind.breakTime => AppColors.warning,
        PlanBlockKind.other => AppColors.primary,
      };
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return _MessageView(
      icon: Icons.workspace_premium_rounded,
      title: 'AI Weekly Planner is a Pro feature',
      message:
          'Let AI turn your exams, deadlines and free time into a focused, '
          'realistic study plan for the week — regenerate any time.',
      actionLabel: 'Unlock with Pro',
      onAction: onUnlock,
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor, height: 1.4)),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
