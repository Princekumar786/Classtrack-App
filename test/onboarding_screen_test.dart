import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/auth/domain/onboarding_profile.dart';
import 'package:classtrack/features/auth/presentation/providers/onboarding_draft_provider.dart';
import 'package:classtrack/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopAnalytics extends AnalyticsService {
  final events = <String>[];
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async =>
      events.add(name);
}

Future<ProviderContainer> _pump(WidgetTester tester,
    {bool reduceMotion = true, Size size = const Size(1200, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    analyticsProvider.overrideWithValue(_NoopAnalytics()),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const Text('SIGNUP')),
    GoRoute(path: '/login', builder: (_, __) => const Text('LOGIN')),
  ]);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
      // Reduce motion: also stops the looping mascot so pumpAndSettle settles.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
    ),
  ));
  if (reduceMotion) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 2));
  }
  return container;
}

void main() {
  testWidgets('full motion on a small phone: every step renders cleanly',
      (tester) async {
    // 360×640 dp — a compact Android phone.
    await _pump(tester,
        reduceMotion: false, size: const Size(1080, 1920));
    Future<void> settle() => tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Personalise my app'), findsOneWidget);
    await tester.tap(find.text('Personalise my app'));
    await settle();
    await tester.enterText(find.byType(TextField), 'Priya Sharma');
    await settle();
    await tester.tap(find.text('That’s me, Priya'));
    await settle();
    await tester.tap(find.text('Attendance'));
    await settle();
    await tester.tap(find.text('Continue with 1'));
    await settle();
    await tester.ensureVisible(find.text('65%'));
    await settle();
    await tester.tap(find.text('65%'));
    await settle();
    await tester.tap(find.text('Set 65% as my target'));
    await settle();
    final aang = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Aang');
    await tester.ensureVisible(aang);
    await settle();
    await tester.tap(aang);
    await settle();
    await tester.tap(find.text('Looks good'));
    await settle();
    expect(find.text('Building your plan…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await settle();
    expect(find.text('You’re all set, Priya.'), findsOneWidget);
    // Back from the plan skips the one-way "building" step.
    await tester.tap(find.byTooltip('Back'));
    await settle();
    expect(find.text('Pick your sidekick'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dispose the tree so looping animations stop before the test ends.
    await tester.pumpWidget(const SizedBox());
    // Let flutter_animate's entrance-delay timers drain.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('answers personalise each next step and seed the draft',
      (tester) async {
    final c = await _pump(tester);

    expect(find.text('Personalise my app'), findsOneWidget);
    await tester.tap(find.text('Personalise my app'));
    await tester.pumpAndSettle();

    // Name → reflected in the CTA and next heading.
    await tester.enterText(find.byType(TextField), 'Priya');
    await tester.pump();
    await tester.tap(find.text('That’s me, Priya'));
    await tester.pumpAndSettle();
    expect(find.text('What do you want help with?'), findsOneWidget);
    // The mascot reacts using the name (typewriter renders a sizing copy too).
    expect(find.text('Hmm… what’s on your plate, Priya?'), findsWidgets);

    // Focus areas → counted in the CTA.
    await tester.tap(find.text('Attendance'));
    await tester.ensureVisible(find.text('Budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budget'));
    await tester.pump();
    expect(find.text('Continue with 2'), findsOneWidget);
    await tester.tap(find.text('Continue with 2'));
    await tester.pumpAndSettle();

    // Target → translated into "classes you can miss".
    expect(find.text('10'), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            'In a 40-class term you can miss up to 10 classes.'),
        findsOneWidget);
    await tester.tap(find.text('85%'));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    await tester.tap(find.text('Set 85% as my target'));
    await tester.pumpAndSettle();

    // Avatar → skippable.
    expect(find.text('Pick your sidekick'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();

    // "Building your plan" auto-advances.
    expect(find.text('Building your plan…'), findsOneWidget);
    expect(find.text('Setting your 85% attendance goal'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Plan built from the answers.
    expect(find.text('You’re all set, Priya.'), findsOneWidget);
    expect(find.text('Attendance alerts before you dip below 85%'),
        findsOneWidget);
    expect(find.text('A monthly budget that keeps spending on track'),
        findsOneWidget);
    expect(find.text('Reminders ahead of every task and exam'), findsNothing);

    final draft = c.read(onboardingDraftProvider);
    expect(draft.name, 'Priya');
    expect(draft.focusAreas, {FocusArea.attendance, FocusArea.budget});
    expect(draft.targetAttendance, 85);

    await tester.tap(find.text('Create my free account'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNUP'), findsOneWidget);
    expect(c.read(onboardingDoneProvider), isTrue);
  });

  testWidgets('returning users can jump straight to sign in', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
    expect(c.read(onboardingDoneProvider), isTrue);
  });

  testWidgets('rejects markup in the name and back returns a step',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Personalise my app'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '<b>x</b>');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Name can’t contain the characters < or >'),
        findsOneWidget);

    // Empty name is allowed (skipping is always OK).
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What do you want help with?'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What should we call you?'), findsOneWidget);
  });
}
