import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/learning_plan.dart';

/// Cloud persistence for learning plans at `users/{uid}/learningPlans/{planId}`.
///
/// Storing plans in Firestore (like every other ClassTrack feature) means they
/// survive sign-out/sign-in and sync across devices — fixing the old local-only
/// SharedPreferences approach where plans appeared to vanish on logout.
class LearningPlanRepository {
  final FirebaseFirestore _db;
  final String uid;

  LearningPlanRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('learningPlans');

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(uid);

  Stream<List<LearningPlan>> watchPlans() {
    return _col.snapshots().map((snap) {
      final list = <LearningPlan>[];
      for (final d in snap.docs) {
        try {
          final data = {...d.data(), 'id': d.id};
          list.add(LearningPlan.fromJson(data));
        } catch (_) {
          // Skip a malformed document rather than breaking the whole list.
        }
      }
      // Newest first (matches the previous in-memory ordering).
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> save(LearningPlan plan) =>
      _col.doc(plan.id).set(plan.toJson());

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Streams the lifetime number of plans this user has ever created. This is
  /// used for the free-tier limit: it never decreases when a plan is deleted,
  /// so building-then-deleting a plan still counts against the free quota.
  Stream<int> watchPlansCreated() {
    return _userDoc.snapshots().map((d) {
      final v = d.data()?['learningPlansCreatedCount'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    });
  }

  /// Atomically increments the lifetime "plans created" counter. Called once
  /// each time a new plan is created (never on edits or deletes).
  Future<void> incrementPlansCreated() => _userDoc.set(
        {'learningPlansCreatedCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
}
