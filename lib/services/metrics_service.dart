import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/firebase_providers.dart';

/// Writes append-only engagement events to `events/{id}`, which a Cloud
/// Function folds into queryable CMS counters (and sponsor reports). Fire-and-
/// forget and crash-proof so analytics can never break a student flow.
///
/// Canonical resource events: 'impression', 'view', 'click', 'apply', 'save',
/// 'share'. Banner events: 'impression', 'click'. This is complementary to
/// [AnalyticsService] (PostHog) — those events aren't queryable from the CMS,
/// these counters are.
class MetricsService {
  final FirebaseFirestore? _db;
  final String? _uid;
  MetricsService(this._db, this._uid);

  /// Impressions already sent this app session (`r:<id>` / `b:<id>`). A card
  /// scrolling in and out, or a feed rebuilding, must not inflate the count —
  /// sponsors expect "seen once per session", like ad-network impressions.
  static final Set<String> _impressedThisSession = {};

  /// Test hook to reset the per-session de-duplication.
  static void resetSessionForTest() => _impressedThisSession.clear();

  Future<void> record({
    required String resourceId,
    required String event,
    String? type,
    String? title,
  }) async {
    if (_uid == null || resourceId.isEmpty) return;
    await _write({
      'resourceId': resourceId,
      'event': event,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
    });
  }

  /// A resource card was shown in a feed. Sent at most once per resource per
  /// app session.
  Future<void> recordImpression(String resourceId) async {
    if (_uid == null || resourceId.isEmpty) return;
    if (!_impressedThisSession.add('r:$resourceId')) return;
    await _write({'resourceId': resourceId, 'event': 'impression'});
  }

  /// A CMS banner was shown ('impression', once per session) or tapped
  /// ('click').
  Future<void> recordBanner(String bannerId, String event) async {
    if (_uid == null || bannerId.isEmpty) return;
    if (event == 'impression' && !_impressedThisSession.add('b:$bannerId')) {
      return;
    }
    await _write({'bannerId': bannerId, 'event': event});
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.collection(AppConstants.eventsCollection).add({
        ...data,
        'uid': _uid,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Analytics must never surface as an app error.
    }
  }
}

final metricsServiceProvider = Provider<MetricsService>((ref) {
  // Analytics must never break a screen: if Firebase isn't available (e.g.
  // widget tests, or a failed init) fall back to a no-op service.
  try {
    return MetricsService(
      ref.watch(firestoreProvider),
      ref.watch(currentUidProvider),
    );
  } catch (_) {
    return MetricsService(null, null);
  }
});
