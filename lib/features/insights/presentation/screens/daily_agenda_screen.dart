import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/widgets/ai_error_view.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../tasks/domain/task_item.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tips/domain/discoverable_feature.dart';
import '../../../tips/presentation/providers/tips_providers.dart';
import '../../data/daily_agenda_pdf.dart';
import '../providers/insights_ai_providers.dart';

/// An AI-backed digest of the user's day — classes, tasks and exams — that can
/// be read on screen and downloaded/shared as a PDF.
class DailyAgendaScreen extends ConsumerWidget {
  const DailyAgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final classes = ref.watch(classesForDayProvider(now));
    final tasks = ref.watch(pendingTasksProvider);
    final exams = ref.watch(upcomingExamsProvider);
    final summaryState = ref.watch(dailyAgendaControllerProvider);

    final canDownload = !(summaryState?.isLoading ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily agenda'),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: canDownload
                ? () => _showDownloadOptions(context, ref, now, classes)
                : null,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          _dateHeader(theme, now),
          const SizedBox(height: 14),
          _AiSummaryCard(),
          const SizedBox(height: 14),
          _section(
            theme,
            icon: Icons.schedule_rounded,
            color: AppColors.primary,
            title: "Today's classes",
            emptyText: 'No classes scheduled today.',
            children: [
              for (final c in classes)
                _line(
                  theme,
                  c.subject.name,
                  '${DateUtilsX.displayTime(context, c.session.startTime)}'
                  '–${DateUtilsX.displayTime(context, c.session.endTime)}'
                  '${(c.session.room?.isNotEmpty ?? false) ? ' · ${c.session.room}' : ''}',
                  dotColor: Color(c.subject.colorHex),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _section(
            theme,
            icon: Icons.checklist_rounded,
            color: AppColors.info,
            title: 'Tasks & deadlines',
            emptyText: "No pending tasks — you're all caught up.",
            children: [
              for (final t in tasks.take(20))
                _line(
                  theme,
                  t.title,
                  '${t.type.label}'
                  '${t.dueDate != null ? ' · due ${DateUtilsX.prettyDate(t.dueDate!)}' : ''}'
                  ' · ${t.priority.label}',
                  dotColor: t.isOverdue ? AppColors.danger : AppColors.info,
                  trailing: t.isOverdue ? 'OVERDUE' : null,
                  trailingColor: AppColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _section(
            theme,
            icon: Icons.event_note_rounded,
            color: AppColors.coral,
            title: 'Upcoming exams',
            emptyText: 'No exams on the horizon.',
            children: [
              for (final e in exams.take(12))
                _line(
                  theme,
                  e.title,
                  '${DateUtilsX.prettyDate(e.date)} · ${e.countdownLabel}'
                  '${(e.room?.isNotEmpty ?? false) ? ' · ${e.room}' : ''}',
                  dotColor: AppColors.coral,
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: canDownload
                ? () => _download(context, ref, now, classes, tasks, exams)
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text("Download today's summary (PDF)"),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: canDownload
                ? () => _downloadWeek(context, ref, now)
                : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.date_range_rounded),
            label: const Text('Download last 7 days (PDF)'),
          ),
        ],
      ),
    );
  }

  /// A small chooser used by the app-bar download icon.
  Future<void> _showDownloadOptions(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
    List<ScheduledClass> classes,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.today_rounded, color: AppColors.primary),
              title: const Text("Today's summary"),
              subtitle: const Text('Classes, tasks & exams for today'),
              onTap: () {
                Navigator.pop(ctx);
                _download(context, ref, now, classes,
                    ref.read(pendingTasksProvider), ref.read(upcomingExamsProvider));
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded,
                  color: AppColors.info),
              title: const Text('Last 7 days'),
              subtitle: const Text('A weekly report with classes by day'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadWeek(context, ref, now);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _dateHeader(ThemeData theme, DateTime now) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good ${_partOfDay(now)}',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: Colors.white70)),
          const SizedBox(height: 2),
          Text(DateUtilsX.prettyFullDate(now),
              style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  String _partOfDay(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  Widget _section(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String emptyText,
    required List<Widget> children,
  }) {
    final real = children.whereType<Widget>().toList();
    final isEmpty = children.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: theme.brightness == Brightness.light
            ? AppColors.softShadow(opacity: 0.05, blur: 16)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isEmpty)
            Text(emptyText,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor))
          else
            ...real,
        ],
      ),
    );
  }

  Widget _line(
    ThemeData theme,
    String title,
    String detail, {
    required Color dotColor,
    String? trailing,
    Color? trailingColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 5, right: 10),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (trailingColor ?? AppColors.primary)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(trailing,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: trailingColor ?? AppColors.primary,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
    List<ScheduledClass> classes,
    List tasks,
    List exams,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final userName =
        ref.read(userProfileProvider).valueOrNull?.displayName ?? 'Student';
    final summary = ref.read(dailyAgendaControllerProvider)?.valueOrNull;

    final classLines = [
      for (final c in classes)
        AgendaLine(
          c.subject.name,
          '${c.session.startTime}–${c.session.endTime}'
          '${(c.session.room?.isNotEmpty ?? false) ? ' · ${c.session.room}' : ''}',
        ),
    ];
    final taskLines = [
      for (final t in ref.read(pendingTasksProvider).take(20))
        AgendaLine(
          t.title,
          '${t.type.label}'
          '${t.dueDate != null ? ' · due ${DateUtilsX.prettyDate(t.dueDate!)}' : ''}'
          ' · ${t.priority.label}${t.isOverdue ? ' · OVERDUE' : ''}',
        ),
    ];
    final examLines = [
      for (final e in ref.read(upcomingExamsProvider).take(12))
        AgendaLine(
          e.title,
          '${DateUtilsX.prettyDate(e.date)} · ${e.countdownLabel}'
          '${(e.room?.isNotEmpty ?? false) ? ' · ${e.room}' : ''}',
        ),
    ];

    try {
      await DailyAgendaPdf.share(
        userName: userName,
        date: now,
        classes: classLines,
        tasks: taskLines,
        exams: examLines,
        aiSummary: summary,
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not create the PDF. Please try again.')));
    }
  }

  /// Builds a "last 7 days" report: each day's scheduled classes (annotated
  /// with any marked attendance) plus current pending tasks and upcoming exams.
  Future<void> _downloadWeek(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final userName =
        ref.read(userProfileProvider).valueOrNull?.displayName ?? 'Student';
    final summary = ref.read(dailyAgendaControllerProvider)?.valueOrNull;
    final today = DateTime(now.year, now.month, now.day);

    // Look up marked attendance keyed by "dateId#subjectId".
    final subjects = ref.read(subjectsStreamProvider).valueOrNull ?? const [];
    final statusByKey = <String, AttendanceStatus>{};
    try {
      for (final s in subjects) {
        final records =
            await ref.read(attendanceForSubjectProvider(s.id).future);
        for (final r in records) {
          if (r.status != AttendanceStatus.unmarked) {
            statusByKey['${r.dateId}#${s.id}'] = r.status;
          }
        }
      }
    } catch (_) {
      // Proceed with whatever attendance data resolved.
    }

    final days = <DaySection>[];
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final dayId = DateUtilsX.dateId(day);
      final dayClasses = ref.read(classesForDayProvider(day));
      final lines = <AgendaLine>[
        for (final c in dayClasses)
          AgendaLine(
            c.subject.name,
            '${c.session.startTime}-${c.session.endTime}'
            '${(c.session.room?.isNotEmpty ?? false) ? ' · ${c.session.room}' : ''}'
            '${statusByKey['$dayId#${c.subject.id}'] != null ? ' · ${statusByKey['$dayId#${c.subject.id}']!.label}' : ''}',
          ),
      ];
      days.add(DaySection(day, lines));
    }

    final taskLines = [
      for (final t in ref.read(pendingTasksProvider).take(20))
        AgendaLine(
          t.title,
          '${t.type.label}'
          '${t.dueDate != null ? ' · due ${DateUtilsX.prettyDate(t.dueDate!)}' : ''}'
          ' · ${t.priority.label}${t.isOverdue ? ' · OVERDUE' : ''}',
        ),
    ];
    final examLines = [
      for (final e in ref.read(upcomingExamsProvider).take(12))
        AgendaLine(
          e.title,
          '${DateUtilsX.prettyDate(e.date)} · ${e.countdownLabel}'
          '${(e.room?.isNotEmpty ?? false) ? ' · ${e.room}' : ''}',
        ),
    ];

    try {
      await DailyAgendaPdf.shareWeek(
        userName: userName,
        days: days,
        tasks: taskLines,
        exams: examLines,
        aiSummary: summary,
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not create the PDF. Please try again.')));
    }
  }
}

/// The AI daily-summary card: generates a friendly briefing on demand and
/// renders it, with loading/error/retry states.
class _AiSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(dailyAgendaControllerProvider);
    final controller = ref.read(dailyAgendaControllerProvider.notifier);
    // Wrap generation so the "AI daily summary" feature is marked as tried on
    // the Tips & Tricks checklist the first time it's used.
    void onGenerate() {
      ref.read(featureUsageProvider.notifier).markUsed(FeatureId.dailySummary);
      controller.generate();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        boxShadow: theme.brightness == Brightness.light
            ? AppColors.softShadow(opacity: 0.05, blur: 16)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('AI daily summary',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (state != null && !state.isLoading)
                IconButton(
                  tooltip: 'Regenerate',
                  onPressed: onGenerate,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.primary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _body(context, theme, state, onGenerate),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ThemeData theme, AsyncValue<String>? state,
      VoidCallback onGenerate) {
    if (state == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Let AI turn today\'s classes, tasks and exams into a friendly, '
            'prioritised briefing you can read or download.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onGenerate,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Generate summary'),
          ),
        ],
      );
    }

    return state.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Text('Writing your briefing…',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
      error: (e, _) => AiErrorView(error: e, onRetry: onGenerate),
      data: (text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}
