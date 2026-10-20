import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/app_settings_provider.dart';
import 'analytics_service.dart';

/// How to offer an available update.
enum UpdateMode { none, flexible, immediate }

/// Pure rules for which Google Play update flow to use (unit-tested).
///
///  • Immediate (full-screen, must update) for important releases: an
///    update priority of 4–5 set when publishing, or a version the student has
///    ignored for [staleDaysForImmediate]+ days.
///  • Flexible (downloads in the background, "Restart" when ready) otherwise.
class UpdatePolicy {
  UpdatePolicy._();

  static const int immediatePriority = 4;
  static const int staleDaysForImmediate = 14;

  /// Ask Play at most this often (resuming a downloaded update is not limited).
  static const Duration checkEvery = Duration(hours: 12);

  static UpdateMode decide({
    required bool available,
    required int priority,
    required int? stalenessDays,
    required bool immediateAllowed,
    required bool flexibleAllowed,
  }) {
    if (!available) return UpdateMode.none;
    final urgent = priority >= immediatePriority ||
        (stalenessDays ?? 0) >= staleDaysForImmediate;
    if (urgent && immediateAllowed) return UpdateMode.immediate;
    if (flexibleAllowed) return UpdateMode.flexible;
    if (immediateAllowed) return UpdateMode.immediate;
    return UpdateMode.none;
  }

  static bool dueForCheck(DateTime now, DateTime? lastCheck) =>
      lastCheck == null || now.difference(lastCheck) >= checkEvery;
}

/// Google Play in-app updates (Android only; no-op elsewhere and in debug,
/// where Play can't serve updates to a side-loaded build).
class AppUpdateService {
  AppUpdateService(this._prefs, {AnalyticsService? analytics}) : _analytics = analytics;

  final SharedPreferences _prefs;
  final AnalyticsService? _analytics;
  StreamSubscription<InstallStatus>? _installSub;
  bool _busy = false;
  bool _readyShown = false;

  static bool get supported =>
      !kIsWeb && !kDebugMode && defaultTargetPlatform == TargetPlatform.android;

  /// Checks Play for an update and starts the right flow. [onReadyToInstall]
  /// is called once a flexible update has finished downloading. Never throws.
  Future<void> check({required VoidCallback onReadyToInstall, bool force = false}) async {
    if (!supported || _busy) return;
    _busy = true;
    try {
      final info = await InAppUpdate.checkForUpdate();

      // A flexible update finished downloading while we were away.
      if (info.installStatus == InstallStatus.downloaded) {
        _notifyReady(onReadyToInstall);
        return;
      }
      // An immediate update was interrupted: Play requires us to resume it.
      if (info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }

      final now = DateTime.now();
      final last = _prefs.getInt(AppConstants.prefsUpdateLastCheckAt);
      if (!force &&
          !UpdatePolicy.dueForCheck(
              now, last == null ? null : DateTime.fromMillisecondsSinceEpoch(last))) {
        return;
      }
      await _prefs.setInt(AppConstants.prefsUpdateLastCheckAt, now.millisecondsSinceEpoch);

      final mode = UpdatePolicy.decide(
        available: info.updateAvailability == UpdateAvailability.updateAvailable,
        priority: info.updatePriority,
        stalenessDays: info.clientVersionStalenessDays,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
      );
      if (mode == UpdateMode.none) return;
      unawaited(_analytics?.log('app_update_offered', {
        'mode': mode.name,
        'priority': info.updatePriority,
        'stale_days': info.clientVersionStalenessDays ?? 0,
      }));

      if (mode == UpdateMode.immediate) {
        final r = await InAppUpdate.performImmediateUpdate();
        unawaited(_analytics?.log('app_update_result', {'mode': 'immediate', 'result': r.name}));
        return;
      }

      _installSub ??= InAppUpdate.installUpdateListener.listen((s) {
        if (s == InstallStatus.downloaded) _notifyReady(onReadyToInstall);
      });
      final r = await InAppUpdate.startFlexibleUpdate();
      unawaited(_analytics?.log('app_update_result', {'mode': 'flexible', 'result': r.name}));
    } catch (_) {
      // Play not available (side-loaded, emulator without Play, offline…).
    } finally {
      _busy = false;
    }
  }

  void _notifyReady(VoidCallback cb) {
    if (_readyShown) return;
    _readyShown = true;
    cb();
  }

  /// Restarts the app into the downloaded version.
  Future<void> install() async {
    try {
      unawaited(_analytics?.log('app_update_installed'));
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      _readyShown = false; // let the next resume offer it again
    }
  }

  void dispose() => _installSub?.cancel();
}

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final s = AppUpdateService(ref.watch(sharedPrefsProvider), analytics: ref.read(analyticsProvider));
  ref.onDispose(s.dispose);
  return s;
});

/// App-wide messenger so update banners can show from anywhere.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Checks for a Play update after the first frame and on every return to the
/// app, and shows a "Restart to update" snackbar once a download is ready.
class AppUpdateChecker extends ConsumerStatefulWidget {
  const AppUpdateChecker({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends ConsumerState<AppUpdateChecker> {
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    if (!AppUpdateService.supported) return;
    // Let the app settle (auth, home) before talking to Play.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), _check);
    });
    _life = AppLifecycleListener(onResume: _check);
  }

  void _check() {
    if (!mounted) return;
    ref.read(appUpdateServiceProvider).check(onReadyToInstall: _showReady);
  }

  void _showReady() {
    rootMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('A new version of ClassTrack is ready.'),
        duration: const Duration(days: 1), // stays until acted on
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'RESTART',
          onPressed: () => ref.read(appUpdateServiceProvider).install(),
        ),
      ));
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
