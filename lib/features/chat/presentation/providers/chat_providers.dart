import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/providers/gemini_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../services/gemini_service.dart';
import '../../../../services/analytics_service.dart';
import '../../domain/ai_errors.dart';
import '../../domain/chat_actions_logic.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../exams/domain/exam.dart';
import '../../../exams/presentation/providers/exam_providers.dart';
import '../../../expenses/domain/expense.dart';
import '../../../expenses/presentation/providers/expense_providers.dart';
import '../../../focus/presentation/providers/study_providers.dart';
import '../../../grades/domain/grade_item.dart';
import '../../../grades/presentation/providers/grade_providers.dart';
import '../../../habits/domain/habit.dart';
import '../../../habits/presentation/providers/habit_providers.dart';
import '../../../learning_planner/domain/learning_plan.dart';
import '../../../learning_planner/domain/learning_plan_generator.dart';
import '../../../learning_planner/presentation/providers/learning_planner_providers.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/presentation/providers/note_providers.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../../../schedule/domain/class_session.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/domain/pro_constants.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../tasks/domain/task_item.dart';
import '../../../tasks/presentation/providers/task_providers.dart';
import '../../../tips/domain/discoverable_feature.dart';
import '../../../tips/presentation/providers/tips_providers.dart';
import '../../domain/chat_message.dart';
import '../../data/chat_repository.dart';
import '../../domain/chat_session.dart';
import 'chat_usage_providers.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool sending;
  const ChatState({this.messages = const [], this.sending = false});

  ChatState copyWith({List<ChatMessage>? messages, bool? sending}) => ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
      );
}

const _welcome = ChatMessage(
  role: ChatRole.assistant,
  text: "Hi! I'm Kiro, your study assistant. 👋\n\n"
      'Tell me your timetable in plain words (e.g. "Mon & Wed 9–10 DBMS in Room 204, '
      "Tue 11–12 Maths\") or attach a photo of it, and I'll build your schedule. "
      'You can also ask me for study or attendance tips.',
);

/// A restorable AI deletion: a human label plus a closure that re-creates the
/// deleted item when the user taps Undo.
class PendingUndo {
  final String label;
  final Future<void> Function() restore;
  const PendingUndo(this.label, this.restore);
}

/// Tally of what a batch of AI actions actually did, so the chat can report the
/// truth instead of echoing the model's (sometimes over-optimistic) "Done".
/// [attempted] counts recognised actions we tried to run; [succeeded] counts
/// the ones that actually changed data (a create/update that found its target,
/// or the number of items a delete removed).
class ActionOutcome {
  int attempted = 0;
  int succeeded = 0;
  void record(bool ok) {
    attempted++;
    if (ok) succeeded++;
  }

  void recordCount(int n) {
    attempted++;
    if (n > 0) succeeded += n;
  }
}

class ChatController extends StateNotifier<ChatState> {
  /// Sent (not shown) when the model claimed a change without an actions
  /// block. Gives it one chance to emit the action it described.
  static const _missingActionsNudge =
      'SYSTEM CHECK (not from the student): your previous reply said you made '
      'a change, but it contained NO ```actions``` block, so NOTHING changed in '
      'the app. If the student asked for a change, reply again with a short '
      'confirmation AND the ```actions``` block, matching the item by its '
      'exact name from the data. If you cannot tell which item they mean, ask '
      'a short question and do NOT claim anything was done.';

  final GeminiService _gemini;
  final Ref _ref;
  final List<Map<String, dynamic>> _history = [];

  /// Firestore id of the conversation currently being edited. Null until the
  /// first real exchange is saved (or after starting a new chat).
  String? _sessionId;

  /// The most recent AI deletion, kept so the UI can offer a one-tap Undo.
  PendingUndo? _pendingUndo;

  /// Returns and clears the pending undo (consumed by the chat screen).
  PendingUndo? takePendingUndo() {
    final u = _pendingUndo;
    _pendingUndo = null;
    return u;
  }

  /// Set when a free user hits the monthly AI limit; the chat screen reads this
  /// to present the paywall.
  bool _needsPaywall = false;
  bool takeNeedsPaywall() {
    final v = _needsPaywall;
    _needsPaywall = false;
    return v;
  }

  ChatController(this._gemini, this._ref)
      : super(const ChatState(messages: [_welcome]));

  bool get isConfigured => _gemini.isConfigured;

  /// Strip stray markdown so the plain-text chat bubble reads cleanly.
  String _cleanMarkdown(String s) {
    var t = s;
    t = t.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*', dotAll: true), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'__(.+?)__', dotAll: true), (m) => m[1]!);
    t = t.replaceAllMapped(
        RegExp(r'(?<!\*)\*(?!\*)(.+?)\*(?!\*)', dotAll: true), (m) => m[1]!);
    t = t.replaceAllMapped(
        RegExp(r'^\s*#{1,6}\s*', multiLine: true), (_) => '');
    t = t.replaceAllMapped(
        RegExp(r'^\s*[-*]\s+', multiLine: true), (_) => '• ');
    t = t.replaceAll('`', '');
    return t.trim();
  }

  /// Compact snapshot of the user's data so the assistant can answer questions
  /// about their attendance, tasks, exams, GPA, expenses, study and habits.
  /// Human-readable free windows BETWEEN a day's classes, so the assistant can
  /// answer "when am I free today/tomorrow?" accurately instead of guessing.
  /// Returns null when there aren't at least two classes to sit between.
  String? _freeGaps(List<ScheduledClass> classes) {
    if (classes.length < 2) return null;
    final sorted = [...classes]..sort((a, b) =>
        DateUtilsX.minutesOfDay(a.session.startTime)
            .compareTo(DateUtilsX.minutesOfDay(b.session.startTime)));
    String fmt(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final gaps = <String>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final endPrev = DateUtilsX.minutesOfDay(sorted[i].session.endTime);
      final startNext =
          DateUtilsX.minutesOfDay(sorted[i + 1].session.startTime);
      // Only count a real break (≥ 15 min) between back-to-back classes.
      if (startNext - endPrev >= 15) {
        gaps.add('${fmt(endPrev)}–${fmt(startNext)}');
      }
    }
    return gaps.isEmpty ? null : gaps.join(', ');
  }

