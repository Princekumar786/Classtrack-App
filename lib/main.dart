import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/providers/app_settings_provider.dart';
import 'features/subscription/data/subscription_service.dart';
import 'features/subscription/presentation/providers/subscription_providers.dart';
import 'features/tips/presentation/providers/tips_providers.dart';
import 'firebase_options.dart';
import 'services/error_reporter.dart';
import 'services/notification_service.dart';
import 'services/push_messaging_service.dart';

Future<void> main() async {
  // Run the whole app inside a guarded zone so ANY uncaught asynchronous error
  // is captured and forwarded to Crashlytics as a fatal report — otherwise
  // async errors outside the Flutter framework would be invisible in prod.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ── Never show a blank/grey screen on a widget build error ───────────
    // In release builds, an exception thrown inside a widget's build() paints
    // an empty grey box with no message. Replace that with a self-contained,
    // friendly fallback panel so the user always sees something intelligible
    // (and can navigate back) instead of a dead blank screen. Kept trivial and
    // dependency-free so the fallback itself can never throw.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF0B1020),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white70, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Something went wrong on this screen.\nPlease go back and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    // ── Edge-to-edge display ─────────────────────────────────────────────
    // Android 15+ (targetSdk 35+) enforces edge-to-edge: the app draws behind
    // the status and navigation bars. Opt in explicitly so the layout extends
    // under the system bars on every device (fixes the Play Console
    // "Edge-to-edge may not display for all users" recommendation), and make
    // the system bars transparent so Flutter's own UI shows through instead of
    // a legacy scrim. Purely a display setting; safe and reversible.
    if (!kIsWeb) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
    }

    // Firebase core must be ready before the app builds any auth/Firestore
    // providers. This is a LOCAL initialisation that completes offline.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // ── Crash reporting ──────────────────────────────────────────────────
    // Route Flutter framework errors and low-level platform errors into
    // Crashlytics. Collection is disabled in debug so local runs and tests
    // don't pollute the dashboard. These handlers are synchronous and offline
    // safe (reports are cached on-device and uploaded on the next launch).
    //
    // Crashlytics has NO web implementation, so we only wire it on mobile —
    // otherwise the plugin call would throw/hang before runApp() and leave the
    // web build stuck on the splash screen.
    if (!kIsWeb) {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      // Searchable on every Crashlytics issue.
      unawaited(crashlytics.setCustomKey('app_version', AppConstants.appVersion));
    }

    // Every error goes to BOTH Crashlytics and PostHog via ErrorReporter, tagged
    // `error_kind` = defect | transient. Transient failures (offline, a
    // briefly-unavailable Firestore, timeouts, a plugin not wired on this
    // surface) are reported as NON-fatal so they stay visible for diagnosis
    // without counting as crashes or tanking the crash-free rate.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ErrorReporter.reportFlutterError(details);
    };
    // Errors that escape the Flutter framework (e.g. in a platform callback).
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorReporter.report(error, stack,
          reason: 'platform_dispatcher', fatal: true);
      return true;
    };

    // Product analytics + error tracking (PostHog, EU cloud). Runs on all
    // platforms (web bridges to the posthog-js snippet in web/index.html).
    await _initPostHog();

    await _bootstrap();
  }, (error, stack) {
    // Any async error not caught elsewhere lands here.
    if (kIsWeb) {
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
    }
    ErrorReporter.report(error, stack, reason: 'uncaught_async', fatal: true);
  });
}

