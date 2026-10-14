// UI: the plan shows one continuous day list (no "WEEK 1 — …" headers), each
// subtopic can be ticked on its own, and Planner home has no week strip.
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/presentation/providers/learning_planner_providers.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/plan_overview_screen.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/planner_home_screen.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

LearningPlan _plan() {
  final today = DateTime.now();
  final d0 = DateTime(today.year, today.month, today.day);
  LearningTopic t(String id, String title, List<String> subs) => LearningTopic(
        id: id,
        title: title,
        estMinutes: 45,
        unit: 'My topics',
        sections: [TopicSection(title: 'Subtopics', minutes: 45, points: subs)],
      );
  return LearningPlan(
    id: 'p1',
    subject: 'Physics',
    specificTopic: false,
    level: KnowledgeLevel.basics,
    goal: LearningGoal.syllabus,
    hasSyllabus: false,
    dailyMinutes: 60,
    studyDays: const {1, 2, 3, 4, 5, 6, 7},
    targetDate: d0.add(const Duration(days: 10)),
    createdAt: d0,
    topics: [
      t('a', 'Kinematics', ['Displacement', 'Velocity']),
      t('b', 'Laws of motion', ['First law']),
    ],
    weeks: [
      WeekPlan(weekNumber: 1, title: 'Foundations', days: [
        DayPlan(dayNumber: 1, date: d0, topicIds: ['a']),
        DayPlan(dayNumber: 2, date: d0.add(const Duration(days: 2)), topicIds: ['b']),
      ]),
    ],
  );
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(overrides: [
    currentUidProvider.overrideWithValue(null), // no Firestore: in-memory only
    learningPlanRepositoryProvider.overrideWithValue(null),
    isProProvider.overrideWith((ref) => true),
    analyticsProvider.overrideWithValue(_NoopAnalytics()),
  ]);
  addTearDown(c.dispose);
  await c.read(learningPlansProvider.notifier).addPlan(_plan());
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

LearningTopic _topic(ProviderContainer c, String id) =>
    c.read(learningPlanByIdProvider('p1'))!.topicById(id)!;

void main() {
  testWidgets('plan: no week headers; subtopics tick one by one', (tester) async {
    final c = await _pump(tester, const PlanOverviewScreen(planId: 'p1'));
    expect(tester.takeException(), isNull);

    expect(find.textContaining('WEEK'), findsNothing);
    expect(find.text('Day 1 · Today'), findsOneWidget);
    expect(find.text('0/2 subtopics'), findsOneWidget);
    // Hand-built plan: no AI-only labels.
    expect(find.text('Your own plan'), findsOneWidget);
    expect(find.text('Why this order?'), findsNothing);

    // Expand Kinematics and tick one subtopic.
    await tester.tap(find.text('Kinematics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Displacement'));
    await tester.pumpAndSettle();
    expect(_topic(c, 'a').status, TopicStatus.learning);
    expect(find.text('1/2 subtopics'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget); // ½ of one of two topics

    // Ticking the last one completes the topic.
    await tester.ensureVisible(find.text('Velocity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Velocity'));
    await tester.pumpAndSettle();
    expect(_topic(c, 'a').isDone, isTrue);
    await tester.scrollUntilVisible(find.text('1 of 2 topics done'), -300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('1 of 2 topics done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner home: no week strip; today + coming up', (tester) async {
    await _pump(tester, const PlannerHomeScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('This week'), findsNothing);
    expect(find.text('Previous week'), findsNothing);
    expect(find.byTooltip('Next week'), findsNothing);
    expect(find.text('Today'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Coming up'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.textContaining('Laws of motion'), findsWidgets);
  });
}
