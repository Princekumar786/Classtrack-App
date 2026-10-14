// Subtopic ticking: students can mark each subtopic on its own; the topic's
// status, the plan's progress ring and the planner home stats follow from it.
import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/domain/planner_insights.dart';
import 'package:flutter_test/flutter_test.dart';

LearningTopic _topic(String id, {List<String> points = const ['A', 'B', 'C']}) =>
    LearningTopic(
      id: id,
      title: id,
      estMinutes: 60,
      sections: [TopicSection(title: 'Subtopics', minutes: 60, points: points)],
    );

String _k(String p) => LearningTopic.subtopicKey('Subtopics', p);

LearningPlan _plan(List<LearningTopic> topics, DateTime start) => LearningPlan(
      id: 'p',
      subject: 'Physics',
      specificTopic: false,
      level: KnowledgeLevel.basics,
      goal: LearningGoal.syllabus,
      hasSyllabus: false,
      dailyMinutes: 60,
      studyDays: const {1, 2, 3, 4, 5, 6, 7},
      targetDate: start.add(const Duration(days: 10)),
      createdAt: start,
      topics: topics,
      weeks: [
        WeekPlan(weekNumber: 1, title: 'Foundations', days: [
          for (var i = 0; i < topics.length; i++)
            DayPlan(
                dayNumber: i + 1,
                date: start.add(Duration(days: i)),
                topicIds: [topics[i].id]),
        ]),
        WeekPlan(weekNumber: 2, title: 'Core', days: [
          DayPlan(
              dayNumber: topics.length + 1,
              date: start.add(Duration(days: topics.length + 5)),
              topicIds: [topics.first.id]),
        ]),
      ],
    );

void main() {
  group('subtopics', () {
    test('lists section points in order, skipping blanks and duplicates', () {
      final t = _topic('t', points: ['A', ' ', 'B', 'A']);
      expect(t.subtopics.map((s) => s.text), ['A', 'B']);
      // No sections → objectives are the subtopics.
      final o = LearningTopic(id: 'o', title: 'o', estMinutes: 30, objectives: ['X']);
      expect(o.subtopicTotal, 1);
    });

    test('ticking drives the topic status', () {
      final t = _topic('t');
      applySubtopic(t, _k('A'), true);
      expect(t.status, TopicStatus.learning);
      expect(t.subtopicsDone, 1);
      expect(t.progress, closeTo(1 / 3, 1e-9));
      applySubtopic(t, _k('B'), true);
      applySubtopic(t, _k('C'), true);
      expect(t.status, TopicStatus.completed, reason: 'last tick completes it');
      expect(t.progress, 1);

      // Unticking one on a completed topic keeps the other two.
      applySubtopic(t, _k('B'), false);
      expect(t.status, TopicStatus.learning);
      expect(t.doneSubtopics, {_k('A'), _k('C')});

      applySubtopic(t, _k('A'), false);
      applySubtopic(t, _k('C'), false);
      expect(t.subtopicsDone, 0);
      expect(t.status, TopicStatus.learning,
          reason: 'stays "still learning" — not silently reset');
    });

    test('unknown keys are ignored', () {
      final t = _topic('t');
      applySubtopic(t, 'nope', true);
      expect(t.doneSubtopics, isEmpty);
      expect(t.status, TopicStatus.notStarted);
    });

    test('marking the whole topic ticks / clears every subtopic', () {
      final t = _topic('t');
      applyTopicStatus(t, TopicStatus.completed);
      expect(t.doneSubtopics.length, 3);
      applyTopicStatus(t, TopicStatus.learning);
      expect(t.doneSubtopics.length, 3);
      applyTopicStatus(t, TopicStatus.notStarted);
      expect(t.doneSubtopics, isEmpty);
    });

    test('survives save/load and copyWith', () {
      final t = _topic('t');
      applySubtopic(t, _k('B'), true);
      final back = LearningTopic.fromJson(t.toJson());
      expect(back.doneSubtopics, {_k('B')});
      expect(back.status, TopicStatus.learning);
      final copy = t.copyWith(estMinutes: 90);
      expect(copy.doneSubtopics, {_k('B')});
      copy.doneSubtopics.add(_k('C'));
      expect(t.doneSubtopics, {_k('B')}, reason: 'copy owns its own set');
      // Old saved topics without the field load fine.
      final legacy = t.toJson()..remove('doneSubtopics');
      expect(LearningTopic.fromJson(legacy).doneSubtopics, isEmpty);
    });
  });

  group('plan progress', () {
    final start = DateTime(2026, 10, 14);

    test('ring counts partial topics', () {
      final a = _topic('a'), b = _topic('b');
      final p = _plan([a, b], start);
      expect(p.percent, 0);
      applySubtopic(a, _k('A'), true); // 1/3 of one of two topics
      expect(p.percent, closeTo(100 / 6, 1e-9));
      applyTopicStatus(b, TopicStatus.completed);
      expect(p.percent, closeTo((1 / 3 + 1) / 2 * 100, 1e-9));
      expect(p.completedTopics, 1);
    });

    test('allDays flattens weeks; custom plans are recognised', () {
      final p = _plan([_topic('a'), _topic('b')], start);
      expect(p.allDays.map((d) => d.dayNumber), [1, 2, 3]);
      expect(p.isCustom, isFalse);
      final custom = _plan([
        LearningTopic(id: 'u', title: 'u', estMinutes: 30, unit: 'My topics'),
      ], start);
      expect(custom.isCustom, isTrue);
    });
  });

  group('planner home (no week strip)', () {
    final now = DateTime(2026, 10, 14, 9);

    test('coming up = days after today with work, soonest first', () {
      final topics = [_topic('a'), _topic('b'), _topic('c')];
      final p = _plan(topics, DateTime(2026, 10, 14)); // days 14, 15, 16, 22
      applyTopicStatus(topics[1], TopicStatus.completed); // 15th is done
      final up = upcomingSessions([p], now);
      expect(up.map((s) => s.day.date.day), [16, 22]);
      expect(upcomingSessions([p], now, limit: 1).length, 1);
      expect(upcomingSessions([p.copyWith(paused: true)], now), isEmpty);
    });

    test('today load counts topics and minutes left incl. ticked subtopics', () {
      final a = _topic('a');
      final p = _plan([a, _topic('b')], DateTime(2026, 10, 14));
      expect(todayLoad([p], now), (planned: 1, done: 0, minutesLeft: 60));
      applySubtopic(a, _k('A'), true);
      expect(todayLoad([p], now).minutesLeft, 40);
      applyTopicStatus(a, TopicStatus.completed);
      expect(todayLoad([p], now), (planned: 1, done: 1, minutesLeft: 0));
    });
  });
}
