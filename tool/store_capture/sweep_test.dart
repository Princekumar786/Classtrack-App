// 360dp layout sweep — renders every user-facing screen (seeded demo account)
// on a compact Android phone at normal and large text, and FAILS on any
// RenderFlex overflow or other build/layout exception.
//
// Run: flutter test tool/store_capture/sweep_test.dart
import 'package:classtrack/features/attendance/presentation/screens/attendance_screen.dart';
import 'package:classtrack/features/auth/presentation/screens/edit_profile_screen.dart';
import 'package:classtrack/features/auth/presentation/screens/login_screen.dart';
import 'package:classtrack/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:classtrack/features/auth/presentation/screens/signup_screen.dart';
import 'package:classtrack/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:classtrack/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:classtrack/features/chat/presentation/screens/chat_screen.dart';
import 'package:classtrack/features/exams/presentation/screens/exams_screen.dart';
import 'package:classtrack/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:classtrack/features/export/presentation/screens/export_screen.dart';
import 'package:classtrack/features/focus/presentation/screens/focus_screen.dart';
import 'package:classtrack/features/grades/presentation/screens/grades_screen.dart';
import 'package:classtrack/features/habits/presentation/screens/habits_screen.dart';
import 'package:classtrack/features/home/presentation/screens/home_shell.dart';
import 'package:classtrack/features/insights/presentation/screens/daily_agenda_screen.dart';
import 'package:classtrack/features/insights/presentation/screens/insights_screen.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/custom_plan_builder_screen.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/plan_overview_screen.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/plan_progress_screen.dart';
import 'package:classtrack/features/learning_planner/presentation/screens/planner_home_screen.dart';
import 'package:classtrack/features/moments/presentation/screens/moments_screen.dart';
import 'package:classtrack/features/notes/presentation/screens/notes_screen.dart';
import 'package:classtrack/features/opportunities/presentation/screens/discounts_screen.dart';
import 'package:classtrack/features/opportunities/presentation/screens/opportunities_screen.dart';
import 'package:classtrack/features/opportunities/presentation/screens/saved_opportunities_screen.dart';
import 'package:classtrack/features/referral/presentation/screens/referral_screen.dart';
import 'package:classtrack/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:classtrack/features/settings/presentation/screens/privacy_policy_screen.dart';
import 'package:classtrack/features/settings/presentation/screens/settings_screen.dart';
import 'package:classtrack/features/subjects/presentation/screens/subjects_screen.dart';
import 'package:classtrack/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:classtrack/features/subscription/presentation/screens/pro_status_screen.dart';
import 'package:classtrack/features/subscription/presentation/widgets/upgrade_prompt.dart';
import 'package:classtrack/features/tasks/presentation/screens/tasks_screen.dart';
import 'package:classtrack/features/tips/presentation/screens/tips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'seed.dart';

final Map<String, Widget Function()> screens = {
  'Home': () => const HomeShell(),
  'Schedule': () => const ScheduleScreen(),
  'Opportunities': () => const OpportunitiesScreen(),
  'Planner home': () => const PlannerHomeScreen(),
  'Plan overview': () => PlanOverviewScreen(planId: demoPlanId),
  'Plan progress': () => PlanProgressScreen(planId: demoPlanId),
  'Custom plan builder': () => const CustomPlanBuilderScreen(),
  'Attendance': () => const AttendanceScreen(),
  'Subjects': () => const SubjectsScreen(),
  'Calendar': () => const CalendarScreen(),
  'Tasks': () => const TasksScreen(),
  'Exams': () => const ExamsScreen(),
  'Grades': () => const GradesScreen(),
  'Notes': () => const NotesScreen(),
  'Habits': () => const HabitsScreen(),
  'Expenses': () => const ExpensesScreen(),
  'Focus': () => const FocusScreen(),
  'Chat': () => const ChatScreen(),
  'Insights': () => const InsightsScreen(),
  'Daily agenda': () => const DailyAgendaScreen(),
  'Discounts': () => const DiscountsScreen(),
  'Saved opportunities': () => const SavedOpportunitiesScreen(),
  'Moments': () => const MomentsScreen(),
  'Referral': () => const ReferralScreen(),
  'Settings': () => const SettingsScreen(),
  'Edit profile': () => const EditProfileScreen(),
  'Export': () => const ExportScreen(),
  'Tips': () => const TipsScreen(),
  'Pro status': () => const ProStatusScreen(),
  'Privacy policy': () => const PrivacyPolicyScreen(),
  'Login': () => const LoginScreen(),
  'Signup': () => const SignupScreen(),
  'Verify email': () => const VerifyEmailScreen(),
  'Onboarding': () => const OnboardingScreen(),
  'Paywall (scans)': () => const PaywallScreen(reason: UpgradeReason.timetableScans),
  'Upgrade prompt': () => const Scaffold(
      body: Align(alignment: Alignment.bottomCenter,
          child: UpgradePromptSheet(reason: UpgradeReason.aiChat))),
};

const sizes = {'360x780': Size(1080, 2340), '360x640': Size(1080, 1920)};
const scales = [1.0, 1.3, 1.5];

/// Captures layout/build errors without failing the test immediately, so one
/// run reports every problem across every screen.
final problems = <String>[];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== SWEEP RESULT: ${problems.length} problem(s) =====');
    for (final p in problems) {
      // ignore: avoid_print
      print(p);
    }
    expect(problems, isEmpty, reason: 'Layout problems found at 360dp — see list above');
  });

  for (final entry in screens.entries) {
    for (final size in sizes.entries) {
      for (final scale in scales) {
        for (final pro in [true, false]) {
          // Free-tier variants only matter at the common size + normal text.
          if (!pro && (size.key != '360x780' || scale != 1.0)) continue;
          final label = '${entry.key} @${size.key} x$scale ${pro ? 'pro' : 'free'}';
          testWidgets(label, (tester) async {
            final seen = <String>{};
            final prev = FlutterError.onError;
            FlutterError.onError = (d) {
              final msg = d.exceptionAsString().split('\n').first;
              final where = _userFrame(d);
              final key = '$msg|$where';
              if (seen.add(key)) problems.add('[$label] $msg  @ $where');
            };
            try {
              await tester.runAsync(loadFonts);
              await bootApp(tester, entry.value(),
                  physicalSize: size.value, textScale: scale, isPro: pro);
              // Scroll the main list to the bottom so lazily-built rows lay out.
              final scrollables = find.byType(Scrollable);
              if (scrollables.evaluate().isNotEmpty) {
                for (var i = 0; i < 6; i++) {
                  await tester.drag(scrollables.first, const Offset(0, -600), warnIfMissed: false);
                  await tester.pump(const Duration(milliseconds: 200));
                }
              }
              await tester.pump(const Duration(seconds: 1));
              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 5));
            } catch (e) {
              problems.add('[$label] THREW: ${e.toString().split('\n').first}');
            } finally {
              FlutterError.onError = prev;
            }
          });
        }
      }
    }
  }
}

/// First stack/creator location inside lib/ — points at the offending widget.
String _userFrame(FlutterErrorDetails d) {
  final text = '${d.toString()}\n${d.stack}';
  final m = RegExp(r'(lib/[\w/]+\.dart):(\d+)(:\d+)?').firstMatch(text) ??
      RegExp(r'package:classtrack/([\w/]+\.dart):(\d+)').firstMatch(text);
  return m == null ? '?' : '${m.group(1)}:${m.group(2)}';
}

