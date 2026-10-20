// Tasks & Assignments: date grouping/summary maths, the new `assignment`
// type (stored + parsed safely), and the redesigned Tasks screen — the
// Assignments view only lists assignments, groups them by date, filters by
// subject, and quick-add creates an assignment.
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/tasks/data/task_repository.dart';
import 'package:classtrack/features/tasks/domain/task_buckets.dart';
import 'package:classtrack/features/tasks/domain/task_item.dart';
import 'package:classtrack/features/tasks/presentation/providers/task_providers.dart';
import 'package:classtrack/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

/// fake_cloud_firestore can't store the real `FieldValue.serverTimestamp()`
/// sentinel, so writes swap it for a plain timestamp.
class _FakeTimeRepo extends TaskRepository {
  final FakeFirebaseFirestore db;
  _FakeTimeRepo(this.db, String uid) : super(db: db, uid: uid);

  @override
  Future<void> add(TaskItem task) => db
      .collection('users')
      .doc(uid)
      .collection('tasks')
      .add({...task.toMap(), 'createdAt': Timestamp.now()});
}

TaskItem _t(String id,
        {DateTime? due,
        bool done = false,
        TaskPriority p = TaskPriority.medium,
        TaskType type = TaskType.task}) =>
    TaskItem(
        id: id, title: id, dueDate: due, done: done, priority: p, type: type);

