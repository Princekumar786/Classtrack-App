import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_parsing.dart';
import '../domain/grade_item.dart';

/// CRUD for users/{uid}/grades.
class GradeRepository {
  final FirebaseFirestore _db;
  final String uid;

  GradeRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('grades');

  /// Current-semester grades only (archived ones are hidden).
  Stream<List<GradeItem>> watchGrades() => watchAllGrades()
      .map((list) => list.where((g) => g.semesterId == null).toList());

  /// Every grade, including archived semesters.
  Stream<List<GradeItem>> watchAllGrades() {
    return _col.snapshots().map((snap) {
      final list =
          parseDocsSafely(snap.docs, GradeItem.fromMap, context: 'grades');
      // Newest first (by date, then created).
      list.sort((a, b) {
        final ad = a.date ?? a.createdAt;
        final bd = b.date ?? b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  Future<void> add(GradeItem grade) => _col.add(grade.toMap());

  Future<void> update(GradeItem grade) =>
      _col.doc(grade.id).set(grade.toMap(), SetOptions(merge: true));

  Future<void> delete(String id) => _col.doc(id).delete();
}
