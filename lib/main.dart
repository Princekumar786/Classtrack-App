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

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        // Transient/environmental failures (a briefly-unavailable Firestore
        // backend, a platform channel that isn't wired on this surface, a
        // timeout) are not code defects and must NOT be reported as fatal
        // crashes — otherwise flaky networks tank the crash-free rate and
        // trigger "repetitive crash" alerts. Log them as non-fatal so they
        // stay visible for diagnosis without counting as crashes.
        if (_isNonFatalInfraError(details.exception)) {
          crashlytics.recordError(
            details.exception,
            details.stack,
            reason: details.context?.toDescription(),
            fatal: false,
          );
        } else {
          crashlytics.recordFlutterFatalError(details);
        }
        // Mirror real defects into PostHog error tracking too.
        _capturePosthogException(details.exception, details.stack);
      };
      // Errors that escape the Flutter framework (e.g. in a platform callback).
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(
          error,
          stack,
          fatal: !_isNonFatalInfraError(error),
        );
        _capturePosthogException(error, stack);
        return true;
      };
    }

    // Product analytics + error tracking (PostHog, EU cloud). Runs on all
    // platforms (web bridges to the posthog-js snippet in web/index.html).
    await _initPostHog();

    await _bootstrap();
  }, (error, stack) {
    // Any async error not caught elsewhere lands here.
    if (!kIsWeb) {
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: !_isNonFatalInfraError(error));
    } else {
      // ignore: avoid_print
      print('Uncaught zone error: $error\n$stack');
    }
    _capturePosthogException(error, stack);
  });
}

/// Mirrors a fatal error into PostHog's error tracking, alongside Crashlytics.
///
/// Guarded and fire-and-forget so it can NEVER block or throw inside a crash
/// handler. Environmental/transient infra errors (offline sockets, unavailable
/// Firestore, timeouts) are skipped — the same ones Crashlytics reports as
/// non-fatal — so PostHog's error dashboard only shows genuine defects.
void _capturePosthogException(Object error, StackTrace? stack) {
  if (_isNonFatalInfraError(error)) return;
  try {
    unawaited(Posthog().captureException(error: error, stackTrace: stack));
  } catch (_) {
    // Never let error reporting cause a secondary failure.
  }
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
      // App Opened / Backgrounded / Installed / Updated, captured natively.
      ..captureApplicationLifecycleEvents = true
      ..personProfiles = PostHogPersonProfiles.identifiedOnly;
    await Posthog().setup(config);
  } catch (_) {
    // Never let analytics setup break app launch.
  }
}

/// Whether [error] is an environmental/transient failure rather than a code
/// defect, and therefore should be logged to Crashlytics as NON-fatal.
///
/// These surface as "crashes" only because the global handlers above forward
/// every uncaught error, but the app keeps running — a flaky/absent network, a
/// Firestore backend that's momentarily unreachable, a platform channel that
/// isn't wired on the current surface/isolate, or a bounded operation that
/// timed out. Reporting them as fatal wrecked the crash-free-users metric and
/// produced the repetitive `[cloud_firestore/unavailable]`,
/// `MissingPluginException` and timeout "crashes" on the dashboard.
bool _isNonFatalInfraError(Object error) {
  // Firestore/Firebase transient backend & connectivity conditions.
  if (error is FirebaseException) {
    const transientCodes = {
      'unavailable', // backend unreachable / offline — the top crash
      'deadline-exceeded', // request outlived its deadline
      'cancelled', // client cancelled (e.g. widget disposed mid-read)
      'aborted', // contention; safe to retry
      'resource-exhausted', // transient quota/backoff
      'internal', // transient server-side blip
      'network-request-failed', // no connectivity
      'unknown', // usually a wrapped socket/IO failure
    };
    return transientCodes.contains(error.code);
  }
  // A plugin method invoked where no platform implementation is registered
  // (background isolate, unsupported surface, or a race during app update).
  if (error is MissingPluginException) return true;
  // Our own bounded operations (getToken/subscribeToTopic/etc.) that timed out.
  if (error is TimeoutException) return true;
  // Environmental network/IO failures — a dropped/blocked connection, a reset
  // socket, a TLS handshake abort, a DNS miss, or an HTTP error on an image
  // fetch. These bubble up most often from NetworkImage loads (feed logos,
  // banners, favicons) when the device is offline or on a captive/flaky
  // network. They are NOT code defects and were being reported as FATAL,
  // wrecking the crash-free-users metric (the recurring
  // "SocketException"/"HttpException" crashes on the dashboard). Treat them as
  // non-fatal so they stay diagnosable without counting as crashes.
  if (_isNetworkIoError(error)) return true;
  return false;
}

/// Whether [error] is a transient network / socket / TLS / image-fetch failure.
///
/// Matched by runtime type NAME (not `is` against `dart:io` types) on purpose:
/// `main.dart` is compiled for web too, where importing `dart:io` fails to
/// compile. The names below are stable across the Dart SDK and Flutter's
/// painting layer, and are safe to match on every platform.
bool _isNetworkIoError(Object error) {
  switch (error.runtimeType.toString()) {
    case 'SocketException': // connection abort/refused/reset, DNS failure
    case 'HttpException': // malformed/aborted HTTP response
    case 'HandshakeException': // TLS negotiation failed
    case 'TlsException': // other TLS-layer failure
    case 'NetworkImageLoadException': // NetworkImage got a non-200 (also web)
    case 'ClientException': // package:http transport failure
      return true;
    default:
      return false;
  }
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
