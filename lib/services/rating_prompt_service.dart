import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/app_settings_provider.dart';
import 'analytics_service.dart';

/// "Happy moments" that may trigger the store rating sheet. Kept as an enum
/// so analytics names stay consistent.
enum HappyMoment { timetableImported, focusSessionDone, flashcardsAced, semesterShared }

/// Pure rules for WHEN to ask for a rating (unit-tested).
///
/// We only ask students who clearly get value from the app, right after a win,
/// and rarely. Google Play / App Store also rate-limit the sheet themselves, so
/// a "request" may show nothing — that's expected.
class RatingPolicy {
  RatingPolicy._();

  /// Don't ask in the first few days — let the app prove itself.
  static const int minDaysSinceInstall = 3;

  /// Opened on at least this many different days.
  static const int minActiveDays = 3;

  /// At least this many wins (this one included).
  static const int minHappyMoments = 2;

  /// Wait this long between asks.
  static const Duration cooldown = Duration(days: 120);

  /// Never ask more than this many times per install.
  static const int maxAsks = 3;

  static bool shouldAsk({
    required DateTime now,
    required DateTime? firstLaunch,
    required int activeDays,
    required int happyMoments,
    required DateTime? lastAsked,
    required int timesAsked,
  }) {
    if (firstLaunch == null) return false;
    if (now.difference(firstLaunch).inDays < minDaysSinceInstall) return false;
    if (activeDays < minActiveDays) return false;
    if (happyMoments < minHappyMoments) return false;
    if (timesAsked >= maxAsks) return false;
    if (lastAsked != null && now.difference(lastAsked) < cooldown) return false;
    return true;
  }
}

/// Shows the native in-app rating sheet at good moments.
///
/// No "Do you like the app?" question first: Google Play's policy forbids
/// gating the review flow on a pre-question, so we call the official API
/// directly and let the store decide whether to show it.
class RatingPromptService {
  RatingPromptService(
    this._prefs, {
    AnalyticsService? analytics,
    Future<bool> Function()? requestReview,
    bool? supported,
    DateTime Function()? clock,
    this.delay = const Duration(milliseconds: 1200),
  })  : _analytics = analytics,
        _requestReview = requestReview ?? _nativeRequest,
        _supported = supported ?? _platformSupported,
        _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final AnalyticsService? _analytics;
  final Future<bool> Function() _requestReview;
  final bool _supported;
  final DateTime Function() _clock;

  /// Pause before the sheet so the student first sees their win (snackbar,
  /// summary, confetti) instead of the sheet covering it.
  final Duration delay;

  bool _inFlight = false;

  static bool get _platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> _nativeRequest() async {
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return false;
    await review.requestReview();
    return true;
  }

  /// Counts today as an active day (once per calendar day). Call on launch.
  static Future<void> recordActiveDay(SharedPreferences prefs, [DateTime? now]) async {
    final d = now ?? DateTime.now();
    final today = '${d.year}-${d.month}-${d.day}';
    if (prefs.getString(AppConstants.prefsRatingLastActiveDay) == today) return;
    await prefs.setString(AppConstants.prefsRatingLastActiveDay, today);
    await prefs.setInt(AppConstants.prefsRatingActiveDays,
        (prefs.getInt(AppConstants.prefsRatingActiveDays) ?? 0) + 1);
  }

  /// Records a win and, if the student qualifies, asks for a rating.
  /// Returns true when the store sheet was requested. Never throws.
  Future<bool> onHappyMoment(HappyMoment moment) async {
    try {
      final happy = (_prefs.getInt(AppConstants.prefsRatingHappyMoments) ?? 0) + 1;
      await _prefs.setInt(AppConstants.prefsRatingHappyMoments, happy);
      if (!_supported || _inFlight) return false;

      final now = _clock();
      final first = _prefs.getInt(AppConstants.prefsFirstLaunchAt);
      final last = _prefs.getInt(AppConstants.prefsRatingLastAskedAt);
      final asked = _prefs.getInt(AppConstants.prefsRatingTimesAsked) ?? 0;
      final ok = RatingPolicy.shouldAsk(
        now: now,
        firstLaunch: first == null ? null : DateTime.fromMillisecondsSinceEpoch(first),
        activeDays: _prefs.getInt(AppConstants.prefsRatingActiveDays) ?? 0,
        happyMoments: happy,
        lastAsked: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
        timesAsked: asked,
      );
      if (!ok) return false;

      _inFlight = true;
      // Record first, so a crash or kill mid-flow can't cause a repeat ask.
      await _prefs.setInt(AppConstants.prefsRatingLastAskedAt, now.millisecondsSinceEpoch);
      await _prefs.setInt(AppConstants.prefsRatingTimesAsked, asked + 1);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final shown = await _requestReview();
      unawaited(_analytics?.log('rating_prompt_requested', {
        'moment': moment.name,
        'available': shown ? 1 : 0,
        'ask_number': asked + 1,
      }));
      return shown;
    } catch (_) {
      return false; // A rating prompt must never break the app.
    } finally {
      _inFlight = false;
    }
  }
}

final ratingPromptProvider = Provider<RatingPromptService>((ref) {
  return RatingPromptService(
    ref.watch(sharedPrefsProvider),
    analytics: ref.read(analyticsProvider),
  );
});
