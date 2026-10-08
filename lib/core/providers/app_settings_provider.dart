import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'firebase_providers.dart';

/// SharedPreferences instance — overridden in main() after it is loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

/// Wraps [SharedPreferences] so each key is stored **per signed-in user**
/// (`"$key::$uid"`).
///
/// Why: settings used to live under a single device-global key, so two accounts
/// on the same phone shared one value — a standard account would inherit a Pro
/// account's custom accent colour, and (worse) its on-device API key and
/// reminder state. Namespacing by uid isolates every account's personalisation.
///
/// When signed out (`uid == null`) nothing is read or written: callers fall
/// back to their defaults, so a logged-out shell never surfaces the previous
/// user's state (and a fresh account never re-schedules the previous account's
/// reminders).
///
/// A one-time migration copies any value still stored under the OLD global key
/// into the current user's namespace on first access, then deletes the global
/// copy — so the legacy value can neither leak to the *next* account on this
/// device nor be restored onto another device.
class ScopedPrefs {
  ScopedPrefs(this._prefs, this._uid);

  final SharedPreferences _prefs;
  final String? _uid;

  bool get isActive => _uid != null;

  String _key(String base) => '$base::$_uid';

  /// Adopt a legacy global value (if any) into this user's namespace, once,
  /// then drop the global copy. No-op when signed out, when the scoped value
  /// already exists, or when there is no legacy value to move.
  void _migrate(String base) {
    if (_uid == null) return;
    final scoped = _key(base);
    if (_prefs.containsKey(scoped)) return;
    if (!_prefs.containsKey(base)) return;
    final Object? v = _prefs.get(base);
    // shared_preferences updates its in-memory cache synchronously, so the
    // subsequent read in the same call sees the migrated value; the disk write
    // completes in the background.
    if (v is bool) {
      unawaited(_prefs.setBool(scoped, v));
    } else if (v is int) {
      unawaited(_prefs.setInt(scoped, v));
    } else if (v is double) {
      unawaited(_prefs.setDouble(scoped, v));
    } else if (v is String) {
      unawaited(_prefs.setString(scoped, v));
    } else if (v is List<String>) {
      unawaited(_prefs.setStringList(scoped, v));
    }
    unawaited(_prefs.remove(base));
  }

  bool? getBool(String base) {
    if (_uid == null) return null;
    _migrate(base);
    return _prefs.getBool(_key(base));
  }

  int? getInt(String base) {
    if (_uid == null) return null;
    _migrate(base);
    return _prefs.getInt(_key(base));
  }

  String? getString(String base) {
    if (_uid == null) return null;
    _migrate(base);
    return _prefs.getString(_key(base));
  }

  Future<void> setBool(String base, bool value) async {
    if (_uid == null) return;
    await _prefs.setBool(_key(base), value);
  }

  Future<void> setInt(String base, int value) async {
    if (_uid == null) return;
    await _prefs.setInt(_key(base), value);
  }

  Future<void> setString(String base, String value) async {
    if (_uid == null) return;
    await _prefs.setString(_key(base), value);
  }

  Future<void> remove(String base) async {
    if (_uid == null) return;
    await _prefs.remove(_key(base));
  }
}

/// Per-user view of SharedPreferences for the currently signed-in account.
/// Rebuilds whenever the signed-in uid changes, so every dependent setting
/// controller reloads that account's values (and clears back to defaults on
/// sign-out).
final scopedPrefsProvider = Provider<ScopedPrefs>((ref) {
  final uid = ref.watch(currentUidProvider);
  return ScopedPrefs(ref.watch(sharedPrefsProvider), uid);
});

/// Whether the user has completed onboarding.
///
/// Intentionally **device-global** (not per-user): onboarding introduces the
/// app itself, so it should show once per install, not once per account.
class OnboardingController extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  OnboardingController(this._prefs)
      : super(_prefs.getBool(AppConstants.prefsOnboardingDone) ?? false);

  Future<void> complete() async {
    await _prefs.setBool(AppConstants.prefsOnboardingDone, true);
    state = true;
  }

  Future<void> reset() async {
    await _prefs.setBool(AppConstants.prefsOnboardingDone, false);
    state = false;
  }
}

final onboardingDoneProvider =
    StateNotifierProvider<OnboardingController, bool>((ref) {
  return OnboardingController(ref.watch(sharedPrefsProvider));
});

