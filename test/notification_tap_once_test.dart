import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/services/notification_service.dart';

/// "Tapped the attendance notification, then Back took 5–6 presses":
/// the same tap was delivered several times, each opening another page.
void main() {
  tearDown(() => NotificationService.selectedPayload.value = null);

  group('launch tap is handled once', () {
    final now = DateTime(2026, 10, 14, 10);
    test('first time is new', () {
      expect(
          NotificationService.isNewLaunch(
              signature: 'a', lastSignature: null, lastAt: null, now: now),
          isTrue);
    });
    test('same tap re-reported later in the day is ignored', () {
      expect(
          NotificationService.isNewLaunch(
              signature: 'a',
              lastSignature: 'a',
              lastAt: now.subtract(const Duration(minutes: 40)),
              now: now),
          isFalse);
    });
    test('a different notification is new', () {
      expect(
          NotificationService.isNewLaunch(
              signature: 'b', lastSignature: 'a', lastAt: now, now: now),
          isTrue);
    });
    test('the same weekly notification next week is new', () {
      expect(
          NotificationService.isNewLaunch(
              signature: 'a',
              lastSignature: 'a',
              lastAt: now.subtract(const Duration(days: 7)),
              now: now),
          isTrue);
    });
  });

  group('one shared tap handler', () {
    NotificationResponse resp(String? action) => NotificationResponse(
          notificationResponseType: action == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction,
          actionId: action,
          payload: 'attendance_checkin|sub1|09:00',
        );

    test('Present button becomes a mark payload', () {
      NotificationService.handleResponse(resp('att_present'));
      expect(NotificationService.selectedPayload.value,
          'attendance_mark|present|sub1|09:00');
    });

    test('plain tap opens attendance (no mark)', () {
      NotificationService.handleResponse(resp(null));
      expect(NotificationService.selectedPayload.value,
          'attendance_checkin|sub1|09:00');
    });
  });
}
