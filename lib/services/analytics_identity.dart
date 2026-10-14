import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/firebase_providers.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/subscription/presentation/providers/subscription_providers.dart';
import 'error_reporter.dart';

/// Person properties sent to PostHog for the signed-in student, built from
/// their ClassTrack profile (not just Firebase Auth, which has no name for
/// email/password sign-ups). Pure so it can be unit-tested.
Map<String, Object> posthogPersonProperties(
  AppUser profile, {
  required bool isPro,
  String? authEmail,
}) {
  void put(Map<String, Object> m, String k, Object? v) {
    if (v == null) return;
    if (v is String && v.trim().isEmpty) return;
    m[k] = v is String ? v.trim() : v;
  }

  final m = <String, Object>{};
  put(m, 'name', profile.displayName);
  put(m, 'email', profile.email ?? authEmail);
  put(m, 'country', profile.effectiveCountry);
  put(m, 'country_source', profile.countryIsDetected ? 'detected' : (profile.country == null ? null : 'profile'));
  put(m, 'university', profile.university);
  put(m, 'college', profile.college);
  put(m, 'degree', profile.degree);
  put(m, 'semester', profile.semester);
  put(m, 'academic_year', profile.academicYear);
  m['is_pro'] = isPro;
  m['referral_count'] = profile.referralCount;
  m['app_version'] = AppConstants.appVersion;
  return m;
}

/// Keeps the PostHog person for the signed-in user up to date with their
/// profile (name, email, country, college, semester, Pro), so the Activity /
/// Persons views show WHO did what by name. Also registers `is_pro` and
/// `app_version` as super properties so every event carries them. Re-sends
/// only when something actually changed. Watched by HomeShell.
final posthogIdentitySyncProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final isPro = ref.watch(isProProvider);
  if (uid == null || profile == null || profile.uid != uid) return;

  final props = posthogPersonProperties(profile, isPro: isPro);
  final signature = '$uid|${props.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  if (signature == _lastSent) return;
  _lastSent = signature;
  try {
    Posthog().identify(userId: uid, userProperties: props);
    Posthog().register('is_pro', isPro);
    Posthog().register('app_version', AppConstants.appVersion);
  } catch (_) {
    // Analytics must never break the app.
  }
  // Same context on Crashlytics issues (searchable custom keys).
  ErrorReporter.setUser(uid, keys: {
    'is_pro': isPro,
    'country': profile.effectiveCountry ?? 'unknown',
  });
});

String? _lastSent;

/// Clears the cached identity (call on sign-out so the next account re-sends).
void resetPosthogIdentityCache() => _lastSent = null;
