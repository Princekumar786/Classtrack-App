import 'learning_plan.dart';

/// Pure, UI-free helpers that turn a student's plans into the "what should I
/// do now / am I on track" signals shown on Planner Home. Kept separate from
/// widgets so they can be unit tested with a fixed [now].

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of the week containing [d] (date-only).
DateTime weekStart(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// A study day is done when the student ticked it, or every topic on it is
/// complete. Days with no topics count as done (nothing to study).
bool isDayDone(LearningPlan plan, DayPlan day) {
  if (day.completed) return true;
  return day.topicIds
      .map(plan.topicById)
      .every((t) => t == null || t.isDone);
}

/// Where a plan stands, used for the status chip on each plan card.
enum PlanHealth { onTrack, behind, paused, done }

extension PlanHealthX on PlanHealth {
  String get label => switch (this) {
        PlanHealth.onTrack => 'On track',
        PlanHealth.behind => 'Behind',
        PlanHealth.paused => 'Paused',
        PlanHealth.done => 'Completed',
      };

  /// Sort weight: plans that need attention first.
  int get sortOrder => switch (this) {
        PlanHealth.behind => 0,
        PlanHealth.onTrack => 1,
        PlanHealth.paused => 2,
        PlanHealth.done => 3,
      };
}

/// Number of scheduled days before today that are still not done.
int overdueDays(LearningPlan plan, DateTime now) {
  final today = dateOnly(now);
  var n = 0;
  for (final w in plan.weeks) {
    for (final d in w.days) {
      if (dateOnly(d.date).isBefore(today) && !isDayDone(plan, d)) n++;
    }
  }
  return n;
}

PlanHealth planHealth(LearningPlan plan, DateTime now) {
  if (plan.totalTopics > 0 && plan.remainingTopics == 0) {
    return PlanHealth.done;
  }
  if (plan.paused) return PlanHealth.paused;
  return overdueDays(plan, now) > 0 ? PlanHealth.behind : PlanHealth.onTrack;
}

/// One plan's study session scheduled on a given date.
typedef PlanSession = ({LearningPlan plan, DayPlan day});

/// Every study session (across active plans) scheduled on [date].
List<PlanSession> sessionsOn(List<LearningPlan> plans, DateTime date) {
  final out = <PlanSession>[];
  for (final p in plans) {
    if (p.paused) continue;
    for (final w in p.weeks) {
      for (final d in w.days) {
        if (sameDay(d.date, date) && d.topicIds.isNotEmpty) {
          out.add((plan: p, day: d));
        }
      }
    }
  }
  return out;
}

/// Estimated minutes for a session's topics that are still open.
int openMinutes(PlanSession s) => s.day.topicIds
    .map(s.plan.topicById)
    .where((t) => t != null && !t.isDone)
    .fold(0, (sum, t) => sum + t!.estMinutes);

/// Load on a single day of the week strip.
class DayLoad {
  final DateTime date;
  final int planned;
  final int done;
  const DayLoad(this.date, this.planned, this.done);

  bool get hasStudy => planned > 0;
  bool get allDone => planned > 0 && done == planned;
}

/// Seven [DayLoad]s (Mon–Sun) for the week containing [anyDay].
List<DayLoad> weekLoad(List<LearningPlan> plans, DateTime anyDay) {
  final start = weekStart(anyDay);
  return [
    for (var i = 0; i < 7; i++)
      () {
        final date = start.add(Duration(days: i));
        final sessions = sessionsOn(plans, date);
        final done = sessions.where((s) => isDayDone(s.plan, s.day)).length;
        return DayLoad(date, sessions.length, done);
      }(),
  ];
}

/// Total estimated minutes left across all active (not paused) plans.
int remainingMinutesAll(List<LearningPlan> plans) => plans
    .where((p) => !p.paused)
    .fold(0, (s, p) => s + p.remainingMinutes);

/// The next study sessions AFTER today that still have work, soonest first
/// (across all active plans). Powers the "Coming up" list on Planner Home.
List<PlanSession> upcomingSessions(List<LearningPlan> plans, DateTime now,
    {int limit = 5}) {
  final today = dateOnly(now);
  final out = <PlanSession>[];
  for (final p in plans) {
    if (p.paused) continue;
    for (final d in p.allDays) {
      if (!dateOnly(d.date).isAfter(today)) continue;
      if (d.topicIds.isEmpty || isDayDone(p, d)) continue;
      out.add((plan: p, day: d));
    }
  }
  out.sort((a, b) => a.day.date.compareTo(b.day.date));
  return out.take(limit).toList();
}

/// Today's load across plans: topics scheduled today and how many are done.
({int planned, int done, int minutesLeft}) todayLoad(
    List<LearningPlan> plans, DateTime now) {
  var planned = 0, done = 0, left = 0;
  for (final s in sessionsOn(plans, now)) {
    for (final id in s.day.topicIds) {
      final t = s.plan.topicById(id);
      if (t == null) continue;
      planned++;
      if (t.isDone) {
        done++;
      } else {
        left += (t.estMinutes * (1 - t.progress)).round();
      }
    }
  }
  return (planned: planned, done: done, minutesLeft: left);
}
