import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'create_plan_flow.dart';
import 'custom_plan_builder_screen.dart';
import 'plan_overview_screen.dart';

/// Screen 1 — Planner Home. The entry point for the AI learning planner:
/// a hero prompt to create a plan and a list of the student's existing plans.
class PlannerHomeScreen extends ConsumerWidget {
  const PlannerHomeScreen({super.key});

  /// Starts the AI create-plan wizard, gating free users at
  /// [kFreeLearningPlanLimit] plans behind the paywall.
  static Future<void> startCreate(BuildContext context, WidgetRef ref) async {
    if (!await _ensureCanCreate(context, ref)) return;
    if (!context.mounted) return;
    ref.read(analyticsProvider).plannerCreateStarted('ai');
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Planner: Create'),
        builder: (_) => const CreatePlanFlow(),
      ),
    );
  }

  /// Starts the manual "build your own plan" template, with the same gating.
  static Future<void> startCustom(BuildContext context, WidgetRef ref) async {
    if (!await _ensureCanCreate(context, ref)) return;
    if (!context.mounted) return;
    ref.read(analyticsProvider).plannerCreateStarted('manual');
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Planner: Build Own'),
        builder: (_) => const CustomPlanBuilderScreen(),
      ),
    );
  }

  static Future<bool> _ensureCanCreate(
      BuildContext context, WidgetRef ref) async {
    if (ref.read(canCreatePlanProvider)) return true;
    final unlocked = await showUpgradePrompt(
        context, UpgradeReason.learningPlans,
        used: ref.read(usedPlanSlotsProvider));
    if (!context.mounted) return false;
    return unlocked || ref.read(canCreatePlanProvider);
  }

  /// A small sheet letting the student pick AI generation or the manual builder.
  static void _showCreateChooser(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            ListTile(
              leading: const AiSparkleBadge(size: 40),
              title: const Text('Create with AI'),
              subtitle: const Text('AI breaks it into topics and builds a plan'),
              onTap: () {
                Navigator.pop(ctx);
                startCreate(context, ref);
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.primary),
              ),
              title: const Text('Build your own plan'),
              subtitle: const Text('Add your own topics and time'),
              onTap: () {
                Navigator.pop(ctx);
                startCustom(context, ref);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plans = ref.watch(learningPlansProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            _Header(isPro: isPro)
                .animate()
                .fadeIn(duration: 350.ms)
                .slideY(begin: -0.15, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 20),
            _HeroCard(onCreate: () => startCreate(context, ref))
                .animate()
                .fadeIn(delay: 80.ms, duration: 400.ms)
                .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 12),
            _BuildYourOwnCard(onTap: () => startCustom(context, ref))
                .animate()
                .fadeIn(delay: 130.ms, duration: 400.ms)
                .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 28),
            if (plans.isEmpty)
              const _EmptyState()
                  .animate()
                  .fadeIn(delay: 160.ms, duration: 400.ms)
                  .scaleXY(begin: 0.96, end: 1, curve: Curves.easeOutCubic)
            else ...[
              Row(
                children: [
                  Text('My Plans', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (!isPro)
                    Text('${ref.watch(usedPlanSlotsProvider)}/$kFreeLearningPlanLimit free',
                        style: theme.textTheme.bodySmall)
                  else
                    Text('${plans.length} active',
                        style: theme.textTheme.bodySmall),
                ],
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 14),
              for (var i = 0; i < plans.length; i++) ...[
                _PlanCard(plan: plans[i])
                    .animate()
                    .fadeIn(delay: (180 + i * 70).ms, duration: 380.ms)
                    .slideY(
                        begin: 0.14, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              _NewPlanButton(onTap: () => _showCreateChooser(context, ref))
                  .animate()
                  .fadeIn(delay: (200 + plans.length * 70).ms),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool isPro;
  const _Header({required this.isPro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Planner', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text('Plan smarter. Learn better.',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (isPro)
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 14, color: AppColors.accent),
                SizedBox(width: 4),
                Text('Pro',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ],
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _HeroCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF8B7FEC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow(opacity: 0.22, blur: 26),
      ),
      child: Stack(
        children: [
          // Subtle decorative rings (kept faint, not childish).
          Positioned(
            right: -24,
            top: -30,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            right: 28,
            bottom: -34,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text('AI planner',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Not sure where to start?',
                style:
                    theme.textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                "Tell AI what you want to learn and we'll break it into topics, "
                'estimate the time and build a plan that fits your deadline.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92), height: 1.4),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onCreate,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Create a plan',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact secondary entry point for the manual plan builder.
class _BuildYourOwnCard extends StatelessWidget {
  final VoidCallback onTap;
  const _BuildYourOwnCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: softCard(context, radius: 20),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Build your own plan',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Add your own topics and time to follow',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.textTheme.bodySmall?.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final LearningPlan plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = plan.percent;
    final next = plan.nextIncompleteDay;
    final nextTopic = next?.topicIds
        .map(plan.topicById)
        .firstWhere((t) => t != null && !t.isDone, orElse: () => null);
    final df = DateFormat('d MMM');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            settings: const RouteSettings(name: 'Planner: Overview'),
            builder: (_) => PlanOverviewScreen(planId: plan.id))),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: softCard(context, radius: 22),
          child: Column(
            children: [
              Row(
                children: [
                  _MiniRing(percent: pct),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${pct.toStringAsFixed(0)}% complete · '
                          '${plan.completedTopics} of ${plan.totalTopics} topics',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: theme.textTheme.bodySmall?.color),
                ],
              ),
              const SizedBox(height: 14),
              ThinProgressBar(value: pct / 100, height: 7),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                      nextTopic == null
                          ? Icons.check_circle_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 15,
                      color: nextTopic == null
                          ? AppColors.success
                          : AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nextTopic == null
                          ? 'All topics complete'
                          : 'Next: ${nextTopic.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.flag_outlined,
                      size: 14, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Text(df.format(plan.targetDate),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRing extends StatelessWidget {
  final double percent;
  const _MiniRing({required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (percent / 100).clamp(0, 1)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: 5,
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          Text('${percent.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _NewPlanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewPlanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4), width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('New plan',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: softCard(context, radius: 24),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.lavenderSoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.auto_stories_outlined,
                size: 34, color: AppColors.primary),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true, count: 4))
              .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
          const SizedBox(height: 18),
          Text('No learning plans yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Create your first plan and let AI break it down for you.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