/// Whether the first-time in-app "home tour" (coach-mark walkthrough of the
/// bottom nav and quick-add button) has been shown.
///
/// Device-global (not per-user), same as onboarding: the tour explains the
/// app's UI, so it should appear once per install rather than once per account.
class HomeTourController extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  HomeTourController(this._prefs)
      : super(_prefs.getBool(AppConstants.prefsHomeTourDone) ?? false);

  Future<void> complete() async {
    await _prefs.setBool(AppConstants.prefsHomeTourDone, true);
    state = true;
  }

  /// Re-arms the tour so it plays again (used by the "Show app tour" action in
  /// Settings).
  Future<void> reset() async {
    await _prefs.setBool(AppConstants.prefsHomeTourDone, false);
    state = false;
  }
}

final homeTourDoneProvider =
    StateNotifierProvider<HomeTourController, bool>((ref) {
  return HomeTourController(ref.watch(sharedPrefsProvider));
});

/// Tracks whether a one-time feature-discovery tip (💡) has been dismissed.
///
/// Keyed by the tip's SharedPreferences key (e.g. [AppConstants.prefsTipNotes]).
/// Device-global — like the onboarding + home tour — because these tips teach
/// the app's features, so they should appear once per install rather than once
/// per account.
class FeatureTipController extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  final String _key;
  FeatureTipController(this._prefs, this._key)
      : super(_prefs.getBool(_key) ?? false);

  /// Marks the tip as seen so it never shows again.
  Future<void> dismiss() async {
    if (state) return;
    state = true;
    await _prefs.setBool(_key, true);
  }

  /// Re-arms the tip (used only for testing / a future "reset tips" action).
  Future<void> reset() async {
    state = false;
    await _prefs.setBool(_key, false);
  }
}

/// Family of one-time feature tips, keyed by their SharedPreferences key.
final featureTipProvider =
    StateNotifierProvider.family<FeatureTipController, bool, String>(
  (ref, key) => FeatureTipController(ref.watch(sharedPrefsProvider), key),
);

/// App theme mode (system/light/dark), persisted per user.
class ThemeModeController extends StateNotifier<ThemeMode> {
  final ScopedPrefs _prefs;
  ThemeModeController(this._prefs) : super(_load(_prefs));

  static ThemeMode _load(ScopedPrefs prefs) {
    final raw = prefs.getString(AppConstants.prefsThemeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(AppConstants.prefsThemeMode, mode.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(scopedPrefsProvider));
});

/// How times are shown everywhere in the app (schedule, home, reminders UI).
enum TimeFormatPref {
  /// Follow the phone's 12/24-hour clock setting (the previous behaviour).
  system,
  twelveHour,
  twentyFourHour;

  String get wire => switch (this) {
        TimeFormatPref.system => 'system',
        TimeFormatPref.twelveHour => '12h',
        TimeFormatPref.twentyFourHour => '24h',
      };

  String get label => switch (this) {
        TimeFormatPref.system => 'Auto',
        TimeFormatPref.twelveHour => '12-hour',
        TimeFormatPref.twentyFourHour => '24-hour',
      };

  static TimeFormatPref parse(String? v) => switch (v?.trim().toLowerCase()) {
        '12h' || '12' || '12-hour' || 'twelvehour' => TimeFormatPref.twelveHour,
        '24h' || '24' || '24-hour' || 'twentyfourhour' => TimeFormatPref.twentyFourHour,
        _ => TimeFormatPref.system,
      };

  /// Value for MediaQuery.alwaysUse24HourFormat, or null to keep the phone's.
  bool? get use24 => switch (this) {
        TimeFormatPref.system => null,
        TimeFormatPref.twelveHour => false,
        TimeFormatPref.twentyFourHour => true,
      };
}

class TimeFormatController extends StateNotifier<TimeFormatPref> {
  final ScopedPrefs _prefs;
  TimeFormatController(this._prefs)
      : super(TimeFormatPref.parse(_prefs.getString(AppConstants.prefsTimeFormat)));

