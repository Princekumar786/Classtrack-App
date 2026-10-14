import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_parsing.dart';
import '../domain/exam.dart';

/// CRUD for users/{uid}/exams.
class ExamRepository {
  final FirebaseFirestore _db;
  final String uid;

  ExamRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('users').doc(uid).collection('exams');

  /// Current-semester exams only (archived ones are hidden).
  Stream<List<Exam>> watchExams() => watchAllExams()
      .map((list) => list.where((e) => e.semesterId == null).toList());

  /// Every exam, including archived semesters.
  Stream<List<Exam>> watchAllExams() {
    return _col.snapshots().map((snap) {
      final list = parseDocsSafely(snap.docs, Exam.fromMap, context: 'exams');
      list.sort((a, b) => a.date.compareTo(b.date));
      return list;
    });
  }

  Future<void> add(Exam exam) => _col.add(exam.toMap());

  Future<void> update(Exam exam) =>
      _col.doc(exam.id).set(exam.toMap(), SetOptions(merge: true));

  Future<void> delete(String id) => _col.doc(id).delete();
}
