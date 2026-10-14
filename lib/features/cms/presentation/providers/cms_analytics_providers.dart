import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/firestore_parsing.dart';
import '../../domain/cms_analytics.dart';

/// Backend-written banner counters (impressions, clicks, reach).
const String kBannerMetricsCollection = 'bannerMetrics';

/// Global per-day engagement totals (most recent ~120 days) for windowed
/// funnels. Written by the backend; readable by any CMS role.
final cmsDailyMetricsProvider = StreamProvider<List<DailyMetric>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(AppConstants.metricsDailyCollection)
      .orderBy('day', descending: true)
      .limit(120)
      .snapshots()
      .map(
        (snap) => parseDocsSafely(
          snap.docs,
          DailyMetric.fromMap,
          context: 'metricsDaily',
        ),
      );
});

/// Per-resource all-time engagement totals for Top Content + sponsor reports.
final cmsResourceMetricsProvider = StreamProvider<List<ResourceMetric>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(AppConstants.resourceMetricsCollection)
      .limit(500)
      .snapshots()
      .map(
        (snap) => parseDocsSafely(
          snap.docs,
          ResourceMetric.fromMap,
          context: 'resourceMetrics',
        ),
      );
});

/// Per-banner all-time totals.
final cmsBannerMetricsProvider = StreamProvider<List<BannerMetric>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(kBannerMetricsCollection)
      .limit(200)
      .snapshots()
      .map(
        (snap) => parseDocsSafely(
          snap.docs,
          BannerMetric.fromMap,
          context: 'bannerMetrics',
        ),
      );
});

/// Identifies one item's daily buckets: `(collection, id)`.
typedef MetricsItem = ({String collection, String id});

/// Daily buckets for one resource or banner (last ~400 days), for campaign
/// windows, trend charts and CSV export.
final cmsItemDailyProvider =
    StreamProvider.family<List<DailyMetric>, MetricsItem>((ref, item) {
      final db = ref.watch(firestoreProvider);
      return db
          .collection(item.collection)
          .doc(item.id)
          .collection('daily')
          .orderBy('day', descending: true)
          .limit(400)
          .snapshots()
          .map(
            (snap) => parseDocsSafely(
              snap.docs,
              DailyMetric.fromMap,
              context: 'daily',
            ),
          );
    });
