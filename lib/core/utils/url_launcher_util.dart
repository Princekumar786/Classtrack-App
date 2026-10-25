import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches [uri] without ever throwing. Returns `true` if something opened it.
///
/// On Android, `launchUrl` throws `PlatformException(ACTIVITY_NOT_FOUND)` —
/// instead of returning false — when no app can handle the intent (e.g. the
/// user disabled Chrome / Samsung Internet, or an MDM policy blocks browsers).
/// That was an uncaught async crash in Crashlytics. For web links we fall back
/// to an in-app WebView, which works even with no browser installed.
Future<bool> safeLaunchUri(
  Uri uri, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  try {
    if (await launchUrl(uri, mode: mode)) return true;
  } catch (e) {
    debugPrint('launchUrl failed for $uri ($mode): $e');
  }
  final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
  if (isWeb && mode != LaunchMode.inAppWebView) {
    try {
      return await launchUrl(uri, mode: LaunchMode.inAppWebView);
    } catch (e) {
      debugPrint('inAppWebView fallback failed for $uri: $e');
    }
  }
  return false;
}

/// Opens [url] in an external app/browser. Shows a snackbar on failure.
///
/// SECURITY: only a small allowlist of schemes is permitted. Links come from
/// CMS content, user-entered subject resource links and shared URLs, so a bare
/// `launchUrl` could be coerced into opening dangerous schemes
/// (`file://`, `content://`, `intent://`, `javascript:`, `data:`, `smb://`, …).
/// A scheme-less input is treated as https.
Future<void> openUrl(BuildContext context, String? url) async {
  if (url == null || url.trim().isEmpty) return;
  var normalized = url.trim();
  if (!normalized.startsWith('http://') &&
      !normalized.startsWith('https://') &&
      !normalized.contains('://')) {
    normalized = 'https://$normalized';
  }
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Invalid link')));
    return;
  }
  // Allowlist: web links, email and phone only. Anything else is refused.
  const allowedSchemes = {'http', 'https', 'mailto', 'tel'};
  if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
    messenger.showSnackBar(const SnackBar(content: Text('Link type not allowed')));
    return;
  }
  final ok = await safeLaunchUri(uri);
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text('Could not open $normalized')));
  }
}