  String _buildContext() {
    final sb = StringBuffer();
    final now = DateTime.now();
    sb.writeln(
        'Today is ${DateUtilsX.prettyFullDate(now)} (${DateUtilsX.dateId(now)}).');
    final profileName =
        _ref.read(userProfileProvider).valueOrNull?.displayName?.trim();
    if (profileName != null && profileName.isNotEmpty) {
      final first = profileName.split(RegExp(r'\s+')).first;
      sb.writeln(
          "The student's name is $first. Greet or address them by their first "
          'name occasionally when it feels natural (for example in a greeting) '
          '— not in every message.');
    }
    final subjects = _ref.read(subjectsStreamProvider).valueOrNull ?? const [];
    final overall = _ref.read(overallStatsProvider);
    final target = _ref.read(userProfileProvider).valueOrNull?.targetAttendancePercent ??
        AppConstants.defaultTargetAttendance;
    if (subjects.isNotEmpty) {
      sb.writeln(
          'Overall attendance: ${overall.held == 0 ? "no data" : "${overall.percent.toStringAsFixed(0)}% (${overall.present}/${overall.held})"}.');
      sb.writeln('Attendance target: ${target.toStringAsFixed(0)}%.');
      final week = _ref.read(weeklyAttendanceProvider);
      if (week.held > 0) {
        sb.writeln(
            'Attendance this week: ${week.percent.toStringAsFixed(0)}% (${week.present}/${week.held} classes; ${week.cancelled} cancelled).');
      }
      sb.writeln('Subjects:');
      for (final s in subjects.take(20)) {
        final held = s.attended + s.absent;
        final effTarget = s.effectiveTarget(target);
        final stats = AttendanceStats(present: s.attended, absent: s.absent);
        var guidance = '';
        if (held > 0) {
          if (s.percent >= effTarget) {
            final canSkip = stats.bunkableClasses(effTarget);
            guidance = canSkip > 0
                ? ' — can skip $canSkip more and stay ≥ ${effTarget.toStringAsFixed(0)}%'
                : " — right at the ${effTarget.toStringAsFixed(0)}% limit, don't skip the next one";
          } else {
            final need = stats.classesToRecover(effTarget);
            guidance = need > 0
                ? ' — below target, attend $need in a row to reach ${effTarget.toStringAsFixed(0)}%'
                : ' — below the ${effTarget.toStringAsFixed(0)}% target';
          }
        }
        sb.writeln(
            '- ${s.name}: ${held == 0 ? "no classes marked" : "${s.percent.toStringAsFixed(0)}% (${s.attended}/$held)"}${s.cancelled > 0 ? ", ${s.cancelled} cancelled" : ""}$guidance.');
      }
    }
    // Today's classes so the assistant can answer "how many classes today?".
    final todayClasses = _ref.read(classesForDayProvider(now));
    if (todayClasses.isEmpty) {
      sb.writeln("Today's classes: none scheduled — the student is free all day.");
    } else {
      sb.writeln("Today's classes (${todayClasses.length}):");
      for (final c in todayClasses) {
        final room = c.session.room;
        sb.writeln(
            '- ${c.subject.name} ${c.session.startTime}–${c.session.endTime}'
            '${room != null && room.isNotEmpty ? " in $room" : ""}.');
      }
      final free = _freeGaps(todayClasses);
      if (free != null) {
        sb.writeln("Free gaps between today's classes: $free.");
      }
    }
    // Tomorrow's classes + exams so the assistant can answer "am I free
    // tomorrow (afternoon)?" and "can I skip tomorrow's lecture?" accurately.
    // classesForDayProvider includes one-off classes and honours course
    // start/end windows and cancellations — not just the recurring template.
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final tomorrowName = Weekdays.full[tomorrow.weekday - 1];
    final tomorrowClasses = _ref.read(classesForDayProvider(tomorrow));
    if (tomorrowClasses.isEmpty) {
      sb.writeln('Tomorrow ($tomorrowName): no classes scheduled.');
    } else {
      sb.writeln('Tomorrow ($tomorrowName) classes (${tomorrowClasses.length}):');
      for (final c in tomorrowClasses) {
        final room = c.session.room;
        sb.writeln(
            '- ${c.subject.name} ${c.session.startTime}–${c.session.endTime}'
            '${room != null && room.isNotEmpty ? " in $room" : ""}.');
      }
      final free = _freeGaps(tomorrowClasses);
      if (free != null) {
        sb.writeln("Free gaps between tomorrow's classes: $free.");
      }
    }
    final allExams = _ref.read(examsStreamProvider).valueOrNull ?? const <Exam>[];
    final tomorrowExams =
        allExams.where((e) => DateUtilsX.isSameDay(e.date, tomorrow)).toList();
    if (tomorrowExams.isNotEmpty) {
      sb.writeln('Tomorrow exams:');
      for (final e in tomorrowExams) {
        final hh = e.date.hour.toString().padLeft(2, '0');
        final mm = e.date.minute.toString().padLeft(2, '0');
        sb.writeln('- ${e.title} at $hh:$mm.');
      }
    }
    // Total classes across the current week (Mon–Sun), so "how many classes do
    // I have this week?" is answered from real data (incl. one-off classes).
    final weekStartMon = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var weekClassCount = 0;
    final perDayCounts = <String>[];
    for (var i = 0; i < 7; i++) {
      final d = weekStartMon.add(Duration(days: i));
      final n = _ref.read(classesForDayProvider(d)).length;
      weekClassCount += n;
      if (n > 0) perDayCounts.add('${Weekdays.short[i]} $n');
    }
    sb.writeln(
        'Classes this week (Mon–Sun): $weekClassCount total${perDayCounts.isNotEmpty ? " (${perDayCounts.join(', ')})" : ""}.');
    // Full weekly recurring timetable, grouped by weekday, so the assistant
    // can plan the week and reason about the schedule on any day.
    final recurring = _ref
        .read(allSessionsProvider)
        .where((c) => c.session.recurring && c.session.dayOfWeek != null)
        .toList();
    if (recurring.isNotEmpty) {
      sb.writeln('Weekly timetable:');
      for (var d = 0; d < 7; d++) {
        final dayClasses = recurring
            .where((c) => c.session.dayOfWeek == d)
            .toList()
          ..sort((a, b) => DateUtilsX.minutesOfDay(a.session.startTime)
              .compareTo(DateUtilsX.minutesOfDay(b.session.startTime)));
        if (dayClasses.isEmpty) continue;
        final parts = dayClasses
            .map((c) =>
                '${c.subject.name} ${c.session.startTime}–${c.session.endTime}')
            .join(', ');
        sb.writeln('- ${Weekdays.full[d]}: $parts');
      }
    }
    // The display setting, so the assistant knows what the student sees
    // (times above are always 24h) and can answer/offer to change it.
    final tf = _ref.read(timeFormatProvider);
    sb.writeln('App time format setting: ${tf.label}'
        '${tf == TimeFormatPref.system ? " (follows the phone clock)" : ""}. '
        'Times above are listed in 24-hour HH:MM.');
    // Classes that look like afternoon times entered without PM.
    final suspect = recurring
        .where((c) => fixAmEnteredClassTime(c.session.startTime, c.session.endTime) != null)
        .length;
    if (suspect > 0) {
      sb.writeln('Note: $suspect class(es) have times between 01:00 and 06:59 or '
          'end before they start — likely afternoon times entered without PM '
          '(a fixClassTimes action corrects them).');
    }
    final gpa = _ref.read(gpaSummaryProvider);
    if (gpa.gradedSubjects > 0) {
      sb.writeln(
          'GPA: ${gpa.gpa.toStringAsFixed(2)} of ${gpa.maxPoints >= 10 ? "10" : "4.0"} (avg ${gpa.averagePercent.toStringAsFixed(0)}%).');
    }
    final tasks = _ref.read(pendingTasksProvider);
    if (tasks.isNotEmpty) {
      sb.writeln('Pending tasks:');
      for (final t in tasks.take(40)) {
        final due =
            t.dueDate != null ? DateUtilsX.prettyDate(t.dueDate!) : 'no date';
        sb.writeln(
            '- ${t.title} (${t.type.label}, due $due, ${t.priority.label})${t.isOverdue ? " [OVERDUE]" : ""}.');
      }
    }
    // Task totals + completed list so the assistant can answer "how many have
    // I completed?" (pendingTasksProvider only exposes not-done items).
    final allTasks = _ref.read(tasksStreamProvider).valueOrNull ?? const [];
    if (allTasks.isNotEmpty) {
      final completed = allTasks.where((t) => t.done).toList();
      sb.writeln(
          'Task totals: ${allTasks.length} total, ${allTasks.length - completed.length} pending, ${completed.length} completed.');
      if (completed.isNotEmpty) {
        sb.writeln('Completed tasks:');
        for (final t in completed.take(15)) {
          sb.writeln('- ${t.title} (${t.type.label}).');
        }
      }
    }
    final exams = _ref.read(upcomingExamsProvider);
    if (exams.isNotEmpty) {
      sb.writeln('Upcoming exams:');
      for (final e in exams.take(10)) {
        final room = e.room;
        sb.writeln(
            '- ${e.title} on ${DateUtilsX.prettyDate(e.date)} (${e.countdownLabel})${room != null && room.isNotEmpty ? ", room $room" : ""}.');
      }
    }
    final pastExams = _ref.read(pastExamsProvider);
    if (pastExams.isNotEmpty) {
      sb.writeln('Past exams:');
      for (final e in pastExams.take(10)) {
        sb.writeln('- ${e.title} on ${DateUtilsX.prettyDate(e.date)}.');
      }
    }
    final study = _ref.read(studyStatsProvider);
    final allStudy =
        _ref.read(studySessionsStreamProvider).valueOrNull ?? const [];
    final allStudyMin = allStudy.fold<int>(0, (a, s) => a + s.minutes);
    sb.writeln(
        'Study focus: ${study.todayMinutes} min today, ${study.weekMinutes} min this week, ${study.streakDays}-day streak, $allStudyMin min all-time across ${allStudy.length} sessions.');
    final habitStreak = _ref.read(bestHabitStreakProvider);
    if (habitStreak > 0) sb.writeln('Best habit streak: $habitStreak days.');
    final currency = _ref.read(currencySymbolProvider);
    final budget = _ref.read(monthlyBudgetProvider);
    // Only state a spending figure once the expenses stream has actually
    // loaded. While it's still syncing valueOrNull is empty (→ 0), which must
    // NOT be reported as a real "you spent 0".
    if (!_ref.read(expensesStreamProvider).hasValue) {
      sb.writeln(
          'Expenses this month: still syncing — do NOT claim the total is 0; '
          'if asked, tell the user their data is loading and to ask again in a moment.');
    } else {
      final spent = _ref.read(monthlyTotalProvider);
      sb.writeln(
          'Expenses this month: $currency${spent.toStringAsFixed(0)}${budget > 0 ? " of $currency${budget.toStringAsFixed(0)} budget" : ""}.');
      // Category-wise breakdown so the assistant can answer "how much on food?".
      final breakdown = _ref.read(categoryBreakdownProvider);
      if (breakdown.isNotEmpty) {
        sb.writeln('Spending by category this month:');
        for (final e in breakdown) {
          sb.writeln(
              '- ${e.key.label}: $currency${e.value.toStringAsFixed(0)}');
        }
      }
      final monthExpenses = _ref.read(thisMonthExpensesProvider);
      if (monthExpenses.isNotEmpty) {
        sb.writeln('Recent expenses:');
        for (final e in monthExpenses.take(10)) {
          sb.writeln(
              '- ${e.title} ($currency${e.amount.toStringAsFixed(0)}, ${e.category.label}, ${DateUtilsX.prettyDate(e.date)}).');
        }
      }
      // Historical months so the assistant can answer about LAST MONTH and
      // earlier (not just the current month). Computed from the full expense
      // history, most recent first.
      final allExpenses =
          _ref.read(expensesStreamProvider).valueOrNull ?? const [];
      final now2 = DateTime.now();
      String monthKey(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final byMonth = <String, double>{};
      final catByMonth = <String, Map<ExpenseCategory, double>>{};
      for (final e in allExpenses) {
        final key = monthKey(e.date);
        byMonth[key] = (byMonth[key] ?? 0) + e.amount;
        (catByMonth[key] ??= <ExpenseCategory, double>{})[e.category] =
            ((catByMonth[key]?[e.category]) ?? 0) + e.amount;
      }
      final currentKey = monthKey(now2);
      final pastKeys = byMonth.keys.where((k) => k != currentKey).toList()
        ..sort((a, b) => b.compareTo(a));
      if (pastKeys.isNotEmpty) {
        sb.writeln('Expense history (previous months, spend per month):');
        for (final k in pastKeys.take(6)) {
          final cats = (catByMonth[k] ?? const {}).entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final top = cats.isNotEmpty
              ? ', top: ${cats.first.key.label} $currency${cats.first.value.toStringAsFixed(0)}'
              : '';
          sb.writeln('- $k: $currency${byMonth[k]!.toStringAsFixed(0)}$top');
        }
        // Explicit last-month category breakdown (a very common question).
        final lastMonth = DateTime(now2.year, now2.month - 1, 1);
        final lastCats = catByMonth[monthKey(lastMonth)];
        if (lastCats != null && lastCats.isNotEmpty) {
          final entries = lastCats.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          sb.writeln('Last month by category:');
          for (final e in entries) {
            sb.writeln(
                '- ${e.key.label}: $currency${e.value.toStringAsFixed(0)}');
          }
        }
      }
    }
    // Per-subject grades.
    if (subjects.isNotEmpty) {
      final gradeLines = <String>[];
      for (final s in subjects) {
        final course = _ref.read(courseGradeProvider(s.id));
        if (course.count == 0) continue;
        gradeLines.add(
            '- ${s.name}: ${course.percent.toStringAsFixed(0)}% (${course.count} graded items).');
      }
      if (gradeLines.isNotEmpty) {
        sb.writeln('Grades by subject:');
        gradeLines.forEach(sb.writeln);
      }
    }
    final gradeItems = _ref.read(gradesStreamProvider).valueOrNull ?? const [];
    if (gradeItems.isNotEmpty) {
      sb.writeln('Individual grades:');
      for (final g in gradeItems.take(15)) {
        sb.writeln(
            '- ${g.title}: ${g.score.toStringAsFixed(0)}/${g.maxScore.toStringAsFixed(0)} (${g.percent.toStringAsFixed(0)}%).');
      }
    }
    // Notes.
    final notes = _ref.read(notesStreamProvider).valueOrNull ?? const [];
    if (notes.isNotEmpty) {
      sb.writeln('Notes (${notes.length}):');
      for (final n in notes.take(15)) {
        final t = n.title.trim().isEmpty ? 'Untitled note' : n.title.trim();
        final preview = n.preview.trim();
        sb.writeln(
            '- $t${preview.isNotEmpty ? ": $preview" : ""}${n.linkedExamId != null ? " [linked to an exam]" : ""}.');
      }
    }
    // Habits.
    final habits = _ref.read(habitsStreamProvider).valueOrNull ?? const [];
    if (habits.isNotEmpty) {
      sb.writeln('Habits:');
      for (final h in habits.take(12)) {
        sb.writeln(
            '- ${h.title} (${h.streak}-day streak, ${h.doneToday ? "done today" : "not done today"}).');
      }
    }
    // Opportunities & Perks (from the CMS-managed `resources` feed), filtered
    // to what the student can actually see (live + country-targeted), so the
    // assistant can answer "what scholarships can I apply to?", "any Spotify
    // deal?", "which perks save the most?" etc. from real, current data.
    final allResources =
        _ref.read(visibleResourcesProvider).valueOrNull ?? const <Resource>[];
    final country = _ref.read(userProfileProvider).valueOrNull?.country;
    final feed = allResources
        .where((r) => r.isInActiveFeed && r.targetsCountry(country))
        .toList();
    final opportunities = feed.where((r) => !r.type.isDiscount).toList();
    final perks = feed.where((r) => r.type.isDiscount).toList();
    if (opportunities.isNotEmpty) {
      sb.writeln('Opportunities available in the app (${opportunities.length}):');
      for (final r in opportunities.take(30)) {
        final parts = <String>['${r.type.label}: ${r.title} — ${r.organization}'];
        if (r.deadline != null) {
          final d = r.daysUntilDeadline;
          parts.add('apply by ${DateUtilsX.prettyDate(r.deadline!)}'
              '${d != null && d >= 0 ? " (in $d days)" : ""}');
        }
        if (r.eligibility != null && r.eligibility!.isNotEmpty) {
          parts.add('eligibility: ${r.eligibility}');
        }
        if (r.paid == true) parts.add('paid/stipend');
        if (r.remote == true) parts.add('remote');
        if (r.applicationUrl != null && r.applicationUrl!.isNotEmpty) {
          parts.add('link: ${r.applicationUrl}');
        }
        sb.writeln('- ${parts.join(' · ')}.');
      }
    }
    if (perks.isNotEmpty) {
      sb.writeln('Student perks/discounts available (${perks.length}):');
      for (final r in perks.take(30)) {
        final parts = <String>[r.brandName];
        if (r.discountText != null && r.discountText!.isNotEmpty) {
          parts.add(r.discountText!);
        }
        if (r.categories.isNotEmpty) parts.add(r.categories.join('/'));
        if (r.redemptionInstructions != null &&
            r.redemptionInstructions!.isNotEmpty) {
          parts.add('how: ${r.redemptionInstructions}');
        }
        final url = r.affiliateUrl ?? r.applicationUrl;
        if (url != null && url.isNotEmpty) parts.add('link: $url');
        sb.writeln('- ${parts.join(' · ')}.');
      }
    }
    return sb.toString().trim();
  }

  void _append(ChatMessage m) =>
      state = state.copyWith(messages: [...state.messages, m]);

  /// The assistant answers data questions from a snapshot built in
  /// [_buildContext]. That snapshot reads several Firestore-backed streams,
  /// which may not have delivered their first value the instant the chat
  /// opens — and a still-loading stream reads as an EMPTY list. That's how the
  /// assistant could once say "you spent 0" moments before the real figure
  /// arrived. Awaiting the first emission (with a safety timeout) guarantees
  /// the context reflects real data. A slow/failing stream never blocks the
  /// chat — we just proceed with whatever has loaded.
  Future<void> _ensureDataLoaded() async {
    Future<void> first(Future<dynamic> f) async {
      await f;
    }

    try {
      await Future.wait([
        first(_ref.read(expensesStreamProvider.future)),
        first(_ref.read(subjectsStreamProvider.future)),
        first(_ref.read(tasksStreamProvider.future)),
        first(_ref.read(gradesStreamProvider.future)),
        first(_ref.read(notesStreamProvider.future)),
        first(_ref.read(habitsStreamProvider.future)),
        first(_ref.read(examsStreamProvider.future)),
        first(_ref.read(studySessionsStreamProvider.future)),
        first(_ref.read(visibleResourcesProvider.future)),
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore — fall back to whatever data is already available.
    }
  }

  Future<void> send(String text, {Uint8List? image, Uint8List? pdf, String? pdfName}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && image == null && pdf == null) return;

    _append(ChatMessage(
      role: ChatRole.user,
      text: trimmed,
      image: image,
      pdfName: pdf != null ? (pdfName ?? 'timetable.pdf') : null,
    ));

    // Feature-usage analytics (never blocks the chat).
    _ref.read(analyticsProvider).aiMessage(hasImage: image != null || pdf != null);
    // Feature discovery: the AI assistant has now been tried.
    _ref.read(featureUsageProvider.notifier).markUsed(FeatureId.aiAssistant);

    if (!_gemini.isConfigured) {
      _append(const ChatMessage(
        role: ChatRole.assistant,
        text: 'I need a Gemini API key to chat. Add a free one in '
            'Settings → AI assistant, then come back. 🙂',
      ));
      return;
    }

    // Enforce the free monthly AI limit (unlimited for Pro). The server also
    // enforces this; the client check gives instant feedback + a paywall.
    final isPro = _ref.read(isProProvider);
    final usageRepo = _ref.read(chatUsageRepositoryProvider);
    if (!isPro) {
      final used = usageRepo == null ? 0 : await usageRepo.currentCount();
      if (used >= ProConstants.freeMonthlyChatLimit) {
        _append(const ChatMessage(role: ChatRole.assistant, text: freeChatLimitMessage));
        _needsPaywall = true;
        return;
      }
    }

    state = state.copyWith(sending: true);
    try {
      final parts = <Map<String, dynamic>>[
        {'text': trimmed.isEmpty ? 'Here is my timetable.' : trimmed},
        if (image != null)
          {
            'inlineData': {
              'data': base64Encode(image),
              'mimeType': 'image/jpeg',
            }
          },
        if (pdf != null)
          {
            'inlineData': {
              'data': base64Encode(pdf),
              'mimeType': 'application/pdf',
            }
          },
      ];
      _history.add({'role': 'user', 'parts': parts});

      // Make sure the user's data streams have loaded before we snapshot them
      // into the assistant's context — otherwise a still-loading stream looks
      // empty and the assistant answers with wrong zeros.
      await _ensureDataLoaded();

      final chatContext = _buildContext();
      var reply = await _gemini.chat(_history, context: chatContext);
      // Claim guard: models sometimes reply "Done — I've marked it complete"
      // WITHOUT emitting the actions block, so nothing changes in the app.
      // Ask once more for the actual action; if it still sends none, we tell
      // the student the truth below instead of echoing the false "done".
      var falseClaim = false;
      if (GeminiService.extractActionsFromReply(reply).isEmpty &&
          GeminiService.extractScheduleFromReply(reply) == null &&
          parseSpendStatement(trimmed) == null && // the spend safety net handles these
          claimsDataChange(reply)) {
        try {
          final retry = await _gemini.chat([
            ..._history,
            {'role': 'model', 'parts': [{'text': reply}]},
            {'role': 'user', 'parts': [{'text': _missingActionsNudge}]},
          ], context: chatContext);
          if (GeminiService.extractActionsFromReply(retry).isNotEmpty) {
            reply = retry;
          } else {
            falseClaim = true;
          }
        } catch (_) {
          falseClaim = true;
        }
      }
      // NOTE: the model turn is appended to `_history` AFTER we've computed the
      // cleaned, user-visible prose (see below). We deliberately store that
      // prose — NOT the raw reply — so the transcript we replay on later turns
      // matches what the user actually saw. Feeding the raw reply back (with
      // its ```actions```/```schedule``` fences and premature "Done — …" lines)
      // pollutes the multi-turn context: the model sees stale action JSON that
      // no longer matches the fresh data snapshot in `_buildContext()`, and in
      // longer chats it starts echoing confirmations without emitting the
      // action block — i.e. it "says done" but nothing runs. Storing the clean
      // prose keeps every turn as trustworthy as a brand-new chat.

      final schedule = GeminiService.extractScheduleFromReply(reply);
      if (schedule != null) {
        _ref.read(analyticsProvider).scheduleImport('chat');
      }
      final actions = GeminiService.extractActionsFromReply(reply);
      ActionOutcome? outcome;
      List<Map<String, dynamic>> pendingDeletes = const [];
      if (actions.isNotEmpty) {
        // When the assistant also proposes a reviewable schedule, the user
        // confirms and commits it from the review card. Auto-executing
        // `subject`/`class` create-actions here would add those same items a
        // first time, producing duplicates once the user taps
        // "Review & add to calendar". So drop them and let the review card be
        // the single source of truth for the schedule. Other action types
        // (exam, task, expense, …) are unrelated and still run.
        final toRun = schedule == null
            ? actions
            : actions.where((a) {
                final t = (a['type'] as String?)?.trim();
                return t != 'subject' && t != 'class';
              }).toList();
        // SECURITY: destructive deletes are NEVER auto-run. They're held and
        // shown as a confirmation card so a prompt-injection (e.g. from a
        // shared image/text) can't silently wipe the user's data. Everything
        // else (create/update/etc.) still runs silently as before.
        pendingDeletes = toRun.where(_isDestructiveAction).toList();
        final safe =
            toRun.where((a) => !_isDestructiveAction(a)).toList();
        if (safe.isNotEmpty) outcome = await _executeActions(safe);
      }
      // Safety net: a plain "I spent 120 on aws" must always be logged, even
      // when the model answered without an expense action (it sometimes asks
      // for a category, or treats tech/cloud spends as off-topic). Only fires
      // for an unambiguous single-amount spend statement.
      String? autoLogged;
      final modelLoggedExpense =
          actions.any((a) => a['type']?.toString().trim() == 'expense');
      if (!modelLoggedExpense && schedule == null && image == null && pdf == null) {
        final spend = parseSpendStatement(trimmed);
        if (spend != null &&
            await _addExpense({
              'title': spend.title,
              'amount': spend.amount,
              'category': spend.category,
            })) {
          (outcome ??= ActionOutcome()).record(true);
          final cur = _ref.read(currencySymbolProvider);
          final amt = spend.amount == spend.amount.roundToDouble()
              ? spend.amount.toStringAsFixed(0)
              : spend.amount.toStringAsFixed(2);
          final cat = ExpenseCategoryX.parse(spend.category).label;
          autoLogged = 'Done — logged $cur$amt for ${spend.title} ($cat). ✅';
        }
      }
      var cleaned = GeminiService.stripScheduleBlock(reply);
      cleaned = GeminiService.stripActionsBlock(cleaned);
      // Belt-and-braces: remove any other fenced code block or bare JSON the
      // model echoed (e.g. a ```json duplicate of a bulk-delete list), so the
      // chat bubble never shows raw script/JSON.
      cleaned = GeminiService.stripAllCodeFences(cleaned);
      cleaned = GeminiService.stripBareActionsJson(cleaned);
      final prose = _cleanMarkdown(cleaned);
      final hasPending = pendingDeletes.isNotEmpty;
      // When deletes are pending we IGNORE the model's prose (it sometimes
      // prematurely says "Done — deleted…") and show a neutral confirmation
      // prompt instead, so the UI never claims a deletion that hasn't happened.
      var finalText = hasPending
          ? 'Just to be safe, please confirm below before I delete anything.'
          : prose.isEmpty
              ? (schedule != null
                  ? 'I put together a schedule below — tap to review it.'
                  : (outcome != null ? 'Done — updated for you. ✅' : 'Okay!'))
              : prose;
      // Honesty guard: the model sometimes says "Done — removed all subjects"
      // even when its action matched nothing (e.g. a "delete all" it couldn't
      // express, or a bad title). If we ran actions but changed nothing, don't
      // echo that false confirmation — tell the user the truth instead. Skipped
      // when there are pending deletes (nothing was claimed done yet).
      if (schedule == null &&
          !hasPending &&
          outcome != null &&
          outcome.attempted > 0 &&
          outcome.succeeded == 0) {
        finalText =
            "I couldn't find anything matching that in your data, so nothing "
            'was changed. Could you tell me exactly which item you mean?';
      }
      // The app logged the spend itself — say exactly that (the model's prose
      // may have been a question or a refusal).
      if (autoLogged != null && !hasPending) finalText = autoLogged;
      // The model claimed a change but never sent an action (even when asked
      // again): nothing happened, so say so rather than "Done".
      if (falseClaim && autoLogged == null && !hasPending && outcome == null) {
        finalText =
            "Sorry — I haven't actually changed anything yet. Could you tell me "
            'the exact name of the item as it appears in the app, and what to '
            'change?';
      }
      // Store the CLEANED, user-visible reply as the model turn (see the note
      // where `reply` is fetched above). This keeps the replayed transcript
      // free of stale action/schedule JSON so multi-turn chats stay accurate.
      _history.add({
        'role': 'model',
        'parts': [
          {'text': finalText}
        ]
      });
      _append(ChatMessage(
        role: ChatRole.assistant,
        text: finalText,
        schedule: schedule,
        pendingActions: hasPending ? pendingDeletes : null,
        pendingSummary: hasPending ? _describeDeletions(pendingDeletes) : null,
      ));
      // Count this successful message toward the free monthly limit.
      if (!isPro) {
        try {
          await usageRepo?.increment();
        } catch (_) {/* never let usage bookkeeping surface as a chat error */}
      }
      // Save the conversation so the user can revisit it from history.
      await _persistSession();
    } catch (e) {
      final outcome = classifyChatError(e, isPro: isPro);
      switch (outcome) {
        case ChatErrorKind.freeLimit:
          // The server is authoritative: e.g. an account re-created with the
          // same email starts with a fresh local counter, but the server still
          // remembers this month's usage. Sync the local mirror so the
          // "remaining" badge shows 0, then prompt the upgrade.
          try {
            await usageRepo?.markExhausted(ProConstants.freeMonthlyChatLimit);
          } catch (_) {/* bookkeeping only */}
          _append(const ChatMessage(role: ChatRole.assistant, text: freeChatLimitMessage));
          _needsPaywall = true;
        case ChatErrorKind.proDailyCap:
          _append(const ChatMessage(
            role: ChatRole.assistant,
            text: "You've reached today's AI usage limit. Please try again "
                'tomorrow. 🙏',
          ));
        case ChatErrorKind.emailUnverified:
          _append(const ChatMessage(
            role: ChatRole.assistant,
            text: 'Please verify your email address to use the AI assistant. '
                'Check your inbox for the verification link. ✉️',
          ));
        case ChatErrorKind.other:
          _append(const ChatMessage(
            role: ChatRole.assistant,
            text: 'Something went wrong reaching the assistant. Please check '
                'your connection and try again.',
          ));
      }
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  // --- Invisible function calling --------------------------------------------

  /// Whether an emitted action is destructive (removes user data). Only
  /// `delete` qualifies — creates/updates are reversible edits and still run
  /// silently. Deletes (single or "delete all") are held for confirmation.
  bool _isDestructiveAction(Map<String, dynamic> a) =>
      (a['type']?.toString().trim()) == 'delete';

  /// Human-readable summary of the deletions awaiting confirmation, e.g.
  /// "all your tasks" or "exam \"DP-800\"". Shown on the confirmation card.
  String _describeDeletions(List<Map<String, dynamic>> deletes) {
    String describe(Map<String, dynamic> a) {
      final entity = (a['entity']?.toString().trim());
      final label = (entity == null || entity.isEmpty) ? 'item' : entity;
      if (a['all'] == true) return 'all your ${label}s';
      final match = a['match']?.toString().trim();
      final subject = a['subject']?.toString().trim();
      if (match != null && match.isNotEmpty) return '$label "$match"';
      if (subject != null && subject.isNotEmpty) return '$label for $subject';
      return 'a $label';
    }

    return deletes.map(describe).join(', ');
  }

  /// Runs the destructive actions the user explicitly confirmed on [message],
  /// then clears the pending state on that message and reports what changed.
  Future<void> confirmPendingActions(ChatMessage message) async {
    final actions = message.pendingActions;
    if (actions == null || actions.isEmpty) return;
    _clearPending(message);
    final outcome = await _executeActions(actions);
    _append(ChatMessage(
      role: ChatRole.assistant,
      text: outcome.succeeded > 0
          ? 'Done — deleted ${outcome.succeeded} item${outcome.succeeded == 1 ? '' : 's'}. ✅'
          : "I couldn't find anything matching that, so nothing was deleted.",
    ));
    await _persistSession();
  }

  /// Discards the pending deletions on [message] without running them.
  void cancelPendingActions(ChatMessage message) {
    _clearPending(message);
    _append(const ChatMessage(
      role: ChatRole.assistant,
      text: 'No problem — I left everything as it is.',
    ));
  }

  /// Replaces [message] in the visible transcript with a copy that has no
  /// pending actions, so the confirmation card collapses and can't fire twice.
  void _clearPending(ChatMessage message) {
    state = state.copyWith(messages: [
      for (final m in state.messages)
        identical(m, message) ? m.withoutPending() : m,
    ]);
  }

  /// Runs the structured actions the assistant emitted, updating Firestore/UI
  /// silently. Failures are swallowed so a bad action never derails the chat.
  /// Returns a tally of what actually changed so the caller can confirm truth-
  /// fully instead of blindly echoing the model's "Done".
  Future<ActionOutcome> _executeActions(List<Map<String, dynamic>> actions) async {
    final outcome = ActionOutcome();
    for (final raw in actions) {
      final a = coerceActionFields(raw);
      final type = a['type']?.toString().trim();
      try {
        switch (type) {
          case 'expense':
            outcome.record(await _addExpense(a));
            break;
          case 'setting':
            outcome.record(await _applySetting(a));
            break;
          case 'fixClassTimes':
            outcome.recordCount(await _fixClassTimes(a));
            break;
          case 'exam':
            outcome.record(await _addExam(a));
            break;
          case 'task':
            outcome.record(await _addTask(a));
            break;
          case 'linkNote':
            outcome.record(await _linkNote(a));
            break;
          case 'attendance':
            outcome.record(await _markAttendance(a));
            break;
          case 'note':
            outcome.record(await _addNote(a));
            break;
          case 'budget':
            outcome.record(await _setBudget(a));
            break;
          case 'subject':
            outcome.record(await _addSubject(a));
            break;
          case 'grade':
            outcome.record(await _addGrade(a));
            break;
          case 'class':
            outcome.record(await _addClass(a));
            break;
          case 'habit':
            outcome.record(await _addHabit(a));
            break;
          case 'habitCheck':
            outcome.record(await _checkHabit(a));
            break;
          case 'study':
            outcome.record(await _addStudy(a));
            break;
          case 'update':
            outcome.record(await _updateEntity(a));
            break;
          case 'createPlan':
            outcome.record(await _createPlan(a));
            break;
          case 'adjustPlan':
            outcome.record(await _adjustPlan(a));
            break;
          case 'completeTopic':
            outcome.record(await _completeTopic(a));
            break;
          case 'delete':
            outcome.recordCount(await _deleteEntity(a));
            break;
        }
      } catch (_) {
        // Invisible automation shouldn't surface stack traces to the user —
        // but a failed action is NOT a success: count it, so the reply never
        // says "Done" for something that threw (e.g. a malformed field).
        outcome.record(false);
      }
    }
    return outcome;
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateUtilsX.fromDateId(s.trim());
    } catch (_) {
      return DateTime.tryParse(s.trim());
    }
  }

  /// Coerce a JSON value to a double, tolerating numbers the model sent as
  /// strings (e.g. "20"). Returns null when it isn't a usable number — so an
  /// action degrades gracefully instead of throwing a ClassCastException that
  /// would silently abort the write while the UI still says "Done ✅".
  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  int? _toInt(dynamic v) => _toDouble(v)?.round();

  String? _findSubjectIdByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final q = name.toLowerCase().trim();
    final subjects = _ref.read(subjectsStreamProvider).valueOrNull ?? const [];
    for (final s in subjects) {
      final n = s.name.toLowerCase();
      if (n == q || n.contains(q) || q.contains(n)) return s.id;
    }
    return null;
  }

  Future<bool> _addExpense(Map<String, dynamic> a) async {
    final amount = _toDouble(a['amount']);
    if (amount == null || amount <= 0) return false;
    final category = ExpenseCategoryX.parse(a['category'] as String?);
    final title = (a['title'] as String?)?.trim();
    await _ref.read(expenseControllerProvider).add(Expense(
          id: '',
          title: (title == null || title.isEmpty) ? category.label : title,
          amount: amount,
          category: category,
          date: DateTime.now(),
        ));
    return true;
  }

  Future<bool> _addExam(Map<String, dynamic> a) async {
    final title = (a['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return false;
    final date = _parseDate(a['date'] as String?) ?? DateTime.now();
    final time = DateUtilsX.parseTime24((a['time'] as String?) ?? '');
    final dt = DateTime(
        date.year, date.month, date.day, time?.hour ?? 9, time?.minute ?? 0);
    String? clean(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    await _ref.read(examControllerProvider).add(Exam(
          id: '',
          title: title,
          subjectId: _findSubjectIdByName(a['subject'] as String?),
          date: dt,
          room: clean(a['room'] as String?),
          note: clean(a['note'] as String?),
        ));
    return true;
  }

  /// `{ "type": "setting", "timeFormat": "12h"|"24h"|"system" }` — changes an
  /// app preference the user asked for (currently the clock style).
  Future<bool> _applySetting(Map<String, dynamic> a) async {
    final raw = a['timeFormat']?.toString();
    if (raw == null || raw.trim().isEmpty) return false;
    await _ref.read(timeFormatProvider.notifier).set(TimeFormatPref.parse(raw));
    return true;
  }

  /// `{ "type": "fixClassTimes", "subject": string|null, "day": string|null }`
  ///
  /// Repairs classes whose afternoon times were entered as morning times (the
  /// student typed "1:40" meaning 1:40 PM, stored as 01:40). See
  /// [fixAmEnteredClassTime] for exactly which times move. Returns how many
  /// classes changed, with a single Undo for the batch.
  Future<int> _fixClassTimes(Map<String, dynamic> a) async {
    final repo = _ref.read(sessionRepositoryProvider);
    if (repo == null) return 0;
    final onlySubject = _findSubjectIdByName(a['subject'] as String?);
    final onlyDay = Weekdays.parse((a['day'] as String?) ?? '');
    final subjects = _ref.read(subjectsStreamProvider).valueOrNull ?? const [];
    final originals = <(String, ClassSession)>[];
    for (final subj in subjects) {
      if (onlySubject != null && subj.id != onlySubject) continue;
      final sessions =
          _ref.read(sessionsForSubjectProvider(subj.id)).valueOrNull ?? const [];
      for (final s in sessions) {
        if (onlyDay != null && s.dayOfWeek != onlyDay) continue;
        final fixed = fixAmEnteredClassTime(s.startTime, s.endTime);
        if (fixed == null) continue;
        await repo.update(s.copyWith(startTime: fixed.$1, endTime: fixed.$2));
        originals.add((subj.id, s));
      }
    }
    if (originals.isNotEmpty) {
      _pendingUndo = PendingUndo('Fixed ${originals.length} class times', () async {
        for (final (_, s) in originals) {
          await repo.update(s);
        }
      });
    }
    return originals.length;
  }

  Future<bool> _addTask(Map<String, dynamic> a) async {
    final title = (a['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return false;
    await _ref.read(taskControllerProvider).add(TaskItem(
          id: '',
          title: title,
          dueDate: _parseDate(a['dueDate'] as String?),
          priority: TaskPriorityX.parse(a['priority'] as String?),
          type: TaskTypeX.parse(a['taskType'] as String?),
          subjectId: _findSubjectIdByName(a['subject'] as String?),
        ));
    return true;
  }

  Future<bool> _linkNote(Map<String, dynamic> a) async {
    final noteQ = (a['noteTitle'] as String?)?.toLowerCase().trim();
    final examQ = (a['examTitle'] as String?)?.toLowerCase().trim();
    if (noteQ == null || noteQ.isEmpty || examQ == null || examQ.isEmpty) {
      return false;
    }
    final notes = _ref.read(notesStreamProvider).valueOrNull ?? const [];
    final exams = _ref.read(examsStreamProvider).valueOrNull ?? const [];

    Note? note;
    for (final n in notes) {
      final t = n.title.toLowerCase();
      if (t.contains(noteQ) || noteQ.contains(t)) {
        note = n;
        break;
      }
    }
    Exam? exam;
    for (final e in exams) {
      final t = e.title.toLowerCase();
      if (t.contains(examQ) || examQ.contains(t)) {
        exam = e;
        break;
      }
    }
    if (note == null || exam == null) return false;
    await _ref.read(noteControllerProvider).update(
          note.copyWith(linkedExamId: exam.id, updatedAt: DateTime.now()),
        );
    return true;
  }

  Future<bool> _markAttendance(Map<String, dynamic> a) async {
    final subjectId = _findSubjectIdByName(a['subject'] as String?);
    if (subjectId == null) return false;
    final status = switch ((a['status'] as String?)?.toLowerCase().trim()) {
      'present' => AttendanceStatus.present,
      'absent' => AttendanceStatus.absent,
      'cancelled' || 'canceled' => AttendanceStatus.cancelled,
      _ => null,
    };
    if (status == null) return false;
    final date = _parseDate(a['date'] as String?) ?? DateTime.now();
    final controller = _ref.read(attendanceControllerProvider);

    // Mark each scheduled occurrence of this subject on [date] keyed by its
    // session start time — the SAME per-occurrence key the home timeline and
    // subject screen use — so a mark made by the AI shows up everywhere (the
    // timeline tile flips out of its "tap to mark" state instead of lingering).
    // Falls back to a subject-level mark only when the subject has no scheduled
    // session that day.
    final day = DateTime(date.year, date.month, date.day);
    final slots = _ref
        .read(classesForDayProvider(day))
        .where((c) => c.subject.id == subjectId)
        .map((c) => c.session.startTime)
        .toSet();
    if (slots.isEmpty) {
      await controller.setForDate(subjectId, date, status);
    } else {
      for (final slot in slots) {
        await controller.setForOccurrence(subjectId, date, slot, status);
      }
    }
    return true;
  }

  Future<bool> _addNote(Map<String, dynamic> a) async {
    final title = (a['title'] as String?)?.trim() ?? '';
    final body = (a['body'] as String?)?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return false;
    await _ref.read(noteControllerProvider).add(Note(
          id: 'new',
          title: title,
          body: body,
          subjectId: _findSubjectIdByName(a['subject'] as String?),
          updatedAt: DateTime.now(),
        ));
    return true;
  }

  Future<bool> _setBudget(Map<String, dynamic> a) async {
    final amount = _toDouble(a['amount']);
    if (amount == null || amount < 0) return false;
    await _ref.read(expenseSettingsProvider).setBudget(amount);
    return true;
  }

  // --- Generic matching + create/update/delete across all entities ----------

  /// Finds the item [q] refers to: exact title, then containment, then keyword
  /// overlap ignoring filler words ("the microsoft fabric video" → "Microsoft
  /// Fabric end-to-end tutorial"). Returns null when nothing — or more than one
  /// thing — fits, so the assistant asks instead of changing the wrong item.
  T? _match<T>(List<T> items, String? q, String Function(T) name) {
    final i = bestMatchIndex([for (final it in items) name(it)], q);
    return i == null ? null : items[i];
  }

  /// Finds the expense the user means, using any combination of amount,
  /// category and title. "delete the 20 rupees food transaction" carries an
  /// amount and a category but often no real title, so title-only matching
  /// fails — this narrows by amount/category first, then title.
  Expense? _matchExpense(
    List<Expense> items,
    String? q,
    num? amount,
    String? categoryName,
  ) {
    final category = (categoryName != null && categoryName.trim().isNotEmpty)
        ? ExpenseCategoryX.parse(categoryName.trim())
        : null;

    var pool = items;
    if (amount != null) {
      final target = amount.toDouble();
      final byAmount =
          items.where((e) => (e.amount - target).abs() < 0.01).toList();
      if (byAmount.isNotEmpty) pool = byAmount;
    }
    if (category != null) {
      final byCat = pool.where((e) => e.category == category).toList();
      if (byCat.isNotEmpty) pool = byCat;
    }

    // Prefer a title match inside the narrowed pool.
    final byTitle = _match(pool, q, (x) => x.title);
    if (byTitle != null) return byTitle;

    // If we narrowed by amount/category, return the most recent candidate.
    // Sort a COPY — never mutate the stream-backed list other widgets read.
    if ((amount != null || category != null) && pool.isNotEmpty) {
      final sorted = [...pool]..sort((a, b) => b.date.compareTo(a.date));
      return sorted.first;
    }

    // Fall back to a plain title search across everything.
    return _match(items, q, (x) => x.title);
  }

  int _pickColor(String? c) {
    if (c != null && c.trim().isNotEmpty) {
      var s = c.trim();
      if (s.startsWith('#')) s = s.substring(1);
      final v = int.tryParse(s, radix: 16);
      if (v != null) return v <= 0xFFFFFF ? (0xFF000000 | v) : v;
    }
    const palette = AppColors.subjectPalette;
    return palette[DateTime.now().microsecondsSinceEpoch % palette.length]
        .toARGB32();
  }

  String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  Future<bool> _addSubject(Map<String, dynamic> a) async {
    final name = (a['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return false;
    final repo = _ref.read(subjectRepositoryProvider);
    if (repo == null) return false;
    await repo.create(Subject(
      id: '',
      name: name,
      colorHex: _pickColor(a['color'] as String?),
      iconKey: a['icon'] as String?,
      startDate: _parseDate(a['startDate'] as String?),
      endDate: _parseDate(a['endDate'] as String?),
    ));
    return true;
  }

  Future<bool> _addGrade(Map<String, dynamic> a) async {
    final title = (a['title'] as String?)?.trim();
    final score = _toDouble(a['score']);
    final maxScore = _toDouble(a['maxScore']);
    if (title == null || title.isEmpty || score == null || maxScore == null ||
        maxScore <= 0) {
      return false;
    }
    await _ref.read(gradeControllerProvider).add(GradeItem(
          id: '',
          title: title,
          score: score,
          maxScore: maxScore,
          weight: _toDouble(a['weight']),
          subjectId: _findSubjectIdByName(a['subject'] as String?),
          date: DateTime.now(),
        ));
    return true;
  }

  Future<bool> _addClass(Map<String, dynamic> a) async {
    final subjectId = _findSubjectIdByName(a['subject'] as String?);
    if (subjectId == null) return false;
    final repo = _ref.read(sessionRepositoryProvider);
    if (repo == null) return false;
    final day = Weekdays.parse((a['day'] as String?) ?? '');
    final start = (a['start'] as String?) ?? '09:00';
    final end =
        DateUtilsX.normalizeEndTime24(start, (a['end'] as String?) ?? '10:00');
    await repo.add(
      subjectId,
      ClassSession(
        id: '',
        subjectId: subjectId,
        recurring: day != null,
        dayOfWeek: day,
        specificDate: day == null ? _parseDate(a['date'] as String?) : null,
        startTime: start,
        endTime: end,
        room: _clean(a['room'] as String?),
      ),
    );
    return true;
  }

  Future<bool> _addHabit(Map<String, dynamic> a) async {
    final title = (a['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return false;
    await _ref.read(habitControllerProvider).add(Habit(
          id: 'new',
          title: title,
          colorHex: _pickColor(a['color'] as String?),
        ));
    return true;
  }

  /// Logs a focus/study session (minutes, optional subject + date).
  Future<bool> _addStudy(Map<String, dynamic> a) async {
    final minutes = _toInt(a['minutes']);
    if (minutes == null || minutes <= 0) return false;
    await _ref.read(studyControllerProvider).logSession(
          minutes: minutes,
          subjectId: _findSubjectIdByName(a['subject'] as String?),
          startedAt: _parseDate(a['date'] as String?),
        );
    return true;
  }

  /// Marks the matching habit done for today (idempotent — never un-checks).
  Future<bool> _checkHabit(Map<String, dynamic> a) async {
    final q = (a['match'] ?? a['title'] ?? a['name']) as String?;
    final habits = _ref.read(habitsStreamProvider).valueOrNull ?? const [];
    final h = _match(habits, q, (x) => x.title);
    if (h == null || h.doneToday) return false;
    await _ref.read(habitControllerProvider).toggleToday(h);
    return true;
  }

  // --- Learning Planner actions ---------------------------------------------

  KnowledgeLevel _parseLevel(dynamic v) {
    switch ('$v'.toLowerCase().trim()) {
      case 'zero':
      case 'beginner':
      case 'none':
        return KnowledgeLevel.zero;
      case 'intermediate':
        return KnowledgeLevel.intermediate;
      case 'advanced':
        return KnowledgeLevel.advanced;
      default:
        return KnowledgeLevel.basics;
    }
  }

  LearningGoal _parseGoal(dynamic v) {
    switch ('$v'.toLowerCase().trim()) {
      case 'syllabus':
        return LearningGoal.syllabus;
      case 'exam':
        return LearningGoal.exam;
      case 'interview':
        return LearningGoal.interview;
      case 'project':
        return LearningGoal.project;
      case 'explore':
        return LearningGoal.explore;
      default:
        return LearningGoal.fundamentals;
    }
  }

  StudyProgram _parseProgram(dynamic v) {
    switch ('$v'.toLowerCase().trim()) {
      case 'school':
        return StudyProgram.school;
      case 'undergraduate':
      case 'undergrad':
        return StudyProgram.undergraduate;
      case 'postgraduate':
      case 'mba':
      case 'pg':
        return StudyProgram.postgraduate;
      case 'professional':
        return StudyProgram.professional;
      default:
        return StudyProgram.general;
    }
  }

  Set<int> _parseStudyDays(dynamic v) {
    if (v is List) {
      final out = <int>{};
      for (final e in v) {
        final d = Weekdays.parse('$e');
        if (d != null) out.add(d);
      }
      if (out.isNotEmpty) return out;
    }
    return {1, 2, 3, 4, 5};
  }

  /// Creates a learning plan. Region is auto-derived from the student's profile
  /// location so jurisdiction-sensitive subjects (law, tax, politics…) are
  /// tailored automatically. Respects the free-plan limit.
  Future<bool> _createPlan(Map<String, dynamic> a) async {
    final subject = (a['subject'] as String?)?.trim();
    if (subject == null || subject.isEmpty) return false;
    if (!_ref.read(canCreatePlanProvider)) return false;
    final country = _ref.read(userProfileProvider).valueOrNull?.country;
    final region = StudyRegionX.fromCountryName(country);
    final gen = _ref.read(learningPlanGeneratorProvider);
    final plan = gen.generate(PlanRequest(
      subject: subject,
      specificTopic: a['specificTopic'] == true,
      level: _parseLevel(a['level']),
      goal: _parseGoal(a['goal']),
      dailyMinutes: _toInt(a['dailyMinutes']) ?? 60,
      studyDays: _parseStudyDays(a['days']),
      targetDate: _parseDate(a['deadline'] as String?) ??
          DateTime.now().add(const Duration(days: 14)),
      region: region,
      program: _parseProgram(a['program']),
    ));
    await _ref.read(learningPlansProvider.notifier).addPlan(plan);
    return true;
  }

  /// Adjusts an existing plan's pace/deadline/days and reschedules.
  Future<bool> _adjustPlan(Map<String, dynamic> a) async {
    final q = (a['subject'] ?? a['match'] ?? a['plan']) as String?;
    final plans = _ref.read(learningPlansProvider);
    final plan = _match(plans, q, (p) => p.subject);
    if (plan == null) return false;
    final minutes = _toInt(a['dailyMinutes']);
    final deadline = _parseDate(a['deadline'] as String?);
    final days = a['days'] is List ? _parseStudyDays(a['days']) : null;
    await _ref.read(learningPlansProvider.notifier).replan(
          plan.id,
          dailyMinutes: minutes,
          studyDays: days,
          targetDate: deadline,
        );
    return true;
  }

  /// Marks a topic within a plan complete.
  Future<bool> _completeTopic(Map<String, dynamic> a) async {
    final q = (a['subject'] ?? a['plan']) as String?;
    final topicQ = (a['topic'] ?? a['title'] ?? a['match']) as String?;
    final plans = _ref.read(learningPlansProvider);
    final plan = _match(plans, q, (p) => p.subject);
    if (plan == null || topicQ == null) return false;
    final topic = _match(plan.topics, topicQ, (t) => t.title);
    if (topic == null) return false;
    await _ref
        .read(learningPlansProvider.notifier)
        .setTopicStatus(plan.id, topic.id, TopicStatus.completed);
    return true;
  }

  Future<bool> _updateEntity(Map<String, dynamic> raw) async {
    // Accept field-name variants ("completed": true → "done": true), and treat
    // an update that requests no actual change as a failure — it used to
    // "succeed" without changing anything, so the reply said "marked complete"
    // while the task stayed open.
    final a = normalizeUpdateAction(raw);
    if (!updateRequestsChange(a)) return false;
    final entity = (a['entity'] as String?)?.toLowerCase().trim();
    final q = (a['match'] ?? a['title'] ?? a['name'])?.toString();
    switch (entity) {
      case 'task':
        final t = _match(_ref.read(tasksStreamProvider).valueOrNull ?? const [],
            q, (x) => x.title);
        if (t == null) return false;
        final updated = t.copyWith(
              title: _clean(a['newTitle'] as String?),
              note: _clean(a['note'] as String?),
              dueDate: _parseDate(a['dueDate'] as String?),
              priority: a['priority'] != null
                  ? TaskPriorityX.parse(a['priority'] as String?)
                  : null,
              type: a['taskType'] != null
                  ? TaskTypeX.parse(a['taskType'] as String?)
                  : null,
              done: a['done'] as bool?,
            );
        await _ref.read(taskControllerProvider).update(updated);
        return true;
      case 'exam':
        final e = _match(_ref.read(examsStreamProvider).valueOrNull ?? const [],
            q, (x) => x.title);
        if (e == null) return false;
        DateTime? newDate;
        final d = _parseDate(a['date'] as String?);
        if (d != null) {
          final tod = DateUtilsX.parseTime24((a['time'] as String?) ?? '');
          newDate = DateTime(d.year, d.month, d.day, tod?.hour ?? e.date.hour,
              tod?.minute ?? e.date.minute);
        }
        await _ref.read(examControllerProvider).update(e.copyWith(
              title: _clean(a['newTitle'] as String?),
              date: newDate,
              room: _clean(a['room'] as String?),
              note: _clean(a['note'] as String?),
            ));
        return true;
      case 'expense':
        final ex = _matchExpense(
            _ref.read(expensesStreamProvider).valueOrNull ?? const [],
            q,
            _toDouble(a['amount']),
            a['category'] as String?);
        if (ex == null) return false;
        await _ref.read(expenseControllerProvider).update(ex.copyWith(
              title: _clean(a['newTitle'] as String?),
              amount: _toDouble(a['newAmount']),
              category: a['newCategory'] != null
                  ? ExpenseCategoryX.parse(a['newCategory'] as String?)
                  : null,
            ));
        return true;
      case 'note':
        final n = _match(_ref.read(notesStreamProvider).valueOrNull ?? const [],
            q, (x) => x.title);
        if (n == null) return false;
        await _ref.read(noteControllerProvider).update(n.copyWith(
              title: _clean(a['newTitle'] as String?),
              body: _clean(a['body'] as String?),
              updatedAt: DateTime.now(),
            ));
        return true;
      case 'grade':
        final g = _match(
            _ref.read(gradesStreamProvider).valueOrNull ?? const [],
            q,
            (x) => x.title);
        if (g == null) return false;
        await _ref.read(gradeControllerProvider).update(g.copyWith(
              title: _clean(a['newTitle'] as String?),
              score: _toDouble(a['score']),
              maxScore: _toDouble(a['maxScore']),
              weight: _toDouble(a['weight']),
            ));
        return true;
      case 'subject':
        final repo = _ref.read(subjectRepositoryProvider);
        final s = _match(
            _ref.read(subjectsStreamProvider).valueOrNull ?? const [],
            q,
            (x) => x.name);
        if (s == null || repo == null) return false;
        await repo.update(s.copyWith(
          name: _clean(a['newName'] as String?),
          colorHex: a['color'] != null ? _pickColor(a['color'] as String?) : null,
          iconKey: a['icon'] as String?,
          startDate: _parseDate(a['startDate'] as String?),
          endDate: _parseDate(a['endDate'] as String?),
        ));
        return true;
      case 'class':
        final subjectId = _findSubjectIdByName(a['subject'] as String?);
        final repo = _ref.read(sessionRepositoryProvider);
        if (subjectId == null || repo == null) return false;
        final sessions =
            _ref.read(sessionsForSubjectProvider(subjectId)).valueOrNull ??
                const [];
        final day = Weekdays.parse((a['day'] as String?) ?? '');
        if (day == null) return false; // need a specific day to pick the class
        ClassSession? target;
        for (final s in sessions) {
          if (s.dayOfWeek == day) {
            target = s;
            break;
          }
        }
        if (target == null) return false;
        final newStart = _clean(a['start'] as String?);
        final newEndRaw = _clean(a['end'] as String?);
        final newDay = Weekdays.parse((a['newDay'] as String?) ?? '');
        final effStart = newStart ?? target.startTime;
        await repo.update(target.copyWith(
          startTime: newStart,
          endTime: newEndRaw != null
              ? DateUtilsX.normalizeEndTime24(effStart, newEndRaw)
              : null,
          dayOfWeek: newDay,
          room: _clean(a['room'] as String?),
        ));
        return true;
      case 'habit':
        final h = _match(
            _ref.read(habitsStreamProvider).valueOrNull ?? const [],
            q,
            (x) => x.title);
        if (h == null) return false;
        await _ref.read(habitControllerProvider).update(h.copyWith(
              title: _clean(a['newTitle'] as String?),
              colorHex:
                  a['color'] != null ? _pickColor(a['color'] as String?) : null,
            ));
        return true;
    }
    return false;
  }

  /// Deletes the matching item(s) and returns how many were removed. When the
  /// action carries "all": true it clears EVERY item of that entity (used for
  /// "delete all my subjects", "clear my tasks", etc.), with a single Undo that
  /// restores the whole batch.
  Future<int> _deleteEntity(Map<String, dynamic> a) async {
    final entity = (a['entity'] as String?)?.toLowerCase().trim();
    final all = a['all'] == true ||
        a['all']?.toString().toLowerCase().trim() == 'true';
    final q = (a['match'] ?? a['title'] ?? a['name']) as String?;
    switch (entity) {
      case 'task':
        final items = _ref.read(tasksStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(taskControllerProvider);
        if (all) {
          for (final t in items) {
            await ctrl.delete(t.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} tasks',
                () async {
              for (final t in items) {
                await ctrl.add(t);
              }
            });
          }
          return items.length;
        }
        final t = _match(items, q, (x) => x.title);
        if (t == null) return 0;
        await ctrl.delete(t.id);
        _pendingUndo = PendingUndo('Deleted "${t.title}"', () => ctrl.add(t));
        return 1;
      case 'exam':
        final items = _ref.read(examsStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(examControllerProvider);
        if (all) {
          for (final e in items) {
            await ctrl.delete(e.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} exams',
                () async {
              for (final e in items) {
                await ctrl.add(e);
              }
            });
          }
          return items.length;
        }
        final e = _match(items, q, (x) => x.title);
        if (e == null) return 0;
        await ctrl.delete(e.id);
        _pendingUndo = PendingUndo('Deleted "${e.title}"', () => ctrl.add(e));
        return 1;
      case 'expense':
        final items = _ref.read(expensesStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(expenseControllerProvider);
        if (all) {
          for (final ex in items) {
            await ctrl.delete(ex.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} expenses',
                () async {
              for (final ex in items) {
                await ctrl.add(ex);
              }
            });
          }
          return items.length;
        }
        final ex = _matchExpense(
            items, q, _toDouble(a['amount']), a['category'] as String?);
        if (ex == null) return 0;
        await ctrl.delete(ex.id);
        _pendingUndo = PendingUndo(
            'Deleted "${ex.title.isEmpty ? ex.category.label : ex.title}"',
            () => ctrl.add(ex));
        return 1;
      case 'note':
        final items = _ref.read(notesStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(noteControllerProvider);
        if (all) {
          for (final n in items) {
            await ctrl.delete(n.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} notes',
                () async {
              for (final n in items) {
                await ctrl.add(n);
              }
            });
          }
          return items.length;
        }
        final n = _match(items, q, (x) => x.title);
        if (n == null) return 0;
        await ctrl.delete(n.id);
        _pendingUndo = PendingUndo(
            'Deleted note "${n.title.isEmpty ? 'Untitled' : n.title}"',
            () => ctrl.add(n));
        return 1;
      case 'grade':
        final items = _ref.read(gradesStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(gradeControllerProvider);
        if (all) {
          for (final g in items) {
            await ctrl.delete(g.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} grades',
                () async {
              for (final g in items) {
                await ctrl.add(g);
              }
            });
          }
          return items.length;
        }
        final g = _match(items, q, (x) => x.title);
        if (g == null) return 0;
        await ctrl.delete(g.id);
        _pendingUndo = PendingUndo('Deleted "${g.title}"', () => ctrl.add(g));
        return 1;
      case 'subject':
        final repo = _ref.read(subjectRepositoryProvider);
        if (repo == null) return 0;
        final items =
            _ref.read(subjectsStreamProvider).valueOrNull ?? const [];
        if (all) {
          for (final s in items) {
            await repo.delete(s.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} subjects',
                () async {
              for (final s in items) {
                await repo.create(s);
              }
            });
          }
          return items.length;
        }
        final s = _match(items, q, (x) => x.name);
        if (s == null) return 0;
        await repo.delete(s.id);
        _pendingUndo = PendingUndo('Deleted "${s.name}"', () => repo.create(s));
        return 1;
      case 'habit':
        final items = _ref.read(habitsStreamProvider).valueOrNull ?? const [];
        final ctrl = _ref.read(habitControllerProvider);
        if (all) {
          for (final h in items) {
            await ctrl.delete(h.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} habits',
                () async {
              for (final h in items) {
                await ctrl.add(h);
              }
            });
          }
          return items.length;
        }
        final h = _match(items, q, (x) => x.title);
        if (h == null) return 0;
        await ctrl.delete(h.id);
        _pendingUndo = PendingUndo('Deleted "${h.title}"', () => ctrl.add(h));
        return 1;
      case 'class':
        final repo = _ref.read(sessionRepositoryProvider);
        if (repo == null) return 0;
        final subjectId = _findSubjectIdByName(a['subject'] as String?);
        if (all) {
          // Clear every class for the named subject, or across all subjects
          // when none was given.
          final subjectIds = subjectId != null
              ? <String>[subjectId]
              : (_ref.read(subjectsStreamProvider).valueOrNull ?? const [])
                  .map((s) => s.id)
                  .toList();
          var count = 0;
          final restores = <Future<void> Function()>[];
          for (final sid in subjectIds) {
            final sessions =
                _ref.read(sessionsForSubjectProvider(sid)).valueOrNull ??
                    const [];
            for (final s in sessions) {
              await repo.delete(sid, s.id);
              restores.add(() => repo.add(sid, s));
              count++;
            }
          }
          if (count > 0) {
            _pendingUndo = PendingUndo('Deleted $count classes', () async {
              for (final r in restores) {
                await r();
              }
            });
          }
          return count;
        }
        if (subjectId == null) return 0;
        final sessions =
            _ref.read(sessionsForSubjectProvider(subjectId)).valueOrNull ??
                const [];
        final day = Weekdays.parse((a['day'] as String?) ?? '');
        if (day == null) return 0; // need a specific day to pick the right class
        ClassSession? target;
        for (final s in sessions) {
          if (s.dayOfWeek == day) {
            target = s;
            break;
          }
        }
        if (target == null) return 0;
        final t = target;
        await repo.delete(subjectId, t.id);
        _pendingUndo =
            PendingUndo('Deleted a class', () => repo.add(subjectId, t));
        return 1;
      case 'plan':
      case 'learning plan':
      case 'learningplan':
      case 'planner':
        final items = _ref.read(learningPlansProvider);
        final ctrl = _ref.read(learningPlansProvider.notifier);
        if (all) {
          for (final p in items) {
            await ctrl.deletePlan(p.id);
          }
          if (items.isNotEmpty) {
            _pendingUndo = PendingUndo('Deleted ${items.length} plans',
                () async {
              for (final p in items) {
                await ctrl.addPlan(p);
              }
            });
          }
          return items.length;
        }
        final p = _match(items, q, (x) => x.subject);
        if (p == null) return 0;
        await ctrl.deletePlan(p.id);
        _pendingUndo =
            PendingUndo('Deleted plan "${p.subject}"', () => ctrl.addPlan(p));
        return 1;
    }
    return 0;
  }

  /// Persists the current conversation to Firestore so it appears in history.
  /// No-op until there's at least one real user message.
  Future<void> _persistSession() async {
    final repo = _ref.read(chatRepositoryProvider);
    if (repo == null) return;
    final stored = state.messages
        .where((m) =>
            m.text.trim().isNotEmpty &&
            !(m.role == ChatRole.assistant && m.text == _welcome.text))
        .toList();
    if (!stored.any((m) => m.isUser)) return;
    _sessionId ??= repo.newId();
    final firstUser = stored.firstWhere((m) => m.isUser);
    final rawTitle = firstUser.text.trim();
    final title =
        rawTitle.length > 60 ? '${rawTitle.substring(0, 60)}…' : rawTitle;
    try {
      await repo.save(ChatSession(
        id: _sessionId!,
        title: title,
        messages: stored,
        updatedAt: DateTime.now(),
      ));
    } catch (_) {
      // History is a convenience; never let a save failure break the chat.
    }
  }

  /// Loads a saved conversation into the live chat, rebuilding the Gemini
  /// context so the assistant can continue where it left off.
  void loadSession(ChatSession session) {
    _sessionId = session.id;
    _history.clear();
    final msgs = <ChatMessage>[];
    for (final m in session.messages) {
      msgs.add(m);
      if (m.text.trim().isNotEmpty) {
        _history.add({
          'role': m.role == ChatRole.user ? 'user' : 'model',
          'parts': [
            {'text': m.text}
          ],
        });
      }
    }
    state = ChatState(messages: msgs.isEmpty ? const [_welcome] : msgs);
  }

  void reset() {
    _history.clear();
    _sessionId = null; // start a fresh conversation; the old one is saved
    state = const ChatState(messages: [_welcome]);
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  // Recreate a fresh (empty) controller whenever the signed-in user changes,
  // so one account can NEVER see another account's in-memory conversation.
  // The saved history in Firestore is already per-uid; this resets the live,
  // in-memory chat + Gemini history on sign-out / account switch.
  ref.watch(currentUidProvider);
  return ChatController(ref.watch(geminiServiceProvider), ref);
});

/// Persistence layer for saved chat conversations (null when signed out).
final chatRepositoryProvider = Provider<ChatRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ChatRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Live list of the user's saved conversations, newest first.
final chatSessionsProvider = StreamProvider<List<ChatSession>>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchSessions();
});
