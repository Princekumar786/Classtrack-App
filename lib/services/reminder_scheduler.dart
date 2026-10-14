import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_settings_provider.dart';
import '../core/providers/firebase_providers.dart';
import '../core/providers/notification_prefs_provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/date_utils.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/exams/domain/exam.dart';
import '../features/exams/presentation/providers/exam_providers.dart';
import '../features/habits/domain/habit.dart';
import '../features/habits/presentation/providers/habit_providers.dart';
import '../features/insights/domain/insight_math.dart';
import '../features/schedule/domain/class_session.dart';
import '../features/schedule/presentation/providers/schedule_providers.dart';
import '../features/subjects/domain/subject.dart';
import '../features/subjects/presentation/providers/subject_providers.dart';
import '../features/subscription/presentation/providers/subscription_providers.dart';
import '../features/tasks/domain/task_item.dart';
import '../features/tasks/presentation/providers/task_providers.dart';
import 'notification_service.dart';
import 'error_reporter.dart';
import 'reminder_sync_runner.dart';

/// The two serial job queues used by [reminderSyncProvider]:
///  • `schedule` — class reminders, check-ins, tasks, exams, habits (many
///    platform calls; only re-run when the TIMETABLE/items actually change,
///    never because an attendance counter moved).
///  • `alerts` — the daily summary + attendance-risk alert (one call each;
///    these legitimately depend on attendance numbers).
///
/// Re-created per signed-in user, so a sign-out (which cancels every local
/// notification) always forces a full re-schedule for the next session.
typedef ReminderSyncRunners = ({
  ReminderSyncRunner schedule,
  ReminderSyncRunner alerts,
});

final reminderSyncRunnersProvider = Provider<ReminderSyncRunners>((ref) {
  ref.watch(currentUidProvider);
  final runners = (
    schedule: ReminderSyncRunner(onError: _reportSyncError),
    alerts: ReminderSyncRunner(onError: _reportSyncError),
  );
  ref.onDispose(() {
    runners.schedule.dispose();
    runners.alerts.dispose();
  });
  return runners;
});

/// Scheduling failures (e.g. the OS alarm limit, a revoked exact-alarm
/// permission) are logged as NON-fatal instead of escaping as uncaught errors.
void _reportSyncError(Object error, StackTrace stack) =>
    ErrorReporter.report(error, stack, reason: 'reminder_sync');

/// Fingerprint of everything that affects class/task/exam/habit reminders.
/// Deliberately EXCLUDES attendance counters, so marking a class never
/// triggers a full re-schedule. Pure — unit tested.
@visibleForTesting
String reminderScheduleSignature({
  required NotificationPrefs prefs,
  required int lead,
  required Map<String, ({Subject subject, List<ClassSession> sessions})>
      classes,
  required List<TaskItem> tasks,
  required List<Exam> exams,
  required List<Habit> habits,
}) {
  final b = StringBuffer()
    ..write('lead=$lead;')
    ..write('p=${prefs.classes},${prefs.attendanceCheckIns},${prefs.tasks},'
        '${prefs.exams},${prefs.habits},${prefs.quietHours},'
        '${prefs.quietStartHour},${prefs.quietEndHour};');
  final subjectIds = classes.keys.toList()..sort();
  for (final id in subjectIds) {
    final c = classes[id]!;
    final sigs = c.sessions.map((s) => s.signature).toList()..sort();
    b.write('S:$id|${c.subject.name}|${sigs.join(',')};');
  }
  for (final t in tasks) {
    b.write('T:${t.id}|${t.title}|${t.dueDate?.millisecondsSinceEpoch}|'
        '${t.done}|${t.type.name}|${t.hasLink};');
  }
  for (final e in exams) {
    b.write('E:${e.id}|${e.title}|${e.date.millisecondsSinceEpoch}|'
        '${e.room ?? ''};');
  }
  for (final h in habits) {
    b.write('H:${h.id}|${h.title}|${h.reminderMinutes};');
  }
  return b.toString();
}

