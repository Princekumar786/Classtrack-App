import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../exams/presentation/screens/exams_screen.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../../tasks/domain/task_item.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tasks/presentation/screens/tasks_screen.dart';
import '../../domain/learning_plan.dart';
import '../../domain/planner_insights.dart';
import '../providers/learning_planner_providers.dart';
import '../widgets/planner_widgets.dart';
import 'create_plan_flow.dart';
import 'custom_plan_builder_screen.dart';
import 'day_view_screen.dart';
import 'plan_overview_screen.dart';

/// Planner Home — the student's daily command centre.
///
/// Answers three questions in order of urgency:
///  1. "What should I study right now?"  → Today's focus card (catch-up aware).
///  2. "What's on today / next?"         → today's agenda (study sessions,
///     tasks due and exams) and a short "Coming up" list.
///  3. "Am I on track?"                  → today's stats, exam countdowns and
///     plan cards with an On track / Behind / Paused / Completed status.
class PlannerHomeScreen extends ConsumerStatefulWidget {
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
  static void showCreateChooser(BuildContext context, WidgetRef ref) {
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
              subtitle:
                  const Text('AI breaks it into topics and builds a plan'),
              onTap: () {
                Navigator.pop(ctx);
                startCreate(context, ref);
              },
            ),
            ListTile(
              leading: const _IconTile(
                  icon: Icons.edit_note_rounded, color: AppColors.primary),
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
  ConsumerState<PlannerHomeScreen> createState() => _PlannerHomeScreenState();
}

class _PlannerHomeScreenState extends ConsumerState<PlannerHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(learningPlansProvider);
    final isPro = ref.watch(isProProvider);
    final focus = ref.watch(todayFocusProvider);
    final upcomingExams = ref.watch(upcomingExamsProvider);
    final now = DateTime.now();

    // Plans that need attention first, finished ones last.
    final sortedPlans = [...plans]..sort((a, b) {
        final h = planHealth(a, now)
            .sortOrder
            .compareTo(planHealth(b, now).sortOrder);
        return h != 0 ? h : a.targetDate.compareTo(b.targetDate);
      });

    final children = <Widget>[
      _Header(
        isPro: isPro,
        onNew: () => PlannerHomeScreen.showCreateChooser(context, ref),
      ),
      const SizedBox(height: 20),
      if (plans.isEmpty) ...[
        _HeroCard(onCreate: () => PlannerHomeScreen.startCreate(context, ref)),
        const SizedBox(height: 12),
        _BuildYourOwnCard(
            onTap: () => PlannerHomeScreen.startCustom(context, ref)),
        const SizedBox(height: 24),
        const _HowItWorks(),
      ] else ...[
        if (focus != null)
          _FocusCard(plan: focus.plan, day: focus.day)
        else
          const _AllCaughtUpCard(),
        const SizedBox(height: 16),
        _TodayStats(plans: plans, now: now),
      ],
      const SizedBox(height: 28),
      // Today only — no week strip / week navigation.
      _Agenda(date: dateOnly(now), plans: plans),
      if (plans.isNotEmpty) ...[
        const SizedBox(height: 28),
        _ComingUp(sessions: upcomingSessions(plans, now)),
      ],
      if (upcomingExams.isNotEmpty) ...[
        const SizedBox(height: 28),
        _ExamsSection(exams: upcomingExams.take(3).toList()),
      ],
      if (plans.isNotEmpty) ...[
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
                child: Text('My plans',
                    style: Theme.of(context).textTheme.titleLarge)),
            Text(
              isPro
                  ? '${plans.length} plan${plans.length == 1 ? '' : 's'}'
                  : '${ref.watch(usedPlanSlotsProvider)}/$kFreeLearningPlanLimit free',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final p in sortedPlans) ...[
          _PlanCard(plan: p, health: planHealth(p, now)),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        _NewPlanButton(
            onTap: () => PlannerHomeScreen.showCreateChooser(context, ref)),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          itemCount: children.length,
          itemBuilder: (_, i) => children[i].listEntrance(i, maxAnimated: 10),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isPro;
  final VoidCallback onNew;
  const _Header({required this.isPro, required this.onNew});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('EEEE, d MMMM').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text('Planner', style: theme.textTheme.headlineSmall),
              ),
            ],
          ),
        ),
        if (isPro) ...[
          const _ProChip(),
          const SizedBox(width: 10),
        ],
        RoundIconButton(
          icon: Icons.add_rounded,
          semanticLabel: 'New plan',
          background: AppColors.primary,
          iconColor: Colors.white,
          onTap: onNew,
        ),
      ],
    );
  }
}

