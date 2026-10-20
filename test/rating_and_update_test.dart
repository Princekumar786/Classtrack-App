import 'package:classtrack/core/constants/app_constants.dart';
import 'package:classtrack/services/app_update_service.dart';
import 'package:classtrack/services/rating_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('RatingPolicy', () {
    final now = DateTime(2026, 10, 17);
    bool ask({
      int installedDaysAgo = 10,
      int activeDays = 5,
      int happy = 3,
      int? lastAskedDaysAgo,
      int timesAsked = 0,
    }) =>
        RatingPolicy.shouldAsk(
          now: now,
          firstLaunch: now.subtract(Duration(days: installedDaysAgo)),
          activeDays: activeDays,
          happyMoments: happy,
          lastAsked: lastAskedDaysAgo == null
              ? null
              : now.subtract(Duration(days: lastAskedDaysAgo)),
          timesAsked: timesAsked,
        );

    test('asks an engaged student after a win', () => expect(ask(), isTrue));
    test('not in the first days', () => expect(ask(installedDaysAgo: 2), isFalse));
    test('not before enough active days', () => expect(ask(activeDays: 2), isFalse));
    test('not on the very first win', () => expect(ask(happy: 1), isFalse));
    test('respects the cooldown', () {
      expect(ask(lastAskedDaysAgo: 30, timesAsked: 1), isFalse);
      expect(ask(lastAskedDaysAgo: 121, timesAsked: 1), isTrue);
    });
    test('caps total asks', () => expect(ask(lastAskedDaysAgo: 400, timesAsked: 3), isFalse));
  });

  group('RatingPromptService', () {
    late SharedPreferences prefs;
    final now = DateTime(2026, 10, 17, 12);

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefsFirstLaunchAt:
            now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      });
      prefs = await SharedPreferences.getInstance();
    });

    RatingPromptService svc(void Function() onRequest) => RatingPromptService(
          prefs,
          supported: true,
          clock: () => now,
          delay: Duration.zero,
          requestReview: () async {
            onRequest();
            return true;
          },
        );

    test('active days count once per calendar day', () async {
      await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, 1, 9));
      await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, 1, 22));
      await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, 2, 8));
      expect(prefs.getInt(AppConstants.prefsRatingActiveDays), 2);
    });

    test('asks on the second win, then waits for the cooldown', () async {
      for (var d = 1; d <= 3; d++) {
        await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, d));
      }
      var requests = 0;
      final s = svc(() => requests++);
      expect(await s.onHappyMoment(HappyMoment.focusSessionDone), isFalse);
      expect(await s.onHappyMoment(HappyMoment.timetableImported), isTrue);
      expect(requests, 1);
      // Further wins in the cooldown don't ask again.
      expect(await s.onHappyMoment(HappyMoment.flashcardsAced), isFalse);
      expect(requests, 1);
      expect(prefs.getInt(AppConstants.prefsRatingTimesAsked), 1);
    });

    test('never asks on unsupported platforms (web)', () async {
      for (var d = 1; d <= 3; d++) {
        await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, d));
      }
      var requests = 0;
      final s = RatingPromptService(prefs,
          supported: false, clock: () => now, delay: Duration.zero,
          requestReview: () async => (requests++ >= 0));
      await s.onHappyMoment(HappyMoment.focusSessionDone);
      await s.onHappyMoment(HappyMoment.focusSessionDone);
      expect(requests, 0);
    });

    test('a failing store call never throws', () async {
      for (var d = 1; d <= 3; d++) {
        await RatingPromptService.recordActiveDay(prefs, DateTime(2026, 10, d));
      }
      final s = RatingPromptService(prefs,
          supported: true, clock: () => now, delay: Duration.zero,
          requestReview: () async => throw Exception('play down'));
      await s.onHappyMoment(HappyMoment.focusSessionDone);
      expect(await s.onHappyMoment(HappyMoment.focusSessionDone), isFalse);
    });
  });

  group('UpdatePolicy', () {
    UpdateMode decide({
      bool available = true,
      int priority = 0,
      int? stale,
      bool immediate = true,
      bool flexible = true,
    }) =>
        UpdatePolicy.decide(
          available: available,
          priority: priority,
          stalenessDays: stale,
          immediateAllowed: immediate,
          flexibleAllowed: flexible,
        );

    test('nothing to do without an update', () => expect(decide(available: false), UpdateMode.none));
    test('normal update downloads in the background', () => expect(decide(), UpdateMode.flexible));
    test('high priority forces an immediate update', () => expect(decide(priority: 4), UpdateMode.immediate));
    test('ignored for 2 weeks becomes immediate', () => expect(decide(stale: 14), UpdateMode.immediate));
    test('falls back to whichever flow Play allows', () {
      expect(decide(priority: 5, immediate: false), UpdateMode.flexible);
      expect(decide(flexible: false), UpdateMode.immediate);
      expect(decide(immediate: false, flexible: false), UpdateMode.none);
    });
    test('checks at most every 12 hours', () {
      final now = DateTime(2026, 10, 17, 12);
      expect(UpdatePolicy.dueForCheck(now, null), isTrue);
      expect(UpdatePolicy.dueForCheck(now, now.subtract(const Duration(hours: 3))), isFalse);
      expect(UpdatePolicy.dueForCheck(now, now.subtract(const Duration(hours: 13))), isTrue);
    });
  });
}
