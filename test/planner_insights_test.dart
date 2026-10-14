import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/domain/planner_insights.dart';
import 'package:flutter_test/flutter_test.dart';

LearningPlan _plan({
  required DateTime start,
  bool paused = false,
  Set<String> doneTopics = const {},
}) {
  final topics = [
    for (final id in ['a', 'b', 'c'])
      LearningTopic(
        id: id,
        title: id,
        estMinutes: 30,
        status: doneTopics.contains(id)
            ? TopicStatus.completed
            : TopicStatus.notStarted,
      ),
  ];
  return LearningPlan(
    id: 'p',
    subject: 'DBMS',
    specificTopic: false,
    level: KnowledgeLevel.basics,
    goal: LearningGoal.exam,
    hasSyllabus: false,
    dailyMinutes: 30,
    studyDays: const {1, 2, 3, 4, 5, 6, 7},
    targetDate: start.add(const Duration(days: 10)),
    createdAt: start,
    paused: paused,
    topics: topics,
    weeks: [
      WeekPlan(weekNumber: 1, title: 'W1', days: [
        DayPlan(dayNumber: 1, date: start, topicIds: ['a']),
        DayPlan(
            dayNumber: 2,
            date: start.add(const Duration(days: 1)),
            topicIds: ['b']),
        DayPlan(
            dayNumber: 3,
            date: start.add(const Duration(days: 2)),
            topicIds: ['c']),
      ]),
    ],
  );
}

void main() {
  // Wednesday 14 Oct 2026.
  final now = DateTime(2026, 10, 14, 9);

  test('weekStart is the Monday of the week', () {
    expect(weekStart(now), DateTime(2026, 10, 12));
    expect(weekStart(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
    expect(weekStart(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
  });

  test('plan is behind when past days are unfinished', () {
    final p = _plan(start: DateTime(2026, 10, 12)); // Mon, Tue are past
    expect(overdueDays(p, now), 2);
    expect(planHealth(p, now), PlanHealth.behind);
  });

  test('plan is on track when past days are done', () {
    final p = _plan(start: DateTime(2026, 10, 12), doneTopics: {'a', 'b'});
    expect(overdueDays(p, now), 0);
    expect(planHealth(p, now), PlanHealth.onTrack);
  });

  test('paused and completed plans', () {
    expect(planHealth(_plan(start: DateTime(2026, 10, 12), paused: true), now),
        PlanHealth.paused);
    expect(
        planHealth(
            _plan(start: DateTime(2026, 10, 12), doneTopics: {'a', 'b', 'c'}),
            now),
        PlanHealth.done);
  });

  test('sessionsOn and weekLoad count scheduled and done days', () {
    final p = _plan(start: DateTime(2026, 10, 12), doneTopics: {'a'});
    expect(sessionsOn([p], DateTime(2026, 10, 13)).length, 1);
    expect(sessionsOn([p], DateTime(2026, 10, 16)), isEmpty);

    final week = weekLoad([p], now);
    expect(week.length, 7);
    expect(week[0].planned, 1);
    expect(week[0].allDone, isTrue);
    expect(week[1].done, 0);
    expect(week.fold(0, (s, d) => s + d.planned), 3);
  });

  test('paused plans are left out of the agenda and remaining time', () {
    final p = _plan(start: DateTime(2026, 10, 12), paused: true);
    expect(sessionsOn([p], DateTime(2026, 10, 12)), isEmpty);
    expect(remainingMinutesAll([p]), 0);
    expect(remainingMinutesAll([_plan(start: DateTime(2026, 10, 12))]), 90);
  });
}