void main() {
  final now = DateTime(2026, 10, 17, 18, 0);
  final today = DateTime(2026, 10, 17);

  group('bucketFor / groupPendingTasks', () {
    test('puts each pending task in the right date group', () {
      expect(bucketFor(_t('a', due: today.subtract(const Duration(days: 1))), now),
          TaskBucket.overdue);
      expect(bucketFor(_t('b', due: today), now), TaskBucket.today);
      expect(bucketFor(_t('c', due: DateTime(2026, 10, 17, 23, 30)), now),
          TaskBucket.today);
      expect(bucketFor(_t('d', due: today.add(const Duration(days: 1))), now),
          TaskBucket.tomorrow);
      expect(bucketFor(_t('e', due: today.add(const Duration(days: 7))), now),
          TaskBucket.thisWeek);
      expect(bucketFor(_t('f', due: today.add(const Duration(days: 8))), now),
          TaskBucket.later);
      expect(bucketFor(_t('g'), now), TaskBucket.noDate);
    });

    test('groups in order, skips done items, sorts by due then priority', () {
      final groups = groupPendingTasks([
        _t('later', due: today.add(const Duration(days: 20))),
        _t('todayLow', due: today, p: TaskPriority.low),
        _t('todayHigh', due: today, p: TaskPriority.high),
        _t('late', due: today.subtract(const Duration(days: 2))),
        _t('finished', due: today, done: true),
        _t('someday'),
      ], now);
      expect(groups.keys.toList(), [
        TaskBucket.overdue,
        TaskBucket.today,
        TaskBucket.later,
        TaskBucket.noDate,
      ]);
      expect(groups[TaskBucket.today]!.map((t) => t.id),
          ['todayHigh', 'todayLow']);
    });
  });

  test('TaskSummary counts pending, overdue, today, week and done', () {
    final s = TaskSummary.of([
      _t('late', due: today.subtract(const Duration(days: 1))),
      _t('today', due: today),
      _t('tomorrow', due: today.add(const Duration(days: 1))),
      _t('far', due: today.add(const Duration(days: 30))),
      _t('nodate'),
      _t('done', due: today, done: true),
    ], now);
    expect(s.pending, 5);
    expect(s.overdue, 1);
    expect(s.dueToday, 1);
    expect(s.dueThisWeek, 2); // today + tomorrow; overdue not included
    expect(s.completed, 1);
    expect(s.total, 6);
    expect(s.progress, closeTo(1 / 6, 1e-9));
    expect(TaskSummary.of(const [], now).progress, 0);
  });

  test('assignment type round-trips; unknown types fall back to task', () {
    expect(TaskTypeX.parse('assignment'), TaskType.assignment);
    expect(TaskTypeX.parse('course'), TaskType.event);
    expect(TaskTypeX.parse('something-new'), TaskType.task);
    expect(_t('x', type: TaskType.assignment).toMap()['type'], 'assignment');
  });

  group('TasksScreen', () {
    const uid = 'u1';

    Future<FakeFirebaseFirestore> pump(WidgetTester tester,
        {TaskType? initialType}) async {
      // A tall phone so the whole (lazily built) list is on screen.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = FakeFirebaseFirestore();
      final user = db.collection('users').doc(uid);
      await user.collection('subjects').doc('dbms').set(
          {'name': 'DBMS', 'colorHex': 0xFF0EA5E9, 'attended': 0, 'absent': 0});
      await user.collection('subjects').doc('os').set(
          {'name': 'OS', 'colorHex': 0xFF22C55E, 'attended': 0, 'absent': 0});
      final d = DateTime.now();
      final todayTs = Timestamp.fromDate(DateTime(d.year, d.month, d.day));
      final lateTs =
          Timestamp.fromDate(DateTime(d.year, d.month, d.day - 2));
      Future<void> add(String id, Map<String, dynamic> m) =>
          user.collection('tasks').doc(id).set({
            'title': id,
            'done': false,
            'priority': 'medium',
            'createdAt': Timestamp.now(),
            ...m,
          });
      await add('DBMS assignment 2',
          {'type': 'assignment', 'subjectId': 'dbms', 'dueDate': todayTs});
      await add('OS lab record',
          {'type': 'assignment', 'subjectId': 'os', 'dueDate': lateTs});
      await add('Buy groceries', {'type': 'task', 'dueDate': todayTs});

      await tester.pumpWidget(ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          currentUidProvider.overrideWithValue(uid),
          sharedPrefsProvider.overrideWithValue(prefs),
          analyticsProvider.overrideWithValue(_NoopAnalytics()),
          taskRepositoryProvider.overrideWithValue(_FakeTimeRepo(db, uid)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: child!),
          home: TasksScreen(initialType: initialType),
        ),
      ));
      await tester.pumpAndSettle();
      return db;
    }

    testWidgets('Assignments view lists only assignments, grouped by date',
        (tester) async {
      await pump(tester, initialType: TaskType.assignment);

      expect(find.text('Assignments'), findsWidgets);
      expect(find.text('DBMS assignment 2'), findsOneWidget);
      expect(find.text('OS lab record'), findsOneWidget);
      expect(find.text('Buy groceries'), findsNothing);
      expect(find.text('Overdue'), findsWidgets); // group header + tile
      expect(find.text('2 assignments to do'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subject chip filters assignments; All tab shows everything',
        (tester) async {
      await pump(tester, initialType: TaskType.assignment);

      // .first = the subject chip row (the task card's "OS" tag comes later).
      await tester.tap(find.widgetWithText(InkWell, 'OS').first);
      await tester.pumpAndSettle();
      expect(find.text('OS lab record'), findsOneWidget);
      expect(find.text('DBMS assignment 2'), findsNothing);

      await tester.tap(find.text('All  3'));
      await tester.pumpAndSettle();
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('DBMS assignment 2'), findsOneWidget);
    });

    testWidgets('quick add on the Assignments view saves an assignment',
        (tester) async {
      final db = await pump(tester, initialType: TaskType.assignment);

      await tester.enterText(find.byType(TextField), 'Maths worksheet');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final docs = await db
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .where('title', isEqualTo: 'Maths worksheet')
          .get();
      expect(docs.docs, hasLength(1));
      expect(docs.docs.single.data()['type'], 'assignment');
      expect(find.text('Maths worksheet'), findsOneWidget);
    });
  });
}
