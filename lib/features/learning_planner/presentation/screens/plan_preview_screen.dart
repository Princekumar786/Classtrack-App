import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'plan_adjustment_screen.dart';
import 'plan_overview_screen.dart';

/// The concise "Your plan is ready" preview shown after generation and before
/// the full overview — summary + curriculum structure so the student can
/// commit with confidence (or adjust first).
class PlanPreviewScreen extends ConsumerWidget {
  final String planId;
  const PlanPreviewScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(learningPlanByIdProvider(planId));
    if (plan == null) {
      return const Scaffold(body: Center(child: Text('Plan not found.')));
    }
    final df = DateFormat('d MMM');
    final perDay = plan.dailyMinutes >= 60 && plan.dailyMinutes % 60 == 0
        ? '${plan.dailyMinutes ~/ 60}h/day'
        : '${plan.dailyMinutes}m/day';
    final studyDays = plan.studyDays.length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 130),
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 22),
                const SizedBox(width: 8),
                Text('Your plan is ready', style: theme.textTheme.titleMedium),
              ],
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 14),
            Text(plan.subject, style: theme.textTheme.headlineMedium)
                .animate()
                .fadeIn(delay: 60.ms)
                .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillTag(
                    label: plan.level.shortLabel,
                    background: AppColors.lavender,
                    foreground: AppColors.primary),
                PillTag(
                    label: plan.program.title,
                    icon: Icons.school_outlined,
                    background: AppColors.lavenderSoft,
                    foreground: AppColors.primaryDark),
                if (plan.region != StudyRegion.global)
                  PillTag(
                      label: plan.region.label,
                      icon: Icons.public_rounded,
                      background: AppColors.lavender,
                      foreground: AppColors.primary),
              ],
            ),
            const SizedBox(height: 20),
            _SummaryRow(
              stats: [
                ('${plan.totalTopics}', 'topics'),
                ('~${formatEstMinutes(plan.totalMinutes)}', 'est. time'),
                ('$studyDays', 'study days'),
                (perDay, 'pace'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Complete by ${df.format(plan.targetDate)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15, color: AppColors.primary)),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text('Curriculum structure', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _UnitList(plan: plan),
            const SizedBox(height: 18),
            const AiInsightCard(
              message:
                  'This plan is estimated from your selected level, goal, '
                  'syllabus and available study time. You can adjust it any time.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: PlannerBottomBar(
        label: 'Looks good',
        trailingIcon: Icons.arrow_forward_rounded,
        onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
            settings: const RouteSettings(name: 'Planner: Overview'),
            builder: (_) => PlanOverviewScreen(planId: planId))),
        secondary: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: 'Planner: Adjust'),
              builder: (_) => PlanAdjustmentScreen(planId: planId))),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Adjust plan'),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<(String, String)> stats;
  const _SummaryRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: softCard(context, radius: 20),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(stats[i].$1,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(stats[i].$2,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            if (i != stats.length - 1)
              Container(
                width: 1,
                height: 34,
                color: theme.dividerColor,
              ),
          ],
        ],
      ),
    );
  }
}

class _UnitList extends StatelessWidget {
  final LearningPlan plan;
  const _UnitList({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = plan.units;
    return Container(
      decoration: softCard(context, radius: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < units.length; i++)
            Column(
              children: [
                if (i > 0) Divider(height: 1, color: theme.dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('${i + 1}',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: AppColors.primary)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(units[i].title.toUpperCase(),
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 14, letterSpacing: 0.3)),
                      ),
                      Text(
                        '${units[i].topics.length} topics · ~${formatEstMinutes(units[i].totalMinutes)}',
                        style: theme.textTheme.bodySmall,
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
