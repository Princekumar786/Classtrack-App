// Notes redesign: clean previews (no raw Markdown), reading time, and the
// Notes screen — grid of cards, Pinned section, "Study all flashcards" card,
// subject filter and search.
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/notes/domain/note_formatting.dart';
import 'package:classtrack/features/notes/presentation/screens/notes_screen.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:classtrack/shared/widgets/ui_kit.dart';
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

void main() {
  group('notePlainPreview', () {
    test('strips headings, quotes, dividers and link syntax', () {
      const body = '# Normalization\n\n> Key idea\n---\n- 1NF: atomic\n'
          'See [slides](https://x.y) and **bold**';
      expect(notePlainPreview(body),
          'Normalization · Key idea · • 1NF: atomic · See slides and bold');
    });

    test('truncates long text with an ellipsis', () {
      final p = notePlainPreview('word ' * 100, maxChars: 40);
      expect(p.length, 40);
      expect(p.endsWith('…'), isTrue);
    });

    test('reading time', () {
      expect(noteReadMinutes(''), 0);
      expect(noteReadMinutes('a b c'), 1);
      expect(noteReadMinutes('w ' * 401), 3);
    });
  });

  group('NotesScreen', () {
    const uid = 'u1';

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = FakeFirebaseFirestore();
      final user = db.collection('users').doc(uid);
      await user.collection('subjects').doc('dbms').set(
          {'name': 'DBMS', 'colorHex': 0xFF0EA5E9, 'attended': 0, 'absent': 0});
      final now = Timestamp.now();
      await user.collection('notes').doc('n1').set({
        'title': 'Normalization',
        'body': '# 1NF\n- atomic values',
        'subjectId': 'dbms',
        'pinned': true,
        'flashcards': [
          {'id': 'f1', 'q': 'What is 1NF?', 'a': 'Atomic'},
          {'id': 'f2', 'q': 'What is 2NF?', 'a': 'No partial'},
        ],
        'updatedAt': now,
        'createdAt': now,
      });
      await user.collection('notes').doc('n2').set({
        'title': 'Shopping ideas',
        'body': 'Notebook, pens',
        'pinned': false,
        'updatedAt': now,
        'createdAt': now,
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          currentUidProvider.overrideWithValue(uid),
          sharedPrefsProvider.overrideWithValue(prefs),
          analyticsProvider.overrideWithValue(_NoopAnalytics()),
          isProProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: child!),
          home: const NotesScreen(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows pinned section, clean preview and study card',
        (tester) async {
      await pump(tester);
      expect(find.text('2 notes · 2 flashcards'), findsOneWidget);
      expect(find.text('Study all flashcards'), findsOneWidget);
      expect(find.text('PINNED · 1'), findsOneWidget);
      expect(find.text('1NF · • atomic values'), findsOneWidget);
      expect(find.textContaining('# 1NF'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subject filter and search narrow the list', (tester) async {
      await pump(tester);
      // The filter chips scroll sideways; subject chips come after the
      // built-in filters.
      final dbms = find.widgetWithText(FilterPill, 'DBMS');
      await tester.scrollUntilVisible(dbms, 120,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.right)
              .first);
      await tester.ensureVisible(dbms);
      await tester.pumpAndSettle();
      await tester.tap(dbms);
      await tester.pumpAndSettle();
      expect(find.text('Normalization'), findsOneWidget);
      expect(find.text('Shopping ideas'), findsNothing);

      final all = find.widgetWithText(FilterPill, 'All');
      await tester.scrollUntilVisible(all, -120,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.right)
              .first);
      await tester.ensureVisible(all);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pens');
      await tester.pumpAndSettle();
      expect(find.text('Shopping ideas'), findsOneWidget);
      expect(find.text('Normalization'), findsNothing);
    });

    testWidgets('grid / list toggle works', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Grid view'), findsOneWidget);
      expect(find.text('Normalization'), findsOneWidget);
    });
  });
}
