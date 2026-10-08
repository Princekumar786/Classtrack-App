// Play Store screenshot capture — renders REAL ClassTrack screens (the actual
// production widgets, theme and fonts) against a seeded demo student account
// in an in-memory Firestore, and writes phone-resolution PNGs to
// play-store-assets/store-2026/raw/.
//
// Run:  flutter test tool/store_capture/capture_test.dart --update-goldens
//
// Not part of the normal test suite (lives under tool/).
import 'dart:io';

import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/providers/gemini_provider.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/auth/data/auth_repository.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:classtrack/features/learning_planner/presentation/providers/learning_planner_providers.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:classtrack/services/gemini_service.dart';
import 'package:classtrack/services/home_widget_service.dart';
import 'package:classtrack/services/push_messaging_service.dart';
import 'package:classtrack/services/reminder_scheduler.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seed.dart';

const uid = 'demo-student';

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
  @override
  Future<void> screen(String name) async {}
}

/// Deterministic AI replies so the assistant screen shows a real exchange.
class FakeGemini extends GeminiService {
  FakeGemini() : super(_NoFunctions());
  @override
  Future<String> chat(List<Map<String, dynamic>> history, {String? context}) async =>
      demoAssistantReply;
}

class _NoFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> loadFonts() async {
  Future<void> font(String family, List<String> paths) async {
    final l = FontLoader(family);
    for (final p in paths) {
      l.addFont(Future.value(ByteData.view(File(p).readAsBytesSync().buffer)));
    }
    await l.load();
  }

  await font('Poppins', [
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
    'assets/fonts/Poppins-Bold.ttf',
  ]);
  await font('Inter', [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  await font('MaterialIcons',
      ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

/// Precache every image currently in the tree (asset decoding is async).
Future<void> precacheAll(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      try {
        await precacheImage((e.widget as Image).image, e);
      } catch (_) {}
    }
  });
  await tester.pump();
}

Future<ProviderContainer> bootApp(WidgetTester tester, Widget home,
    {Size physicalSize = const Size(1080, 2340), double textScale = 1.0, bool isPro = true}) async {
  // Default 1080×2340 px phone (360×780 dp at 3x) — a modern 19.5:9 Android screen.
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
  addTearDown(tester.view.reset);

  final db = FakeFirebaseFirestore();
  await tester.runAsync(() => seedDemoAccount(db, uid));

  // ignore: invalid_use_of_visible_for_testing_member — capture runs under flutter_test.
  SharedPreferences.setMockInitialValues({
    'onboarding_done': true,
    'home_tour_done': true,
    'tips_prompt_shown': true,
    'first_launch_at': DateTime.now().millisecondsSinceEpoch,
  });
  final prefs = await tester.runAsync(SharedPreferences.getInstance);

  final container = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    currentUidProvider.overrideWithValue(uid),
    sharedPrefsProvider.overrideWithValue(prefs!),
    analyticsProvider.overrideWithValue(_NoopAnalytics()),
    isProProvider.overrideWith((ref) => isPro),
    geminiServiceProvider.overrideWithValue(FakeGemini()),
    // Background side-effect services (notifications, RevenueCat identity,
    // push topics, home-screen widget) — irrelevant to what's on screen.
    reminderSyncProvider.overrideWith((ref) {}),
    plannerReminderSyncProvider.overrideWith((ref) {}),
    subscriptionAuthLinkProvider.overrideWith((ref) {}),
    pushCountryTopicSyncProvider.overrideWith((ref) {}),
    homeWidgetSyncProvider.overrideWith((ref) {}),
    // Profile reads go through AuthRepository → back it with the fake DB.
    authRepositoryProvider.overrideWithValue(
        AuthRepository(auth: _NoAuth(), db: db, googleSignIn: GoogleSignIn())),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Entrance animations off so every frame is final; real layout otherwise.
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    ),
  ));
  await settle(tester);
  return container;
}

/// Lets Firestore streams deliver and layout finish (looping animations mean
/// pumpAndSettle may never return, so pump a fixed budget instead).
Future<void> settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await precacheAll(tester);
  await tester.pump(const Duration(seconds: 2));
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, frames: 6);
  await expectLater(find.byType(MaterialApp),
      matchesGoldenFile('../../play-store-assets/store-2026/raw/$name.png'));
}
