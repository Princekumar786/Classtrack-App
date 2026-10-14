import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/firebase_providers.dart';
import '../features/auth/domain/profile_options.dart';
import '../features/auth/presentation/providers/auth_providers.dart';

/// ISO 3166 alpha-2 → the country NAMES the app and CMS target with
/// ([ProfileOptions.countries]). Only these are targetable, so other codes are
/// ignored rather than stored as a name nobody can target.
const Map<String, String> kIsoToTargetCountry = {
  'in': 'India',
  'us': 'United States',
  'gb': 'United Kingdom',
  'uk': 'United Kingdom',
  'ca': 'Canada',
  'au': 'Australia',
  'de': 'Germany',
  'fr': 'France',
  'sg': 'Singapore',
  'ae': 'United Arab Emirates',
  'ng': 'Nigeria',
  'pk': 'Pakistan',
  'bd': 'Bangladesh',
  'np': 'Nepal',
  'lk': 'Sri Lanka',
  'za': 'South Africa',
};

/// Where a detected country came from (most → least reliable).
enum CountrySource { sim, network, deviceRegion }

class DetectedCountry {
  final String name;
  final CountrySource source;
  const DetectedCountry(this.name, this.source);
}

/// Pure detection rule: SIM country, then mobile network, then the phone's
/// region setting. The region setting is last because many Indian phones are
/// set to English (United States).
DetectedCountry? pickCountry({String? sim, String? network, String? region}) {
  String? name(String? code) =>
      code == null ? null : kIsoToTargetCountry[code.trim().toLowerCase()];
  final s = name(sim);
  if (s != null) return DetectedCountry(s, CountrySource.sim);
  final n = name(network);
  if (n != null) return DetectedCountry(n, CountrySource.network);
  final r = name(region);
  if (r != null) return DetectedCountry(r, CountrySource.deviceRegion);
  return null;
}

/// Reads the phone's country signals. Android uses the SIM / network country
/// (no permission, no location); other platforms use the region setting.
class CountryDetector {
  static const _channel = MethodChannel('classtrack/country');

  Future<DetectedCountry?> detect() async {
    String? sim, network;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final m = await _channel
            .invokeMapMethod<String, String>('getTelephonyCountry')
            .timeout(const Duration(seconds: 3));
        sim = m?['sim'];
        network = m?['network'];
      } catch (_) {/* no telephony / old build: fall back below */}
    }
    final region = PlatformDispatcher.instance.locale.countryCode;
    return pickCountry(sim: sim, network: network, region: region);
  }
}

final countryDetectorProvider = Provider<CountryDetector>((_) => CountryDetector());

/// Detects once per app run.
final detectedCountryProvider = FutureProvider<DetectedCountry?>((ref) {
  return ref.watch(countryDetectorProvider).detect();
});

/// Keeps `users/{uid}.detectedCountry` up to date so the app AND the backend
/// (CMS audience counts, push targeting via the device topic) can fall back
/// to it when the student hasn't picked a country. Watched by HomeShell.
/// Only writes when the value actually changed.
final countryDetectionSyncProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  final profile = ref.watch(userProfileProvider).valueOrNull;
  final detected = ref.watch(detectedCountryProvider).valueOrNull;
  if (uid == null || profile == null || detected == null) return;
  if (profile.detectedCountry == detected.name) return;
  ref
      .read(firestoreProvider)
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .set({
        'detectedCountry': detected.name,
        'detectedCountrySource': detected.source.name,
        'detectedCountryAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
      .catchError((_) {/* best-effort; retried next start */});
});
