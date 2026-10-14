import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../domain/content_report.dart';

/// Access to the `reports` collection.
///
/// Students may only CREATE reports (attributed to themselves); moderators+
/// read the queue and update status. All authorization is enforced by Firestore
/// rules — this class assumes the caller is permitted.
class ReportRepository {
  final FirebaseFirestore _db;

  /// The signed-in user's uid (reporter on create, reviewer on update).
  final String uid;
  ReportRepository({required FirebaseFirestore db, required this.uid})
    : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(AppConstants.reportsCollection);

  /// Files a new report (student). Ignores any caller-supplied status/uid.
  Future<void> create({
    required String resourceId,
    required String resourceTitle,
    required ReportReason reason,
    String? message,
  }) {
    final report = ContentReport(
      id: '',
      resourceId: resourceId,
      resourceTitle: resourceTitle,
      reporterUid: uid,
      reason: reason,
      message: message,
    );
    return _col.add(report.toCreateMap());
  }

  /// All reports, newest first (moderation queue).
  Stream<List<ContentReport>> watchAll({int limit = 300}) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ContentReport.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// Moderator action: change a report's status (+ optional resolution note),
  /// stamping the reviewer + time.
  Future<void> setStatus(String id, ReportStatus status, {String? resolution}) {
    return _col.doc(id).set({
      'status': status.key,
      'reviewedBy': uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (resolution != null && resolution.trim().isNotEmpty)
        'resolution': resolution.trim(),
    }, SetOptions(merge: true));
  }
}
