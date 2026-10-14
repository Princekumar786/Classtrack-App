import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/cms_notification.dart';
import '../domain/marketing.dart';

/// Write-capable access to `banners` and `campaigns`, used by the CMS marketing
/// roles. Every write stamps `updatedBy` (required by the security rules and
/// used by the audit-log triggers).
class CmsMarketingRepository {
  final FirebaseFirestore _db;
  final String editorUid;
  CmsMarketingRepository({
    required FirebaseFirestore db,
    required this.editorUid,
  }) : _db = db;

  CollectionReference<Map<String, dynamic>> get _banners =>
      _db.collection(AppConstants.bannersCollection);
  CollectionReference<Map<String, dynamic>> get _campaigns =>
      _db.collection(AppConstants.campaignsCollection);

  // ── Banners ────────────────────────────────────────────────────────────
  Stream<List<CmsBanner>> watchBanners({int limit = 300}) {
    return _banners
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => parseDocsSafely(s.docs, CmsBanner.fromMap, context: 'banners'),
        );
  }

  Future<String> saveBanner(CmsBanner b) async {
    final map = b.toMap()..['updatedBy'] = editorUid;
    if (b.id.isEmpty) {
      final doc = _banners.doc();
      await doc.set(map);
      return doc.id;
    }
    await _banners.doc(b.id).set(map, SetOptions(merge: true));
    return b.id;
  }

  Future<void> setBannerPublished(String id, bool published) =>
      _banners.doc(id).set({
        'published': published,
        'updatedBy': editorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> deleteBanner(String id) => _banners.doc(id).delete();

  // ── Campaigns ──────────────────────────────────────────────────────────
  Stream<List<Campaign>> watchCampaigns({int limit = 300}) {
    return _campaigns
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) =>
              parseDocsSafely(s.docs, Campaign.fromMap, context: 'campaigns'),
        );
  }

  Future<String> saveCampaign(Campaign c) async {
    final map = c.toMap()..['updatedBy'] = editorUid;
    if (c.id.isEmpty) {
      final doc = _campaigns.doc();
      await doc.set(map);
      return doc.id;
    }
    await _campaigns.doc(c.id).set(map, SetOptions(merge: true));
    return c.id;
  }

  Future<void> setCampaignPublished(String id, bool published) =>
      _campaigns.doc(id).set({
        'published': published,
        'updatedBy': editorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> deleteCampaign(String id) => _campaigns.doc(id).delete();

  // ── Targeted notifications ───────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection(AppConstants.notificationsCollection);

  Stream<List<CmsNotification>> watchNotifications({int limit = 100}) {
    return _notifications
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => parseDocsSafely(
            s.docs,
            CmsNotification.fromMap,
            context: 'notifications',
          ),
        );
  }

  /// Enqueues a notification for the backend to deliver. `country` null/empty
  /// or "Global" broadcasts to everyone.
  Future<void> enqueueNotification({
    required String title,
    required String body,
    String? country,
    String? payload,
  }) {
    return _notifications.add({
      'title': title,
      'body': body,
      'country': (country == null || country.trim().isEmpty) ? null : country,
      'payload': (payload == null || payload.trim().isEmpty) ? null : payload,
      'status': 'queued',
      'updatedBy': editorUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
