import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/domain/plan_builder_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  linkTests();
  // Monday 12 Oct 2026.
  final mon = DateTime(2026, 10, 12, 9);
  const weekdays = {1, 2, 3, 4, 5};

  test('studyDaysBetween counts chosen weekdays inclusive', () {
    expect(studyDaysBetween(mon, DateTime(2026, 10, 18), weekdays), 5);
    expect(studyDaysBetween(mon, DateTime(2026, 10, 18), {6, 7}), 2);
    expect(studyDaysBetween(mon, DateTime(2026, 10, 11), weekdays), 0);
    expect(studyDaysBetween(mon, DateTime(2026, 10, 18), {}), 0);
  });

  test('PlanFit verdicts', () {
    expect(const PlanFit(0, 5, 60).status, FitStatus.empty);
    expect(const PlanFit(200, 5, 60).status, FitStatus.fits); // 67%
    expect(const PlanFit(280, 5, 60).status, FitStatus.tight); // 93%
    const over = PlanFit(450, 5, 60);
    expect(over.status, FitStatus.overflow);
    expect(over.neededPerDay, 90);
    expect(over.daysNeeded, 8);
    expect(const PlanFit(60, 0, 60).status, FitStatus.overflow);
  });

  test('suggestions fix an overflowing plan', () {
    expect(suggestDailyMinutes(90, [30, 60, 90, 120]), 90);
    expect(suggestDailyMinutes(70, [120, 30, 60, 90]), 90);
    expect(suggestDailyMinutes(200, [30, 60, 120]), isNull);
    // 8 weekdays from Mon 12 Oct → Wed 21 Oct.
    expect(earliestFinish(mon, 8, weekdays), DateTime(2026, 10, 21));
    expect(earliestFinish(mon, 3, {}), isNull);
  });

  test('parseTopicList strips bullets, numbers and reads durations', () {
    final t = parseTopicList('''
1. Arrays & Strings - 45 min
  • Linked lists
- Trees (1.5h)
* Graphs: 2 hours

2) arrays & strings
a) Dynamic programming 90m
Big O
''');
    expect(t.map((e) => e.title).toList(), [
      'Arrays & Strings',
      'Trees',
      'Graphs',
      'Dynamic programming',
      'Big O',
    ]);
    expect(t.map((e) => e.minutes).toList(), [45, 90, 120, 90, null]);
    // The indented line under a topic is one of its subtopics.
    expect(t.first.subtopics, ['Linked lists']);
  });

  test('parseTopicList reads indented / ◦ lines as subtopics', () {
    final t = parseTopicList('''
1. Kinematics – 45 min
   - Displacement
   - Velocity
   - velocity
◦ Acceleration
2. Laws of motion
\t• Newton's first law
3. Work & energy
''');
    expect(t.map((e) => e.title).toList(),
        ['Kinematics', 'Laws of motion', 'Work & energy']);
    expect(t[0].subtopics, ['Displacement', 'Velocity', 'Acceleration']);
    expect(t[1].subtopics, ["Newton's first law"]);
    expect(t[2].subtopics, isEmpty);
    // An indented first line has no parent, so it's a topic.
    expect(parseTopicList('  Optics\n    - Lenses').single.subtopics, ['Lenses']);
  });

  test('parseTopicList keeps a bare number title and caps the count', () {
    expect(parseTopicList('Chapter 5').single.title, 'Chapter 5');
    expect(parseTopicList(List.generate(80, (i) => 'T$i').join('\n')).length, 60);
  });
}


void linkTests() {
  group('study links', () {
    test('normalizeStudyLink adds https and rejects unsafe schemes', () {
      expect(normalizeStudyLink('youtube.com/watch?v=1'),
          'https://youtube.com/watch?v=1');
      expect(normalizeStudyLink(' https://a.com/x '), 'https://a.com/x');
      expect(normalizeStudyLink('javascript:alert(1)'), isNull);
      expect(normalizeStudyLink('file:///etc/passwd'), isNull);
      expect(normalizeStudyLink('hello'), isNull);
      expect(normalizeStudyLink(''), isNull);
    });

    test('links round-trip through JSON and bad ones are dropped', () {
      final t = LearningTopic(
          id: 'a', title: 'A', estMinutes: 30, links: ['https://a.com']);
      final back = LearningTopic.fromJson(
          {...t.toJson(), 'links': ['https://a.com', 'javascript:x']});
      expect(back.links, ['https://a.com']);
      // Old topics without links still load.
      final old = Map<String, dynamic>.from(t.toJson())..remove('links');
      expect(LearningTopic.fromJson(old).links, isEmpty);
    });
  });
}