/// Keeps class, task, exam & habit reminders in sync with the latest data and
/// the user's notification preferences while the app is open. Watched once
/// (by HomeShell). The actual scheduling runs in a serial, de-duplicated,
/// debounced queue ([ReminderSyncRunner]) so bursts of data changes — e.g.
/// every attendance tap rewriting the subject counters — can never pile up
/// hundreds of overlapping notification calls and freeze the app.
final reminderSyncProvider = Provider<void>((ref) {
  final runners = ref.watch(reminderSyncRunnersProvider);
  if (!ref.watch(remindersEnabledProvider)) {
    // Something else may clear notifications while off; re-apply fully when
    // reminders are turned back on.
    runners.schedule.reset();
    runners.alerts.reset();
    return;
  }
  final service = ref.watch(notificationServiceProvider);
  final lead = ref.watch(reminderLeadProvider);
  final prefs = ref.watch(notificationPrefsProvider);
  final isPro = ref.watch(isProProvider);

  final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  final exams = ref.watch(examsStreamProvider).valueOrNull ?? const [];
  final habits = ref.watch(habitsStreamProvider).valueOrNull ?? const [];
  final scheduledClasses = ref.watch(allSessionsProvider);

  final sessionsBySubject = <String, List<ClassSession>>{};
  final subjectsById = <String, Subject>{};
  for (final sc in scheduledClasses) {
    sessionsBySubject.putIfAbsent(sc.subject.id, () => []).add(sc.session);
    subjectsById[sc.subject.id] = sc.subject;
  }

  // ── Classes, check-ins, tasks, exams, habits ─────────────────────────────
  final scheduleSig = reminderScheduleSignature(
    prefs: prefs,
    lead: lead,
    classes: {
      for (final e in sessionsBySubject.entries)
        e.key: (subject: subjectsById[e.key]!, sessions: e.value),
    },
    tasks: tasks,
    exams: exams,
    habits: habits,
  );
  runners.schedule.submit(scheduleSig, () async {
    final errors = <(Object, StackTrace)>[];
    Future<void> step(Future<void> Function() f) async {
      try {
        await f();
      } catch (e, st) {
        errors.add((e, st));
      }
    }

    final currentSubjectIds = sessionsBySubject.keys.toSet();
    if (prefs.classes) {
      // Cancel reminders for subjects removed since the last sync, then
      // (re)schedule reminders for the current subjects.
      await step(() => service.pruneClassReminders(currentSubjectIds));
      for (final entry in sessionsBySubject.entries) {
        await step(() => service.scheduleForSubject(
            subjectsById[entry.key]!, entry.value,
            minutesBefore: lead, prefs: prefs));
      }
    } else {
      await step(() => service.pruneClassReminders(<String>{}));
      for (final id in currentSubjectIds) {
        await step(() => service.cancelForSubject(id));
      }
    }

    // After-class attendance check-ins.
    if (prefs.attendanceCheckIns) {
      await step(() => service.pruneAttendanceCheckIns(currentSubjectIds));
      for (final entry in sessionsBySubject.entries) {
        await step(() => service.scheduleAttendanceCheckIns(
            subjectsById[entry.key]!, entry.value,
            prefs: prefs));
      }
    } else {
      await step(() => service.pruneAttendanceCheckIns(<String>{}));
      for (final id in currentSubjectIds) {
        await step(() => service.cancelAttendanceCheckInsForSubject(id));
      }
    }

    if (prefs.tasks) {
      await step(() =>
          service.scheduleForTasks(tasks, minutesBefore: lead, prefs: prefs));
    } else {
      for (final t in tasks) {
        await step(() => service.cancelTask(t.id));
      }
    }

    if (prefs.exams) {
      await step(() =>
          service.scheduleForExams(exams, minutesBefore: 30, prefs: prefs));
    } else {
      for (final e in exams) {
        await step(() => service.cancelExam(e.id));
      }
    }

    if (prefs.habits) {
      await step(() => service.scheduleForHabits(habits, prefs: prefs));
    } else {
      for (final h in habits) {
        await step(() => service.cancelHabit(h.id));
      }
    }

    // Surface the first failure so the runner logs it and retries next time.
    if (errors.isNotEmpty) {
      Error.throwWithStackTrace(errors.first.$1, errors.first.$2);
    }
  });

  // ── Daily agenda summary + attendance risk alert (Pro) ───────────────────
  // Both reuse the "smart daily notifications" toggle (dailySummary).
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  ({String title, String body})? summary;
  ({String title, String body})? risk;
  if (isPro && prefs.dailySummary) {
    final classCount =
        scheduledClasses.where((c) => c.session.occursOn(now)).length;
    final dueToday = tasks
        .where((t) =>
            !t.done &&
            t.dueDate != null &&
            DateUtilsX.isSameDay(t.dueDate!, now))
        .length;
    final examsSoon = exams
        .where((e) =>
            !e.date.isBefore(today) &&
            e.date.isBefore(today.add(const Duration(days: 2))))
        .length;
    final parts = <String>[
      '$classCount class${classCount == 1 ? '' : 'es'}',
      if (dueToday > 0) '$dueToday task${dueToday == 1 ? '' : 's'} due',
      if (examsSoon > 0) '$examsSoon exam${examsSoon == 1 ? '' : 's'} soon',
    ];
    summary = (
      title: 'Your day at a glance',
      body: 'Today: ${parts.join(' · ')}. Tap to view & download your summary.',
    );

    // The evening before, if skipping a class scheduled tomorrow would push a
    // subject below the user's target, send one actionable heads-up.
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final target = ref
            .watch(userProfileProvider)
            .valueOrNull
            ?.targetAttendancePercent ??
        AppConstants.defaultTargetAttendance;
    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowCount = <String, int>{};
    for (final sc in scheduledClasses) {
      if (sc.session.occursOn(tomorrow)) {
        tomorrowCount[sc.subject.id] = (tomorrowCount[sc.subject.id] ?? 0) + 1;
      }
    }
    final atRisk = <AttendanceRiskAlert>[];
    for (final s in subjects) {
      final upcoming = tomorrowCount[s.id] ?? 0;
      if (upcoming == 0) continue;
      final alert = attendanceRiskAlert(
        subjectName: s.name,
        attended: s.attended,
        held: s.held,
        target: s.effectiveTarget(target),
        upcomingCount: upcoming,
      );
      if (alert.level == AttendanceRiskLevel.danger) atRisk.add(alert);
    }
    if (atRisk.isNotEmpty) {
      final t = target.toStringAsFixed(0);
      risk = (
        title: atRisk.length == 1
            ? '${atRisk.first.subjectName} attendance at risk'
            : '${atRisk.length} subjects at risk tomorrow',
        body: atRisk.length == 1
            ? atRisk.first.message
            : 'Missing tomorrow’s classes could drop ${atRisk.map((a) => a.subjectName).take(3).join(', ')} below your $t% target.',
      );
    }
  }
  final alertsSig = 'q=${prefs.quietHours},${prefs.quietStartHour},'
      '${prefs.quietEndHour};at=${prefs.summaryHour}:${prefs.summaryMinute};'
      'sum=${summary?.title}|${summary?.body};risk=${risk?.title}|${risk?.body}';
  runners.alerts.submit(alertsSig, () async {
    final s = summary;
    if (s != null) {
      await service.scheduleDailySummary(
        hour: prefs.summaryHour,
        minute: prefs.summaryMinute,
        title: s.title,
        body: s.body,
      );
    } else {
      await service.cancelDailySummary();
    }
    final r = risk;
    if (r != null) {
      await service.scheduleAttendanceRiskAlert(
        hour: 20,
        minute: 0,
        title: r.title,
        body: r.body,
        prefs: prefs,
      );
    } else {
      await service.cancelAttendanceRiskAlert();
    }
  });
});

/// Requests notification permission and, if granted, turns reminders on (which
/// makes [reminderSyncProvider] schedule everything). Safe to call from a
/// button tap.
Future<void> enableRemindersFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(notificationServiceProvider);
  final granted = await service.requestPermissions();
  if (granted) {
    await ref.read(remindersEnabledProvider.notifier).set(true);
    messenger.showSnackBar(const SnackBar(
        content: Text(
            "Reminders on — you'll be notified before classes, tasks and exams.")));
  } else {
    messenger.showSnackBar(const SnackBar(
        content: Text('Notification permission was denied.')));
  }
}

/// A small opt-in card shown only while reminders are OFF. Tapping Enable
/// requests permission and turns them on; the card then disappears.
class RemindersBanner extends ConsumerWidget {
  const RemindersBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(remindersEnabledProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turn on reminders',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('Get notified before classes, tasks and exams.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => enableRemindersFlow(context, ref),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
