import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// One place that sends every error to BOTH Firebase Crashlytics and PostHog
/// error tracking, with the same tags, so an issue can be spotted and triaged
/// from either dashboard.
///
/// Every report carries:
///  • `fatal` — true only for genuine code defects that escaped every handler.
///  • `error_kind` — `defect` (a bug to fix) or `transient` (network/offline/
///    timeout; filter these out in PostHog with `error_kind = defect`).
///  • `reason` — where it happened (e.g. `attendance_mark`, `provider:subjects`).
///  • `screen` — the last screen the user opened.
/// plus the signed-in user id (set via [setUser]) on both sinks.
///
/// Identical errors are throttled (once per [_throttle] per signature) so an
/// offline retry loop can't flood either dashboard. Never throws.
class ErrorReporter {
  ErrorReporter._();

  static const Duration _throttle = Duration(seconds: 60);
  static final Map<String, DateTime> _recent = <String, DateTime>{};
  static String? _screen;

  /// Disabled in debug and tests (mirrors the Crashlytics/PostHog opt-out).
  @visibleForTesting
  static bool enabled = !kDebugMode;

  /// Test hook: every report is passed here (even when [enabled] is false).
  @visibleForTesting
  static void Function(ErrorReport report)? debugSink;

  static bool get _crashlyticsAvailable => !kIsWeb && Firebase.apps.isNotEmpty;

  /// Sends [error] to Crashlytics and PostHog. [fatal] is forced to false for
  /// transient infra errors, so they never count against crash-free users.
  static void report(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, Object>? extra,
  }) {
    if (isKnownHarmlessError(error, reason)) return;
    final transient = isTransientError(error);
    final isFatal = fatal && !transient;
    final r = ErrorReport(
      error: error,
      stack: stack ?? StackTrace.current,
      reason: reason,
      fatal: isFatal,
      kind: transient ? 'transient' : 'defect',
      screen: _screen,
    );
    debugSink?.call(r);
    if (!enabled) return;
    if (!isFatal && _isThrottled(r.signature)) return;

    if (_crashlyticsAvailable) {
      try {
        unawaited(FirebaseCrashlytics.instance.recordError(
          error,
          r.stack,
          reason: reason,
          fatal: isFatal,
          information: [
            'error_kind: ${r.kind}',
            if (_screen != null) 'screen: $_screen',
            if (extra != null) for (final e in extra.entries) '${e.key}: ${e.value}',
          ],
        ));
      } catch (_) {}
    }
    try {
      unawaited(Posthog().captureException(
        error: error,
        stackTrace: r.stack,
        properties: {
          'fatal': isFatal,
          'error_kind': r.kind,
          if (reason != null) 'reason': reason,
          if (_screen != null) 'screen': _screen!,
          ...?extra,
        },
      ));
    } catch (_) {}
  }

  /// Forwards a Flutter framework error, keeping Flutter's own context text.
  static void reportFlutterError(FlutterErrorDetails details,
      {bool fatal = true}) {
    report(
      details.exception,
      details.stack,
      reason: details.context?.toDescription() ?? details.library,
      fatal: fatal && !details.silent,
    );
  }

  /// Ties reports to the signed-in user (or clears it on sign-out) and keeps
  /// a few searchable custom keys on Crashlytics issues.
  static void setUser(String? uid, {Map<String, Object> keys = const {}}) {
    if (!enabled || !_crashlyticsAvailable) return;
    try {
      final c = FirebaseCrashlytics.instance;
      unawaited(c.setUserIdentifier(uid ?? ''));
      for (final e in keys.entries) {
        unawaited(c.setCustomKey(e.key, e.value));
      }
    } catch (_) {}
  }

  /// Breadcrumb: the screen the user is on. Shown in the Crashlytics "Logs"
  /// tab and on every PostHog exception as `screen`.
  static void setScreen(String? name) {
    if (name == null || name.isEmpty || name == _screen) return;
    _screen = name;
    if (!enabled || !_crashlyticsAvailable) return;
    try {
      final c = FirebaseCrashlytics.instance;
      unawaited(c.setCustomKey('screen', name));
      unawaited(c.log('screen: $name'));
    } catch (_) {}
  }

  /// Breadcrumb for an important user action (e.g. "mark attendance").
  static void log(String message) {
    if (!enabled || !_crashlyticsAvailable) return;
    try {
      unawaited(FirebaseCrashlytics.instance.log(message));
    } catch (_) {}
  }

  static bool _isThrottled(String signature) {
    final now = DateTime.now();
    final last = _recent[signature];
    if (last != null && now.difference(last) < _throttle) return true;
    if (_recent.length > 200) _recent.clear();
    _recent[signature] = now;
    return false;
  }

  @visibleForTesting
  static void resetForTest() {
    _recent.clear();
    _screen = null;
  }
}

/// A single error report, as passed to [ErrorReporter.debugSink].
class ErrorReport {
  final Object error;
  final StackTrace stack;
  final String? reason;
  final bool fatal;
  final String kind;
  final String? screen;
  const ErrorReport({
    required this.error,
    required this.stack,
    required this.reason,
    required this.fatal,
    required this.kind,
    required this.screen,
  });

  // Ids inside a reason (e.g. a per-transaction channel name) are replaced so
  // identical errors share one signature and the throttle actually applies.
  String get signature {
    final r = reason?.replaceAll(_uuid, '<id>');
    final e = '$error'.replaceAll(_uuid, '<id>');
    return '${error.runtimeType}|$r|${e.length > 200 ? e.substring(0, 200) : e}';
  }
}

final RegExp _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

/// Errors that are known plugin noise with no effect on the user, so they are
/// not reported at all:
///  • FlutterFire Android calls `cancel` on a Firestore transaction's event
///    channel after the native side already removed it. The transaction itself
///    succeeded. (~900 PostHog events a week on 1.0.61.)
bool isKnownHarmlessError(Object error, String? reason) {
  if (error is MissingPluginException) {
    final where = '${reason ?? ''} $error';
    if (where.contains('firebase_firestore/transaction/')) return true;
  }
  return false;
}

/// Whether [error] is an environmental/transient failure (offline, backend
/// briefly unavailable, timeout, missing plugin on this surface) rather than a
/// code defect. Such errors are still REPORTED (as non-fatal, `transient`) so
/// they stay visible, but never counted as crashes.
bool isTransientError(Object error) {
  if (error is FirebaseException) {
    const transientCodes = {
      'unavailable',
      'deadline-exceeded',
      'cancelled',
      'aborted',
      'resource-exhausted',
      'internal',
      'network-request-failed',
      'unknown',
      'too-many-requests',
    };
    return transientCodes.contains(error.code);
  }
  if (error is MissingPluginException) return true;
  if (error is TimeoutException) return true;
  // Matched by type NAME so this file also compiles for web (no dart:io).
  switch (error.runtimeType.toString()) {
    case 'SocketException':
    case 'HttpException':
    case 'HandshakeException':
    case 'TlsException':
    case 'NetworkImageLoadException':
    case 'ClientException':
      return true;
  }
  return false;
}

/// Logs every pushed/popped route name as a breadcrumb (see
/// [ErrorReporter.setScreen]). Add to the router's observers.
class ErrorReporterRouteObserver extends NavigatorObserver {
  void _set(Route<dynamic>? route) => ErrorReporter.setScreen(route?.settings.name);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);
}
