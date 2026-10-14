// UI flow: a Pro student wraps up a semester end to end (screen renders with
// the suggested name and counts, confirm archives the data, lands on the
// semester page with SGPA), and a free student hits the Pro prompt instead.
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/auth/domain/app_user.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/features/semesters/presentation/screens/past_semesters_screen.dart';
import 'package:classtrack/features/semesters/presentation/screens/wrap_up_semester_screen.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

const uid = 'u1';

Future<FakeFirebaseFirestore> _pump(WidgetTester tester,
    {required bool isPro}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = FakeFirebaseFirestore();
  final user = db.collection('users').doc(uid);
  await user.collection('subjects').doc('maths').set({
    'name': 'Maths',
    'colorHex': 0xFF6C5CE7,
    'credits': 4,
    'attended': 18,
    'absent': 2,
  });
  await user
      .collection('grades')
      .doc('g1')
      .set({'subjectId': 'maths', 'title': 'Mid', 'score': 85, 'maxScore': 100});

  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      currentUidProvider.overrideWithValue(uid),
      sharedPrefsProvider.overrideWithValue(prefs),
      analyticsProvider.overrideWithValue(_NoopAnalytics()),
      isProProvider.overrideWith((ref) => isPro),
      userProfileProvider.overrideWith((ref) =>
          Stream.value(const AppUser(uid: uid, email: 'a@b.c', semester: 5))),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: child!),
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => startSemesterWrapUp(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  return db;
}

void main() {
  testWidgets('Pro user wraps up a semester end to end', (tester) async {
    final db = await _pump(tester, isPro: true);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Wrap up semester'), findsWidgets);
    expect(find.text('Maths'), findsOneWidget);
    expect(find.text('Semester 5'), findsOneWidget); // from profile
    expect(find.textContaining('Will save 1 subject, 1 grade and 0 exams'),
        findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Wrap up semester'));
    await tester.tap(find.widgetWithText(FilledButton, 'Wrap up semester'));
    await tester.pumpAndSettle();
    expect(find.text('Wrap up Semester 5?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Wrap up'));
    await tester.pumpAndSettle();

    // Lands on the new semester's page with an estimated SGPA.
    expect(find.text('Semester wrapped!'), findsOneWidget);
    expect(find.text('3.70'), findsOneWidget); // 85% -> 3.7 on the 4.0 scale

    final sems = await db.collection('users').doc(uid).collection('semesters').get();
    expect(sems.docs.single['name'], 'Semester 5');
    final maths = await db
        .collection('users')
        .doc(uid)
        .collection('subjects')
        .doc('maths')
        .get();
    expect(maths['semesterId'], sems.docs.single.id);

    // Past semesters list shows it with CGPA; restore brings Maths back.
    await tester.pageBack();
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('open'));
    Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => const PastSemestersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Semester 5'), findsOneWidget);
    expect(find.text('Across 1 past semester'), findsOneWidget);
    expect(find.text('3.70'), findsWidgets);

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore to current semester'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    // The empty-state illustration loops, so don't wait for it to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No past semesters yet'), findsOneWidget);
    final restored = await db
        .collection('users')
        .doc(uid)
        .collection('subjects')
        .doc('maths')
        .get();
    expect(restored.data()!.containsKey('semesterId'), isFalse);
  });

  testWidgets('free user sees the Pro prompt, not the wrap-up screen',
      (tester) async {
    await _pump(tester, isPro: false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Semester wrap-up is a Pro feature'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Maths'), findsNothing);
  });
}
