import 'package:classtrack/features/attendance/presentation/screens/attendance_screen.dart';
import 'package:classtrack/features/chat/presentation/screens/chat_screen.dart';
import 'package:classtrack/features/exams/presentation/screens/exams_screen.dart';
import 'package:classtrack/features/import/presentation/screens/import_screen.dart';
import 'package:classtrack/features/grades/presentation/screens/grades_screen.dart';
import 'package:classtrack/features/home/presentation/screens/home_shell.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/plan_overview_screen.dart';
import 'package:classtrack/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'seed.dart';

/// Captures one screen per store asset. Each test boots a fresh app with the
/// seeded demo account, so screens never leak state into each other.
Future<void> capture(
  WidgetTester tester,
  String name,
  Widget Function() home, {
  Future<void> Function(WidgetTester)? interact,
  List<String> mustShow = const [],
  List<String> mustNotShow = const ['No subjects yet', 'Nothing here yet', 'Something went wrong'],
}) async {
  await tester.runAsync(loadFonts);
  await bootApp(tester, home());
  if (interact != null) await interact(tester);
  // Content checks stand in for eyeballing: the capture must show real data.
  for (final s in mustShow) {
    expect(find.textContaining(s, findRichText: true), findsWidgets, reason: '$name should show "$s"');
  }
  for (final s in mustNotShow) {
    expect(find.textContaining(s, findRichText: true), findsNothing, reason: '$name shows "$s"');
  }
  await shot(tester, name);
  // Tear down so periodic timers / looping animations stop cleanly.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

Future<void> tapNav(WidgetTester tester, String label) async {
  const icons = {
    'Schedule': Icons.calendar_month_outlined,
    'Explore': Icons.explore_outlined,
    'Planner': Icons.auto_awesome_outlined,
  };
  await tester.tap(find.byIcon(icons[label]!).last);
  await settle(tester);
}

void main() {
  testWidgets('01 home', (t) => capture(t, '01_home', () => const HomeShell(),
      mustShow: ['Aarav', 'Linear Algebra']));

  testWidgets('02 attendance', (t) => capture(t, '02_attendance', () => const AttendanceScreen(),
      mustShow: ['Data Structures & Algorithms', '%']));

  testWidgets('03 planner', (t) async {
    await capture(t, '03_planner', () => const HomeShell(),
        interact: (t) => tapNav(t, 'Planner'), mustShow: ['Machine Learning']);
  });

  testWidgets('03b plan roadmap', (t) async {
    await capture(t, '03b_plan_overview', () => _LazyPlan(), mustShow: ['Machine Learning']);
  });

  testWidgets('04 schedule', (t) => capture(t, '04_schedule', () => const HomeShell(),
      interact: (t) => tapNav(t, 'Schedule'), mustShow: ['Data Structures & Algorithms', 'LH-204']));

  testWidgets('05 tasks', (t) => capture(t, '05_tasks', () => const TasksScreen(),
      mustShow: ['OS assignment', 'Networks lab record']));

  testWidgets('09 import', (t) => capture(t, '09_import', () => const ImportScreen(freeAccess: true)));

  testWidgets('10 exams', (t) => capture(t, '10_exams', () => const ExamsScreen()));

  testWidgets('06 grades', (t) => capture(t, '06_grades', () => const GradesScreen(),
      mustShow: ['Data Structures & Algorithms']));

  testWidgets('07 opportunities', (t) => capture(t, '07_opportunities', () => const HomeShell(),
      interact: (t) => tapNav(t, 'Explore'), mustShow: ['Software Engineering Intern']));

  testWidgets('08 assistant', (t) => capture(t, '08_assistant', () => const ChatScreen(),
      mustShow: ['What does my Monday look like?', 'free from 12:00'],
      interact: (t) async {
        await t.enterText(find.byType(TextField), 'What does my Monday look like?');
        await t.pump();
        await t.tap(find.byIcon(Icons.send_rounded));
        await settle(t);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(t);
      }));
}

/// Builds the plan overview once the seed has assigned [demoPlanId].
class _LazyPlan extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PlanOverviewScreen(planId: demoPlanId);
}