  Future<void> set(TimeFormatPref value) async {
    state = value;
    await _prefs.setString(AppConstants.prefsTimeFormat, value.wire);
  }
}

final timeFormatProvider =
    StateNotifierProvider<TimeFormatController, TimeFormatPref>((ref) {
  return TimeFormatController(ref.watch(scopedPrefsProvider));
});

/// On-device Gemini API key (entered by the user in Settings). Per user, so one
/// account can never read or reuse another account's key on a shared device.
class GeminiKeyController extends StateNotifier<String?> {
  final ScopedPrefs _prefs;
  GeminiKeyController(this._prefs)
      : super(_prefs.getString(AppConstants.prefsGeminiKey));

  bool get hasKey => (state ?? '').trim().isNotEmpty;

  Future<void> set(String key) async {
    final trimmed = key.trim();
    await _prefs.setString(AppConstants.prefsGeminiKey, trimmed);
    state = trimmed;
  }

  Future<void> clear() async {
    await _prefs.remove(AppConstants.prefsGeminiKey);
    state = null;
  }
}

final geminiKeyProvider =
    StateNotifierProvider<GeminiKeyController, String?>((ref) {
  return GeminiKeyController(ref.watch(scopedPrefsProvider));
});

/// How many minutes before a class/task to fire the reminder (e.g. 10 or 30).
class ReminderLeadController extends StateNotifier<int> {
  final ScopedPrefs _prefs;
  ReminderLeadController(this._prefs)
      : super(_prefs.getInt(AppConstants.prefsReminderLead) ?? 10);

  Future<void> set(int minutes) async {
    state = minutes;
    await _prefs.setInt(AppConstants.prefsReminderLead, minutes);
  }
}

final reminderLeadProvider =
    StateNotifierProvider<ReminderLeadController, int>((ref) {
  return ReminderLeadController(ref.watch(scopedPrefsProvider));
});

/// Whether the user has enabled reminders (set true after granting permission
/// and scheduling from Settings). Drives automatic re-sync of reminders.
///
/// Per user: a fresh account on a shared device starts with reminders OFF
/// instead of inheriting the previous account's "enabled" flag and immediately
/// re-scheduling notifications for data that isn't theirs.
class RemindersEnabledController extends StateNotifier<bool> {
  final ScopedPrefs _prefs;
  RemindersEnabledController(this._prefs)
      : super(_prefs.getBool(AppConstants.prefsRemindersEnabled) ?? false);

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBool(AppConstants.prefsRemindersEnabled, value);
  }
}

final remindersEnabledProvider =
    StateNotifierProvider<RemindersEnabledController, bool>((ref) {
  return RemindersEnabledController(ref.watch(scopedPrefsProvider));
});

/// Grading scale used to compute GPA: 4.0 scale or 10-point (CGPA).
enum GpaScaleType { four, ten }

class GpaScaleController extends StateNotifier<GpaScaleType> {
  final ScopedPrefs _prefs;
  GpaScaleController(this._prefs)
      : super(_prefs.getString(AppConstants.prefsGpaScale) == 'ten'
            ? GpaScaleType.ten
            : GpaScaleType.four);

  Future<void> set(GpaScaleType type) async {
    state = type;
    await _prefs.setString(
        AppConstants.prefsGpaScale, type == GpaScaleType.ten ? 'ten' : 'four');
  }
}

final gpaScaleProvider =
    StateNotifierProvider<GpaScaleController, GpaScaleType>((ref) {
  return GpaScaleController(ref.watch(scopedPrefsProvider));
});

/// User-chosen accent color (Pro). Null = the default ClassTrack purple.
/// Stored as an ARGB int; 0 means "use default". Per user, so a custom colour
/// set on one account no longer bleeds onto another account on the same device.
class AccentColorController extends StateNotifier<Color?> {
  final ScopedPrefs _prefs;
  AccentColorController(this._prefs) : super(_load(_prefs));

  static Color? _load(ScopedPrefs p) {
    final v = p.getInt(AppConstants.prefsAccentColor) ?? 0;
    return v == 0 ? null : Color(v);
  }

  Future<void> set(Color? color) async {
    state = color;
    if (color == null) {
      await _prefs.remove(AppConstants.prefsAccentColor);
    } else {
      await _prefs.setInt(AppConstants.prefsAccentColor, color.toARGB32());
    }
  }
}

final accentColorProvider =
    StateNotifierProvider<AccentColorController, Color?>((ref) {
  return AccentColorController(ref.watch(scopedPrefsProvider));
});