class _ProChip extends StatelessWidget {
  const _ProChip();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

// ── Today's focus ─────────────────────────────────────────────────────────

class _FocusCard extends ConsumerWidget {
  final LearningPlan plan;
  final DayPlan day;
  const _FocusCard({required this.plan, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final dayDate = dateOnly(day.date);
    final overdue = dayDate.isBefore(today);
    final upcoming = dayDate.isAfter(today);
    final topics =
        day.topicIds.map(plan.topicById).whereType<LearningTopic>().toList();
    final done = topics.where((t) => t.isDone).length;
    final mins = openMinutes((plan: plan, day: day));
    final controller = ref.read(learningPlansProvider.notifier);

    final eyebrow = overdue
        ? 'CATCH UP · ${DateFormat('EEE d MMM').format(day.date)}'
        : upcoming
            ? 'UP NEXT · ${DateFormat('EEE d MMM').format(day.date)}'
            : "TODAY'S FOCUS";

    void openDay() => Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'Planner: Day'),
        builder: (_) =>
            DayViewScreen(planId: plan.id, dayNumber: day.dayNumber)));

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: overdue
              ? const [Color(0xFFE8566B), Color(0xFFF08A5D)]
              : const [Color(0xFF6C5CE7), Color(0xFF8B7FEC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.softShadow(opacity: 0.22, blur: 26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(eyebrow,
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85))),
              ),
              _GlassPill(
                  icon: Icons.schedule_rounded,
                  label: '~${formatEstMinutes(mins)}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 2),
          Text(
            'Day ${day.dayNumber} · $done of ${topics.length} topics done',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final t in topics.take(3))
                  _FocusTopicRow(
                    topic: t,
                    onToggle: () {
                      HapticFeedback.lightImpact();
                      final next = t.isDone
                          ? TopicStatus.notStarted
                          : TopicStatus.completed;
                      controller.setTopicStatus(plan.id, t.id, next);
                      if (next == TopicStatus.completed) {
                        ref.read(analyticsProvider).plannerTopicCompleted();
                      }
                    },
                  ),
                if (topics.length > 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('+${topics.length - 3} more',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85))),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor:
                          overdue ? const Color(0xFFE8566B) : AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: openDay,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(done == 0 ? 'Start session' : 'Continue',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Mark day as done',
                child: SizedBox(
                  height: 46,
                  width: 46,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: Colors.white,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await controller.markDayComplete(
                          plan.id, day.dayNumber, true);
                      ref.read(analyticsProvider).plannerDayCompleted();
                      if (context.mounted) {
                        showQuickFeedback(context, 'Day ${day.dayNumber} done. Nice work!');
                      }
                    },
                    child: const Icon(Icons.done_all_rounded,
                        semanticLabel: 'Mark day as done'),
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

class _FocusTopicRow extends StatelessWidget {
  final LearningTopic topic;
  final VoidCallback onToggle;
  const _FocusTopicRow({required this.topic, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: topic.isDone,
      label: topic.title,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  topic.isDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(topic.isDone),
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white
                        .withValues(alpha: topic.isDone ? 0.7 : 1),
                    decoration:
                        topic.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                  topic.subtopicTotal > 0 && !topic.isDone
                      ? '${topic.subtopicsDone}/${topic.subtopicTotal}'
                      : '~${formatEstMinutes(topic.estMinutes)}',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: topic.subtopicsDone > 0 && !topic.isDone
                          ? FontWeight.w700
                          : null,
                      color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GlassPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _AllCaughtUpCard extends StatelessWidget {
  const _AllCaughtUpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context, radius: 22),
      child: Row(
        children: [
          const _IconTile(
              icon: Icons.celebration_rounded, color: AppColors.success),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're all caught up", style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('Nothing due right now. Start a new plan or take a break.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Today's stats ─────────────────────────────────────────────────────────

class _TodayStats extends StatelessWidget {
  final List<LearningPlan> plans;
  final DateTime now;
  const _TodayStats({required this.plans, required this.now});

  @override
  Widget build(BuildContext context) {
    final today = todayLoad(plans, now);
    final topicsDone = plans.fold(0, (s, p) => s + p.completedTopics);
    final subsDone = plans.fold<int>(
        0, (s, p) => s + p.topics.fold<int>(0, (a, t) => a + t.subtopicsDone));

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.today_rounded,
            color: AppColors.primary,
            value: today.planned == 0 ? '—' : '${today.done}/${today.planned}',
            label: 'Today',
            progress: today.planned == 0 ? null : today.done / today.planned,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.hourglass_bottom_rounded,
            color: AppColors.info,
            value: today.planned == 0
                ? formatEstMinutes(remainingMinutesAll(plans))
                : formatEstMinutes(today.minutesLeft),
            label: today.planned == 0 ? 'Study left' : 'Left today',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.task_alt_rounded,
            color: AppColors.success,
            value: '$topicsDone',
            label: subsDone > 0 ? 'Topics · $subsDone subs' : 'Topics done',
          ),
        ),
      ],
    );
  }
}

// ── Coming up ─────────────────────────────────────────────────────────────

/// The next few study days after today (across plans) as a simple timeline.
class _ComingUp extends StatelessWidget {
  final List<PlanSession> sessions;
  const _ComingUp({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coming up', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: softCard(context, radius: 18),
            child: Text('Nothing scheduled after today.',
                style: theme.textTheme.bodyMedium),
          )
        else
          Container(
            decoration: softCard(context, radius: 20),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 70, color: theme.dividerColor),
                    _ComingUpRow(session: sessions[i], today: today),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ComingUpRow extends StatelessWidget {
  final PlanSession session;
  final DateTime today;
  const _ComingUpRow({required this.session, required this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = session.day;
    final date = dateOnly(d.date);
    final tomorrow = sameDay(date, today.add(const Duration(days: 1)));
    final topics =
        d.topicIds.map(session.plan.topicById).whereType<LearningTopic>().toList();
    final mins = openMinutes(session);
    final when = tomorrow ? 'Tomorrow' : DateFormat('EEEE').format(d.date);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: 'Planner: Day'),
          builder: (_) =>
              DayViewScreen(planId: session.plan.id, dayNumber: d.dayNumber))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: tomorrow ? AppColors.primary : AppColors.lavenderSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(DateFormat('MMM').format(d.date).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tomorrow ? Colors.white70 : AppColors.primary)),
                  Text('${d.date.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: tomorrow ? Colors.white : AppColors.primary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.plan.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '$when · ${topics.length} topic${topics.length == 1 ? '' : 's'}'
                    ' · ~${formatEstMinutes(mins)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (topics.isNotEmpty)
                    Text(topics.map((t) => t.title).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.primary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final double? progress;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: softCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5)),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ThinProgressBar(value: progress!, height: 4, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Today's agenda ────────────────────────────────────────────────────────

class _Agenda extends ConsumerWidget {
  final DateTime date;
  final List<LearningPlan> plans;
  const _Agenda({required this.date, required this.plans});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = sessionsOn(plans, date);
    final tasks = ref.watch(tasksForDayProvider(date));
    final exams = (ref.watch(examsStreamProvider).valueOrNull ?? const <Exam>[])
        .where((e) => sameDay(e.date, date))
        .toList();
    final today = dateOnly(DateTime.now());
    final label = sameDay(date, today)
        ? 'Today'
        : sameDay(date, today.add(const Duration(days: 1)))
            ? 'Tomorrow'
            : DateFormat('EEEE, d MMM').format(date);

    final rows = <Widget>[
      for (final e in exams)
        _AgendaRow(
          icon: Icons.school_rounded,
          color: AppColors.coral,
          title: e.title,
          subtitle: [
            'Exam · ${DateFormat.jm().format(e.date)}',
            if (e.room != null && e.room!.trim().isNotEmpty) e.room!,
          ].join(' · '),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Exams'), builder: (_) => const ExamsScreen())),
        ),
      for (final s in sessions)
        _AgendaRow(
          icon: Icons.menu_book_rounded,
          color: AppColors.primary,
          title: s.plan.subject,
          subtitle:
              'Day ${s.day.dayNumber} · ${s.day.topicIds.length} topic${s.day.topicIds.length == 1 ? '' : 's'} · ~${formatEstMinutes(s.day.topicIds.map(s.plan.topicById).whereType<LearningTopic>().fold(0, (a, t) => a + t.estMinutes))}',
          done: isDayDone(s.plan, s.day),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              settings: const RouteSettings(name: 'Planner: Day'),
              builder: (_) => DayViewScreen(
                  planId: s.plan.id, dayNumber: s.day.dayNumber))),
        ),
      for (final t in tasks)
        _AgendaRow(
          icon: t.type.icon,
          color: t.done ? AppColors.success : t.priority.color,
          title: t.title,
          subtitle: '${t.type.label} · ${t.priority.label} priority',
          done: t.done,
          onToggle: () {
            HapticFeedback.lightImpact();
            ref.read(taskControllerProvider).toggle(t);
          },
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(settings: const RouteSettings(name: 'Tasks'), builder: (_) => const TasksScreen())),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.textTheme.bodySmall?.color)),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: softCard(context, radius: 18, shadow: false)
                .copyWith(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.12))),
            child: Column(
              children: [
                Icon(Icons.wb_sunny_outlined,
                    color: AppColors.primary.withValues(alpha: 0.7)),
                const SizedBox(height: 8),
                Text('Free day', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('No study sessions, tasks or exams.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          )
        else
          Container(
            decoration: softCard(context, radius: 18),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        indent: 64,
                        color: theme.dividerColor.withValues(alpha: 0.5)),
                  rows[i],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  const _AgendaRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.done = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            _IconTile(icon: icon, color: color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          color: done
                              ? theme.textTheme.bodySmall?.color
                              : null)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (onToggle != null)
              IconButton(
                tooltip: done ? 'Mark as not done' : 'Mark as done',
                onPressed: onToggle,
                icon: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? AppColors.success : theme.dividerColor,
                ),
              )
            else if (done)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.check_circle_rounded,
                    color: AppColors.success, semanticLabel: 'Done'),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.chevron_right_rounded,
                    color: theme.textTheme.bodySmall?.color),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Upcoming exams ────────────────────────────────────────────────────────

class _ExamsSection extends ConsumerWidget {
  final List<Exam> exams;
  const _ExamsSection({required this.exams});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Upcoming exams',
          actionLabel: 'See all',
          onAction: () => Navigator.of(context)
              .push(MaterialPageRoute(settings: const RouteSettings(name: 'Exams'), builder: (_) => const ExamsScreen())),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ExamCard(
              exam: exams[i],
              onPlan: () => PlannerHomeScreen.startCreate(context, ref),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  final Exam exam;
  final VoidCallback onPlan;
  const _ExamCard({required this.exam, required this.onPlan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = exam.daysUntil;
    final urgent = d <= 3;
    final color = urgent ? AppColors.danger : AppColors.coral;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: softCard(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  d == 0
                      ? 'Today'
                      : d == 1
                          ? 'Tomorrow'
                          : '$d days',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              Text(DateFormat('d MMM').format(exam.date),
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(exam.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall),
          const Spacer(),
          if (exam.hasTopics) ...[
            Row(
              children: [
                Expanded(
                    child: ThinProgressBar(
                        value: exam.readiness,
                        height: 5,
                        color: AppColors.success)),
                const SizedBox(width: 8),
                Text('${(exam.readiness * 100).round()}% ready',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ] else
            InkWell(
              onTap: onPlan,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text('Make a study plan',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Plans ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final LearningPlan plan;
  final PlanHealth health;
  const _PlanCard({required this.plan, required this.health});

  Color get _healthColor => switch (health) {
        PlanHealth.onTrack => AppColors.success,
        PlanHealth.behind => AppColors.danger,
        PlanHealth.paused => AppColors.cancelled,
        PlanHealth.done => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = plan.percent;
    final next = plan.nextIncompleteDay;
    final nextTopic = next?.topicIds
        .map(plan.topicById)
        .firstWhere((t) => t != null && !t.isDone, orElse: () => null);
    final daysLeft = plan.daysToTarget;
    final behindBy = health == PlanHealth.behind
        ? overdueDays(plan, DateTime.now())
        : 0;

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
                  _MiniRing(percent: pct, color: _healthColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _HealthChip(
                              label: health == PlanHealth.behind
                                  ? 'Behind $behindBy d'
                                  : health.label,
                              color: _healthColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${plan.completedTopics}/${plan.totalTopics} topics · '
                                '${formatEstMinutes(plan.remainingMinutes)} left',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: theme.textTheme.bodySmall?.color),
                ],
              ),
              const SizedBox(height: 14),
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
                  Text(
                      health == PlanHealth.done
                          ? DateFormat('d MMM').format(plan.targetDate)
                          : daysLeft == 0
                              ? 'Due today'
                              : '$daysLeft days left',
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

class _HealthChip extends StatelessWidget {
  final String label;
  final Color color;
  const _HealthChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _MiniRing extends StatelessWidget {
  final double percent;
  final Color color;
  const _MiniRing({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${percent.toStringAsFixed(0)} percent complete',
      excludeSemantics: true,
      child: SizedBox(
        width: 50,
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (percent / 100).clamp(0, 1)),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            Text('${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: color)),
          ],
        ),
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
              const Icon(Icons.add_rounded, size: 20, color: AppColors.primary),
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

// ── First-run (no plans) ──────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _HeroCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF8B7FEC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.softShadow(opacity: 0.22, blur: 26),
      ),
      child: Stack(
        children: [
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _GlassPill(
                  icon: Icons.auto_awesome_rounded, label: 'AI planner'),
              const SizedBox(height: 14),
              Text('Turn any subject into a daily plan',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                'Tell AI what to learn and your deadline. It breaks it into '
                'topics, estimates the time and schedules it around your week.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92), height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
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
              const _IconTile(
                  icon: Icons.edit_note_rounded, color: AppColors.primary),
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

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      (Icons.edit_rounded, 'Tell us the goal',
          'Subject, your level and the deadline.'),
      (Icons.view_timeline_rounded, 'Get a daily plan',
          'Topics spread across the days you study.'),
      (Icons.trending_up_rounded, 'Stay on track',
          'Tick topics off. Fall behind? Replan in one tap.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _IconTile(
                    icon: steps[i].$1, color: AppColors.primary, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ${steps[i].$2}',
                          style: theme.textTheme.titleSmall),
                      Text(steps[i].$3, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconTile({required this.icon, required this.color, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
