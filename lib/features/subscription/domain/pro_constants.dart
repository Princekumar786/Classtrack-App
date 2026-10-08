import 'dart:io' show Platform;

/// Central configuration for ClassTrack Pro (RevenueCat subscriptions).
///
/// The two public SDK keys below are NOT secrets — RevenueCat public keys are
/// safe to ship in the client. Fill them in from your RevenueCat dashboard
/// (Project → API keys). Leaving them blank keeps the app fully functional
/// with subscriptions simply disabled (no paywall, everything on the free
/// tier), so the app never crashes before you finish store setup.
class ProConstants {
  ProConstants._();

  /// RevenueCat entitlement identifier that unlocks Pro. Create an entitlement
  /// with this id in the RevenueCat dashboard and attach your products to it.
  static const String entitlementId = 'pro';

  /// The RevenueCat "offering" to display on the paywall (usually 'default').
  static const String offeringId = 'default';

  /// Public SDK keys (safe to ship). Get these from RevenueCat → API keys.
  /// A build-time --dart-define overrides these defaults when provided.
  ///
  /// IMPORTANT: leave the defaults EMPTY. A `test_...` key makes the
  /// RevenueCat SDK show a "Wrong API Key" dialog and force-close the app in
  /// real builds. Supply your real public key (Android: `goog_...`,
  /// iOS: `appl_...`) at build time via --dart-define, e.g.:
  ///   flutter run --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
  static const String _androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'goog_eGHVsrMqbOpsYrtNTrUQUKtOSab',
  );
  static const String _iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: '',
  );

  /// Resolves the correct key for the current platform (empty when unset).
  static String get apiKey {
    try {
      if (Platform.isIOS || Platform.isMacOS) return _iosApiKey;
      return _androidApiKey;
    } catch (_) {
      return '';
    }
  }

  /// Whether subscriptions are configured. When false the app stays on the
  /// free tier everywhere and no paywall is shown.
  static bool get enabled => apiKey.trim().isNotEmpty;

  /// Free users get this many AI assistant messages per calendar month.
  /// Pro users are unlimited. Kept in sync with the server-side limit.
  static const int freeMonthlyChatLimit = 10;
}
