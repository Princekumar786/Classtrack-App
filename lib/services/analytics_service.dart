import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// App-wide access to [AnalyticsService].
final analyticsProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(),
);

/// Thin, crash-proof wrapper that fans every event out to BOTH Firebase
/// Analytics and PostHog (EU cloud), so feature code logs usage once without
/// touching either SDK directly — and so a logging failure can NEVER break the
/// app (every call is individually guarded).
///
/// We use a small set of high-signal events to answer "which features do users
/// actually use": tab switches, feature-screen opens, quick-add usage, AI
/// messages and schedule imports. View them in Firebase Console → Analytics or
/// in PostHog → Activity / Product analytics.
class AnalyticsService {
  FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  /// Logs a custom event. Parameter values must be String or num (no bools) —
  /// a Firebase constraint we keep so the same map is safe for both sinks.
  Future<void> log(String name, [Map<String, Object>? params]) async {
    try {
      await _fa.logEvent(name: name, parameters: params);
    } catch (_) {
      // Analytics must never surface as an app error.
    }
    try {
      await Posthog().capture(eventName: name, properties: params);
    } catch (_) {
      // PostHog is opted-out in debug / not set up on some surfaces — ignore.
    }
  }

  /// Logs a screen/feature view to both sinks.
  Future<void> screen(String name) async {
    try {
      await _fa.logScreenView(screenName: name);
    } catch (_) {}
    try {
      await Posthog().screen(screenName: name);
    } catch (_) {}
  }

  // --- Convenience helpers for the events we care about --------------------

  Future<void> tab(String name) => log('tab_select', {'tab': name});

  Future<void> openFeature(String name) =>
      log('open_feature', {'feature': name});

  Future<void> quickAdd(String type) => log('quick_add', {'type': type});

  // --- Learning Planner ----------------------------------------------------
  // High-signal planner events for PostHog/Firebase product analytics. Screen
  // views are captured automatically via named routes (RouteSettings) picked
  // up by the Firebase + PostHog navigator observers.

  /// A plan creation flow was started. [mode] is 'ai' or 'manual'.
  Future<void> plannerCreateStarted(String mode) =>
      log('planner_create_started', {'mode': mode});

  /// A plan was created. [source] is 'ai' | 'library' | 'manual'.
  Future<void> plannerPlanCreated({
    required String source,
    required String subject,
    required String level,
    required String goal,
    required String program,
    required String region,
    required int topics,
    required int estMinutes,
    required bool hasSyllabus,
  }) =>
      log('planner_plan_created', {
        'source': source,
        'subject': subject,
        'level': level,
        'goal': goal,
        'program': program,
        'region': region,
        'topics': topics,
        'est_minutes': estMinutes,
        'has_syllabus': hasSyllabus ? 1 : 0,
      });

  Future<void> plannerTopicCompleted() => log('planner_topic_completed');

  Future<void> plannerDayCompleted() => log('planner_day_completed');

  Future<void> plannerFocusLogged(int minutes) =>
      log('planner_focus_logged', {'minutes': minutes});

  Future<void> plannerRecalibrated(double pace) =>
      log('planner_recalibrated', {'pace_pct': (pace * 100).round()});

  Future<void> plannerAdjusted(String type) =>
      log('planner_adjusted', {'type': type});

  Future<void> plannerDeleted() => log('planner_deleted');

  Future<void> aiMessage({bool hasImage = false}) =>
      log('ai_message', {'has_image': hasImage ? 1 : 0});

  Future<void> scheduleImport(String source) =>
      log('schedule_import', {'source': source});

  // --- Import funnel -------------------------------------------------------
  // A step-by-step funnel so we can see exactly where users drop off in the AI
  // timetable import: opened → method chosen → parse started → succeeded/failed
  // (with a reason) → reviewed & saved. View in Firebase → Analytics → Funnels.

  /// The AI import screen was opened. [source] is where it was launched from
  /// (e.g. 'attendance_onboarding' or 'schedule').
  Future<void> importOpened(String source) =>
      log('import_opened', {'source': source});

  /// A specific upload method was chosen: 'camera' | 'gallery' | 'pdf' | 'text'.
  Future<void> importMethodSelected(String method) =>
      log('import_method_selected', {'method': method});

  /// The parse request was sent to the backend.
  Future<void> importParseStarted(String method) =>
      log('import_parse_started', {'method': method});

  /// The parse returned usable results.
  Future<void> importParseSucceeded(
    String method, {
    required int subjects,
    required String confidence,
  }) => log('import_parse_succeeded', {
    'method': method,
    'subjects': subjects,
    'confidence': confidence,
  });

  /// The parse failed or returned nothing. [reason] is a coarse category, e.g.
  /// 'empty' | 'not_a_timetable' | 'limit_reached' | 'network' | 'unknown'.
  Future<void> importParseFailed(String method, String reason) =>
      log('import_parse_failed', {'method': method, 'reason': reason});

  /// The reviewed schedule was committed to the app.
  Future<void> importReviewSaved({
    required int subjects,
    required int sessions,
    required int tasks,
  }) => log('import_review_saved', {
    'subjects': subjects,
    'sessions': sessions,
    'tasks': tasks,
  });
}
