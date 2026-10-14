// Unsaved import drafts: a scanned timetable must survive the app being
// killed / swiped from recents before "Add to ClassTrack" is tapped.
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/providers/gemini_provider.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/import/data/import_draft_store.dart';
import 'package:classtrack/features/import/domain/parsed_schedule.dart';
import 'package:classtrack/features/import/presentation/widgets/import_draft_banner.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:classtrack/services/gemini_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

const uid = 'u1';

ParsedSchedule _sample() => ParsedSchedule(
      confidence: 'medium',
      subjects: [
        ParsedSubject(
          name: 'DBMS',
          professor: 'Dr. Rao',
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 12, 1),
          sessions: [
            ParsedSession(day: 'Monday', start: '09:00', end: '10:00', room: 'A1'),
            ParsedSession(
                day: 'Friday',
                start: '14:00',
                end: '15:00',
                date: DateTime(2026, 10, 30)),
          ],
        ),
        ParsedSubject(name: 'OS', sessions: [], include: false),
      ],
      tasks: [
        ParsedTask(
            title: 'Lab report',
            due: DateTime(2026, 10, 20),
            link: 'https://x.y',
            include: false),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('draft JSON keeps every field the review screen can edit', () {
    final back = ParsedSchedule.fromDraftJson(_sample().toDraftJson());
    expect(back.confidence, 'medium');
    final dbms = back.subjects.first;
    expect(dbms.name, 'DBMS');
    expect(dbms.professor, 'Dr. Rao');
    expect(dbms.startDate, DateTime(2026, 8, 1));
    expect(dbms.endDate, DateTime(2026, 12, 1));
    expect(dbms.sessions.first.room, 'A1');
    expect(dbms.sessions.first.isRecurring, isTrue);
    expect(dbms.sessions.last.date, DateTime(2026, 10, 30));
    expect(back.subjects.last.include, isFalse);
    final task = back.tasks.single;
    expect((task.title, task.due, task.link, task.include),
        ('Lab report', DateTime(2026, 10, 20), 'https://x.y', false));
    // Lists must be growable: the review screen removes items in place.
    expect(() => back.tasks.removeAt(0), returnsNormally);
  });

  group('ImportDraftStore', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('survives an app restart (new store, same prefs)', () async {
      await ImportDraftStore(ScopedPrefs(prefs, uid)).save(_sample());
      final reopened = ImportDraftStore(ScopedPrefs(prefs, uid));
      expect(reopened.state?.schedule.subjects.first.name, 'DBMS');
    });

    test('is private to each account', () async {
      await ImportDraftStore(ScopedPrefs(prefs, 'a')).save(_sample());
      expect(ImportDraftStore(ScopedPrefs(prefs, 'b')).state, isNull);
      expect(ImportDraftStore(ScopedPrefs(prefs, null)).state, isNull);
    });

    test('expires after 7 days and drops corrupt data', () async {
      var now = DateTime(2026, 10, 1);
      await ImportDraftStore(ScopedPrefs(prefs, uid), clock: () => now)
          .save(_sample());
      now = DateTime(2026, 10, 7);
      expect(ImportDraftStore(ScopedPrefs(prefs, uid), clock: () => now).state,
          isNotNull);
      now = DateTime(2026, 10, 9);
      expect(ImportDraftStore(ScopedPrefs(prefs, uid), clock: () => now).state,
          isNull);
      expect(ScopedPrefs(prefs, uid).getString(ImportDraftStore.key), isNull);

      await ScopedPrefs(prefs, uid).setString(ImportDraftStore.key, '{oops');
      expect(ImportDraftStore(ScopedPrefs(prefs, uid)).state, isNull);
    });

    test('clear and empty schedules remove the draft', () async {
      final store = ImportDraftStore(ScopedPrefs(prefs, uid));
      await store.save(_sample());
      await store.save(ParsedSchedule(subjects: [], confidence: 'low'));
      expect(store.state, isNull);
      await store.save(_sample());
      await store.clear();
      expect(ImportDraftStore(ScopedPrefs(prefs, uid)).state, isNull);
    });
  });

  group('ReviewScreen', () {
    late FakeFirebaseFirestore db;
    late SharedPreferences prefs;

    Future<ProviderContainer> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = FakeFirebaseFirestore();
      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(db),
        currentUidProvider.overrideWithValue(uid),
        sharedPrefsProvider.overrideWithValue(prefs),
        analyticsProvider.overrideWithValue(_NoopAnalytics()),
        geminiServiceProvider.overrideWithValue(GeminiService(_NoFunctions())),
        isProProvider.overrideWith((ref) => true),
      ]);
      addTearDown(container.dispose);
      await container.read(importDraftProvider.notifier).save(_sample());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: child!),
          home: Scaffold(
            body: ListView(children: const [ImportDraftBanner()]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    ParsedSchedule? saved() =>
        ImportDraftStore(ScopedPrefs(prefs, uid)).state?.schedule;

    testWidgets('banner resumes the draft; edits autosave; backgrounding flushes',
        (tester) async {
      await pump(tester);
      expect(find.text('Finish your timetable import'), findsOneWidget);
      await tester.tap(find.text('Review & save'));
      await tester.pumpAndSettle();
      expect(find.text('Review & confirm'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'DBMS'), 'DBMS Lab');
      await tester.pump(const Duration(milliseconds: 700));
      expect(saved()?.subjects.first.name, 'DBMS Lab');

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Dr. Rao'), 'Dr. Iyer');
      // App sent to background before the debounce fires: saved right away.
      // (Real lifecycle order: inactive → hidden → paused, and back.)
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(saved()?.subjects.first.professor, 'Dr. Iyer');
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('back asks: keep keeps the draft, discard deletes it',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Review & save'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.text('Keep for later'));
      await tester.pumpAndSettle();
      expect(find.text('Review & confirm'), findsNothing);
      expect(saved(), isNotNull);
      expect(find.text('Finish your timetable import'), findsOneWidget);

      await tester.tap(find.text('Review & save'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(saved(), isNull);
      expect(find.text('Finish your timetable import'), findsNothing);
    });

    testWidgets('saving to ClassTrack writes Firestore and clears the draft',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Review & save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to ClassTrack'));
      await tester.pumpAndSettle();

      final subjects =
          await db.collection('users').doc(uid).collection('subjects').get();
      // OS was unticked in the draft, so only DBMS is added.
      expect(subjects.docs.map((d) => d['name']), ['DBMS']);
      expect(saved(), isNull);
      expect(find.text('Review & confirm'), findsNothing);
      expect(find.text('Finish your timetable import'), findsNothing);
    });
  });
}
