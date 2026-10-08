import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../chat/presentation/widgets/ai_error_view.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../expenses/domain/expense.dart';
import '../../../expenses/presentation/providers/expense_providers.dart';
import '../../../focus/presentation/providers/study_providers.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/insight_math.dart';
import '../providers/insights_ai_providers.dart';
import '../widgets/insight_charts.dart';

/// Pro-only analytics: an AI insights briefing plus chart-rich attendance,
/// spending, grade and study cards — all derived from the user's own data.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target =
        ref.watch(userProfileProvider).valueOrNull?.targetAttendancePercent ??
            AppConstants.defaultTargetAttendance;

    final cards = <Widget>[
      _AiInsightsCard(),
      _attendanceCard(context, ref, theme, target),
      _examsCard(context, ref, theme),
      _budgetCard(context, ref, theme),
      _gradeCard(context, ref, theme),
      _studyCard(context, ref, theme),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights & predictions'),
        centerTitle: false,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) => cards[i]
            .animate()
            .fadeIn(duration: 350.ms, delay: (60 * i).ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
      ),
    );
  }

  // ── shared card chrome ─────────────────────────────────────────────────
  static Widget _card(ThemeData theme, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: theme.brightness == Brightness.light
              ? AppColors.softShadow(opacity: 0.05, blur: 18)
              : null,
        ),
        child: child,
      );

  static Widget _header(ThemeData theme, IconData icon, String title,
      {Color color = AppColors.primary, Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ── Attendance ─────────────────────────────────────────────────────────
  Widget _attendanceCard(
      BuildContext context, WidgetRef ref, ThemeData theme, double target) {
    final overall = ref.watch(overallStatsProvider);
    final advice = attendanceAdvice(
        attended: overall.present, held: overall.held, target: target);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    String headline;
    Color color;
    if (overall.held == 0) {
      headline = 'Mark some classes to unlock projections.';
      color = theme.hintColor;
    } else if (advice.unreachable) {
      headline =
          'Reaching ${target.toStringAsFixed(0)}% now needs every remaining class.';
      color = AppColors.danger;
    } else if (advice.onTrack) {
      headline = advice.canSkip > 0
          ? 'You can skip ${advice.canSkip} more class'
              '${advice.canSkip == 1 ? '' : 'es'} and stay above '
              '${target.toStringAsFixed(0)}%.'
          : 'Right at your ${target.toStringAsFixed(0)}% target — don\'t miss any.';
      color = AppColors.success;
    } else {
      headline = 'Attend the next ${advice.mustAttend} class'
          '${advice.mustAttend == 1 ? '' : 'es'} to reach '
          '${target.toStringAsFixed(0)}%.';
      color = AppColors.warning;
    }

    final ringColor = overall.held == 0 ? theme.hintColor : color;

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, Icons.insights_rounded, 'Attendance projection'),
          const SizedBox(height: 16),
          Row(
            children: [
              RingChart(
                value: overall.held == 0 ? 0 : advice.percent / 100,
                target: target / 100,
                color: ringColor,
                size: 128,
                stroke: 13,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${advice.percent.toStringAsFixed(0)}%',
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800, color: ringColor)),
                    Text('attended',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: color, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(theme, '${overall.present} present',
                            AppColors.present),
                        _pill(theme, '${overall.absent} absent',
                            AppColors.absent),
                        _pill(theme, 'target ${target.toStringAsFixed(0)}%',
                            AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subjects.isNotEmpty) ...[
            const Divider(height: 28),
            Text('By subject',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 4),
            ...subjects.take(12).map((s) {
              final stats = ref.watch(subjectStatsProvider(s.id));
              final a = attendanceAdvice(
                  attended: stats.present, held: stats.held, target: target);
              final subColor = stats.held == 0
                  ? theme.hintColor
                  : (a.onTrack ? AppColors.success : AppColors.danger);
              final trailing = stats.held == 0
                  ? 'no data'
                  : '${a.percent.toStringAsFixed(0)}%';
              return BarRow(
                label: s.name,
                fraction: stats.held == 0 ? 0 : a.percent / 100,
                color: Color(s.colorHex),
                trailing: trailing,
                trailingColor: subColor,
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Exams ──────────────────────────────────────────────────────────────
  Widget _examsCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final upcoming = ref.watch(upcomingExamsProvider);
    final past = ref.watch(pastExamsProvider);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    String subjectName(String? id) {
      if (id == null) return '';
      for (final s in subjects) {
        if (s.id == id) return s.name;
      }
      return '';
    }

    Color subjectColor(String? id) {
      if (id == null) return AppColors.danger;
      for (final s in subjects) {
        if (s.id == id) return Color(s.colorHex);
      }
      return AppColors.danger;
    }

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, Icons.event_note_rounded, 'Exams',
              color: AppColors.danger,
              trailing: upcoming.isEmpty
                  ? null
                  : _pill(theme,
                      '${upcoming.length} upcoming', AppColors.danger)),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                past.isEmpty
                    ? 'Add your exams to see live countdowns and how ready you are for each one.'
                    : 'No upcoming exams — you’re all caught up. 🎉',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            // The soonest exam, highlighted with a live countdown.
            Builder(builder: (context) {
              final next = upcoming.first;
              final subj = subjectName(next.subjectId);
              final d = next.daysUntil;
              final countColor = d <= 2
                  ? AppColors.danger
                  : (d <= 7 ? AppColors.warning : AppColors.success);
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: countColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Next up',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.hintColor)),
                          const SizedBox(height: 2),
                          Text(next.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (subj.isNotEmpty)
                            Text(subj,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(next.countdownLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: countColor)),
                        if (next.hasTopics)
                          Text('${(next.readiness * 100).toStringAsFixed(0)}% ready',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.hintColor)),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            Text('Prep readiness',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 4),
            // Revision progress per upcoming exam (topics checked off).
            ...upcoming.take(6).map((e) {
              final label = subjectName(e.subjectId).isEmpty
                  ? e.title
                  : '${e.title} · ${subjectName(e.subjectId)}';
              final ready = e.hasTopics ? e.readiness : 0.0;
              return BarRow(
                label: label,
                fraction: ready,
                color: subjectColor(e.subjectId),
                trailing:
                    e.hasTopics ? '${(ready * 100).toStringAsFixed(0)}%' : e.countdownLabel,
                trailingColor: e.hasTopics ? null : theme.hintColor,
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Spending ───────────────────────────────────────────────────────────
  Widget _budgetCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final currency = ref.watch(currencySymbolProvider);
    final spent = ref.watch(monthlyTotalProvider);
    final budget = ref.watch(monthlyBudgetProvider);
    final breakdown = ref.watch(categoryBreakdownProvider);
    final projected =
        projectedMonthlySpend(spentSoFar: spent, now: DateTime.now());
    final overBudget = budget > 0 && projected > budget;

    final slices = [
      for (final e in breakdown) DonutSlice(e.key.label, e.value, e.key.color),
    ];

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, Icons.account_balance_wallet_rounded,
              'Spending forecast',
              color: AppColors.info),
          const SizedBox(height: 14),
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Log some expenses to see your spending breakdown.',
                  style: theme.textTheme.bodyMedium),
            )
          else
            Row(
              children: [
                DonutChart(
                  slices: slices,
                  size: 128,
                  stroke: 18,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$currency${spent.toStringAsFixed(0)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.info)),
                      Text('this month',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in breakdown.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: LegendDot(
                            color: e.key.color,
                            label: e.key.label,
                            value: '$currency${e.value.toStringAsFixed(0)}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Projected month-end',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$currency${projected.toStringAsFixed(0)}'
                  '${budget > 0 ? ' / $currency${budget.toStringAsFixed(0)}' : ''}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: overBudget ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          if (budget > 0) ...[
            const SizedBox(height: 10),
            BudgetMeter(
              spentFraction: budget > 0 ? spent / budget : 0,
              projectedFraction: budget > 0 ? projected / budget : 0,
              color: AppColors.info,
              over: overBudget,
            ),
            const SizedBox(height: 8),
            Text(
              overBudget
                  ? 'On track to exceed budget by '
                      '$currency${(projected - budget).toStringAsFixed(0)}.'
                  : 'Projected to stay within budget — nice.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: overBudget ? AppColors.danger : AppColors.success),
            ),
          ],
        ],
      ),
    );
  }

  // ── Grades ─────────────────────────────────────────────────────────────
  Widget _gradeCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final gpa = ref.watch(gpaSummaryProvider);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, Icons.school_rounded, 'Grades & GPA',
              color: AppColors.primaryLight),
          const SizedBox(height: 8),
          if (gpa.gradedSubjects == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Add some grades to see your GPA and averages.',
                  style: theme.textTheme.bodyMedium),
            )
          else ...[
            Center(
              child: GaugeChart(
                value: gpa.maxPoints > 0
                    ? (gpa.gpa / gpa.maxPoints).clamp(0.0, 1.0)
                    : 0,
                color: AppColors.primary,
                size: 180,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(gpa.gpa.toStringAsFixed(2),
                        style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    Text('GPA / ${gpa.maxPoints.toStringAsFixed(0)}  ·  '
                        'avg ${gpa.averagePercent.toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...subjects.map((s) {
              final course = ref.watch(courseGradeProvider(s.id));
              if (course.count == 0) return const SizedBox.shrink();
              return BarRow(
                label: s.name,
                fraction: (course.percent / 100).clamp(0.0, 1.0),
                color: Color(s.colorHex),
                trailing: '${course.percent.toStringAsFixed(0)}%',
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Study ──────────────────────────────────────────────────────────────
  Widget _studyCard(BuildContext context, WidgetRef ref, ThemeData theme) {
    final study = ref.watch(studyStatsProvider);
    final sessions =
        ref.watch(studySessionsStreamProvider).valueOrNull ?? const [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final bars = <BarDatum>[];
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final mins = sessions
          .where((s) => DateUtilsX.isSameDay(s.startedAt, d))
          .fold<int>(0, (a, s) => a + s.minutes);
      bars.add(BarDatum(
        DateFormat('E').format(d).substring(0, 1),
        mins.toDouble(),
        highlight: i == days.length - 1,
      ));
    }

    final wkH = study.weekMinutes ~/ 60;
    final wkM = study.weekMinutes % 60;
    final tdH = study.todayMinutes ~/ 60;
    final tdM = study.todayMinutes % 60;

    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, Icons.timer_rounded, 'Study focus',
              color: AppColors.coral),
          const SizedBox(height: 16),
          MiniBarChart(
            data: bars,
            color: AppColors.coral,
            height: 130,
            valueLabel: (v) => v >= 60
                ? '${(v / 60).toStringAsFixed(v % 60 == 0 ? 0 : 1)}h'
                : '${v.toInt()}m',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatChip(
                  icon: Icons.calendar_view_week_rounded,
                  value: wkH > 0 ? '${wkH}h ${wkM}m' : '${wkM}m',
                  caption: 'This week',
                  color: AppColors.coral,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatChip(
                  icon: Icons.today_rounded,
                  value: tdH > 0 ? '${tdH}h ${tdM}m' : '${tdM}m',
                  caption: 'Today',
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatChip(
                  icon: Icons.local_fire_department_rounded,
                  value: '${study.streakDays}',
                  caption: 'Day streak',
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _pill(ThemeData theme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      );
}

/// The headline card: a Gemini-generated insights briefing built from the
/// user's own data, generated on demand to respect AI usage.
class _AiInsightsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(aiInsightsControllerProvider);
    final controller = ref.read(aiInsightsControllerProvider.notifier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('AI insights',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              if (state != null && !state.isLoading)
                IconButton(
                  tooltip: 'Regenerate',
                  onPressed: controller.generate,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _body(context, theme, state, controller),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ThemeData theme, AsyncValue<String>? state,
      AiTextController controller) {
    // Idle — invite the user to generate.
    if (state == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get a personalised briefing on your attendance, grades, study '
            'momentum and spending — analysed by AI from your own data.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
          ),
          const SizedBox(height: 14),
          _generateButton(context, controller, 'Generate insights'),
        ],
      );
    }

    return state.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Analysing your data…',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
          ],
        ),
      ),
      error: (e, _) => AiErrorView(
        error: e,
        onRetry: controller.generate,
        onDark: true,
      ),
      data: (text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _generateButton(
      BuildContext context, AiTextController controller, String label) {
    return FilledButton.icon(
      onPressed: controller.generate,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
