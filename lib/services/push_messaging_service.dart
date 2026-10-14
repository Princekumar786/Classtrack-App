import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import 'notification_service.dart';

/// Android channel used to *display* Firebase Cloud Messaging pushes. It must
/// match the `default_notification_channel_id` metadata in AndroidManifest.xml
/// so background/terminated notifications from the Firebase console render with
/// the right importance instead of falling into a silent "Miscellaneous" bucket.
const String kPushChannelId = 'classtrack_push';
const String kPushChannelName = 'Announcements';
const String kPushChannelDesc =
    'Updates and announcements sent by the ClassTrack team.';

/// Topic every device subscribes to, so the Firebase console can broadcast to
/// the whole audience with a single "topic" send in addition to the built-in
/// "all users" segment.
const String kBroadcastTopic = 'all';

/// Background/terminated message handler.
///
/// MUST be a top-level (or static) function annotated with
/// `@pragma('vm:entry-point')` — Flutter spins up a *separate* isolate to run
/// it, so it can't capture any app state. For "notification" messages sent from
/// the Firebase console the system tray notification is drawn automatically by
/// the FCM SDK; this handler only needs to exist (and initialise Firebase for
/// the background isolate) so data-only messages don't crash.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The background isolate has no access to the app's already-initialised
  // Firebase instance, so initialise it here. Guard against the rare case where
  // it's already been set up for this isolate.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {/* already initialised for this isolate */}
  // No further work required: notification messages are shown by the OS.
  if (kDebugMode) debugPrint('[FCM] background message: ${message.messageId}');
}

/// Wires Firebase Cloud Messaging into the app so pushes sent from the Firebase
/// console (Messaging → "Create your first campaign"/"New notification") are
/// delivered and displayed on this device.
class PushMessagingService {
  PushMessagingService({FlutterLocalNotificationsPlugin? localPlugin})
      : _local = localPlugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _local;
  // Lazy so constructing the service (e.g. in tests) never touches Firebase.
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  bool _ready = false;

  /// The country topic this device is currently subscribed to (e.g.
  /// `country_india`), or null. Tracked so a profile country change can move
  /// the subscription without leaving stale ones behind.
  String? _countryTopic;

  /// FCM topic for a profile country, matching the server's slug rules
  /// (functions/notifications.js). Null for empty/"Global".
  static String? countryTopicFor(String? country) {
    if (country == null) return null;
    final c = country.trim().toLowerCase();
    if (c.isEmpty || c == 'global') return null;
    final slug = c
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? null : 'country_$slug';
  }

  /// Subscribes this device to its profile country's topic (and unsubscribes
  /// from a previous one) so CMS country-targeted notifications are delivered.
  /// Best-effort and bounded — never blocks or throws.
  Future<void> setCountryTopic(String? country) async {
    if (kIsWeb) return;
    final topic = countryTopicFor(country);
    if (topic == _countryTopic) return;
    final previous = _countryTopic;
    _countryTopic = topic;
    if (previous != null) {
      try {
        await _fcm
            .unsubscribeFromTopic(previous)
            .timeout(const Duration(seconds: 5));
      } catch (_) {/* best-effort */}
    }
    if (topic != null) {
      try {
        await _fcm.subscribeToTopic(topic).timeout(const Duration(seconds: 5));
      } catch (_) {/* best-effort */}
    }
  }

  /// Initialise messaging: request permission, create the Android display
  /// channel, wire foreground/tap handlers and subscribe to the broadcast
  /// topic. Safe to call multiple times.
  Future<void> init() async {
    if (_ready) return;

    // 1. Ask the user for notification permission (Android 13+ / iOS).
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // 2. iOS: make sure a notification shows while the app is foregrounded.
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Android: create the channel the manifest points at, so background
    //    pushes display at high importance (heads-up) rather than silently.
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        kPushChannelId,
        kPushChannelName,
        description: kPushChannelDesc,
        importance: Importance.high,
      ),
    );

    // 4. Initialise the local-notifications plugin so we can render pushes that
    //    arrive while the app is in the foreground (FCM doesn't auto-display
    //    those). Reuse the app icon; taps flow through onDidReceive... below.
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Same handler as NotificationService (they share one plugin, and the
      // last initialize() owns the callback), so Present/Absent action taps
      // are marked no matter which service initialised last.
      onDidReceiveNotificationResponse: NotificationService.handleResponse,
    );

    // 5. Foreground messages → draw a local notification ourselves.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // 6. Tap on a notification that opened/resumed the app → deep-link.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

    // 7. Cold start from a tapped push while the app was terminated.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleOpened(initial);

    // 8. Subscribe to the broadcast topic (web/desktop don't support topics).
    //    Bounded by a timeout: subscribeToTopic can stall indefinitely offline
    //    or without Google Play Services, and this must never wedge init().
    if (!kIsWeb) {
      try {
        await _fcm
            .subscribeToTopic(kBroadcastTopic)
            .timeout(const Duration(seconds: 5));
      } catch (_) {/* topic subscription is best-effort */}
    }

    // 9. Debug builds only: log the device token for the console's "Send test
    //    message". Never in release — debugPrint is NOT stripped there, so the
    //    token (which can target this phone) would land in the system log.
    if (kDebugMode) {
      try {
        final token =
            await _fcm.getToken().timeout(const Duration(seconds: 5));
        debugPrint('[FCM] device token: $token');
      } catch (_) {/* token may be unavailable (offline / no APNs / timeout) */}
    }

    _ready = true;
  }

  /// Render a foreground push using the same channel as background pushes.
  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return; // data-only messages are handled elsewhere.
    await _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kPushChannelId,
          kPushChannelName,
          channelDescription: kPushChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notify',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: _payloadFor(message),
    );
  }

  /// Surface the tapped push's payload so the UI can deep-link. Falls back to
  /// the daily-agenda screen used by local reminders when no explicit route is
  /// provided in the message's data block.
  void _handleOpened(RemoteMessage message) {
    NotificationService.selectedPayload.value = _payloadFor(message);
  }

  /// Custom `data` key `payload` (settable in the console under
  /// "Additional options → Custom data") drives deep-linking; otherwise reuse
  /// the daily-agenda payload so a tap still lands somewhere sensible.
  String _payloadFor(RemoteMessage message) {
    final custom = message.data['payload'];
    if (custom is String && custom.isNotEmpty) return custom;
    return NotificationService.dailyAgendaPayload;
  }
}

final pushMessagingServiceProvider = Provider<PushMessagingService>(
  (ref) => PushMessagingService(),
);

/// Keeps the device subscribed to its country's FCM topic so CMS
/// country-targeted notifications are delivered. Uses the SAME country as
/// opportunities ([effectiveCountryProvider]: profile choice, else detected).
/// Watch it where the app is alive (HomeShell) so it re-runs on change.
final pushCountryTopicSyncProvider = Provider<void>((ref) {
  final country = ref.watch(effectiveCountryProvider);
  // Fire-and-forget; the service call is bounded and never throws.
  ref.read(pushMessagingServiceProvider).setCountryTopic(country);
});