/// Initialises PostHog (EU cloud) for behaviour analytics, screen views, app
/// lifecycle events and error tracking. Manual init — the native manifests set
/// `com.posthog.posthog.AUTO_INIT=false` so this Dart call is authoritative and
/// lets us control config. Opted OUT in debug (mirroring the Crashlytics
/// collection gate) so local/dev runs never pollute the production project.
/// Never throws — analytics must not block or break app launch.
Future<void> _initPostHog() async {
  try {
    final config = PostHogConfig(AppConstants.posthogApiKey)
      ..host = AppConstants.posthogHost
      ..debug = kDebugMode
      // No data is sent in debug builds; flip this to always-on if you want to
      // watch events land while developing.
      ..optOut = kDebugMode
      // Flush each event as soon as it's captured (and, as a safety net, every
      // 10s) instead of the SDK default of batching 20 events / 30s. The
      // default batching meant a user who tapped a few things and then
      // swipe-killed the app lost that un-flushed tail, so analytics appeared
      // to "record some events, skip others". flushAt:1 trades a little extra
      // network for near-real-time, no-loss capture at this app's volume.
      ..flushAt = 1
      ..flushInterval = const Duration(seconds: 5)
      // App Opened / Backgrounded / Installed / Updated, captured natively.
      ..captureApplicationLifecycleEvents = true
      ..personProfiles = PostHogPersonProfiles.identifiedOnly;
    await Posthog().setup(config);
    // Push anything still queued (e.g. captured while offline) the moment
    // the app is backgrounded, so the PostHog live view never waits on the
    // next interval and a swipe-kill can't drop the tail of a session.
    _posthogLifecycle ??= AppLifecycleListener(
      onHide: _flushPosthog,
      onPause: _flushPosthog,
      onDetach: _flushPosthog,
      onResume: _flushPosthog,
    );
  } catch (_) {
    // Never let analytics setup break app launch.
  }
}

AppLifecycleListener? _posthogLifecycle;

void _flushPosthog() {
  try {
    unawaited(Posthog().flush());
  } catch (_) {}
}

/// Builds services and starts the app. Split out of [main] so it runs inside
/// the guarded zone above.
Future<void> _bootstrap() async {
  // Register the FCM background/terminated handler BEFORE runApp so pushes that
  // arrive while the app isn't foregrounded are handled. Synchronous, no
  // network — must reference a top-level function.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Local, fast — needed to build the settings providers.
  final prefs = await SharedPreferences.getInstance();

  // Anchor the Tips & Tricks 7-day gate on the very first launch (device-wide).
  await recordFirstLaunchIfNeeded(prefs);

  // Build the service singletons synchronously (constructors do no I/O). Their
  // async initialisers touch the network — FCM getToken()/subscribeToTopic()
  // and RevenueCat — which can BLOCK when the app is launched offline or on a
  // device with degraded Google Play Services. Awaiting them here previously
  // meant runApp() was never reached and the app "wouldn't open without
  // internet". We create them now and initialise them AFTER the first frame.
  final notifications = NotificationService();
  final pushMessaging = PushMessagingService();
  final subscriptions = SubscriptionService();

  runApp(
    ProviderScope(
      // Reports every provider/stream failure (e.g. a Firestore listener that
      // was denied or dropped) instead of it silently showing an empty screen.
      observers: const [ErrorReportingProviderObserver()],
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
        pushMessagingServiceProvider.overrideWithValue(pushMessaging),
        subscriptionServiceProvider.overrideWithValue(subscriptions),
      ],
      child: const ClassTrackApp(),
    ),
  );

  // Fire-and-forget the non-critical initialisers so a slow or absent
  // connection can never delay the UI. Each is internally guarded (its own
  // try/catch) and idempotent, so running them in the background is safe:
  //  • notifications.init()  — local, but kept off the critical path anyway;
  //    scheduling paths call init() lazily so ordering is unaffected.
  //  • pushMessaging.init()  — network (token/topic); safe to complete late.
  //  • subscriptions.configure() — RevenueCat; the paywall/Pro providers all
  //    tolerate the "not configured yet" state until this finishes.
  unawaited(notifications.init());
  unawaited(pushMessaging.init());
  unawaited(subscriptions.configure());

  // Fonts are now BUNDLED (see pubspec.yaml `fonts:`), so there is no runtime
  // font fetch to warm up — the first frame already paints in Poppins/Inter.
}

/// Riverpod observer that forwards provider failures (stream errors such as a
/// denied or dropped Firestore listener, a FutureProvider that threw) to
/// [ErrorReporter] as non-fatal, tagged with the provider's name.
class ErrorReportingProviderObserver extends ProviderObserver {
  const ErrorReportingProviderObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    ErrorReporter.report(
      error,
      stackTrace,
      reason: 'provider:${provider.name ?? provider.runtimeType}',
    );
  }
}
