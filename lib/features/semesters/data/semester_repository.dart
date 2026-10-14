import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../../exams/domain/exam.dart';
import '../../grades/domain/grade_item.dart';
import '../domain/semester.dart';

/// What a wrap-up will archive. Pure so the selection rules stay testable.
class WrapUpPlan {
  final List<String> subjectIds;
  final List<String> gradeIds;
  final List<String> examIds;

  /// Upcoming exams of archived subjects (their reminders get cancelled).
  final List<String> upcomingExamIds;

  const WrapUpPlan({
    required this.subjectIds,
    required this.gradeIds,
    required this.examIds,
    this.upcomingExamIds = const [],
  });

  bool get isEmpty => subjectIds.isEmpty && gradeIds.isEmpty && examIds.isEmpty;

  /// Archives the [selectedSubjectIds] with all their grades and exams. With
  /// [includeUnlinked], grades with no subject and PAST exams with no subject
  /// go too (upcoming unlinked exams stay in the current semester).
  factory WrapUpPlan.build({
    required Set<String> selectedSubjectIds,
    required List<GradeItem> grades,
    required List<Exam> exams,
    required bool includeUnlinked,
    required Set<String> currentSubjectIds,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    // "Unlinked" = no subject, or a subject that no longer exists.
    bool unlinked(String? id) => id == null || !currentSubjectIds.contains(id);
    final gradeIds = [
      for (final g in grades)
        if (g.semesterId == null &&
            ((g.subjectId != null && selectedSubjectIds.contains(g.subjectId)) ||
                (includeUnlinked && unlinked(g.subjectId))))
          g.id,
    ];
    final examIds = <String>[];
    final upcoming = <String>[];
    for (final e in exams) {
      if (e.semesterId != null) continue;
      final linked =
          e.subjectId != null && selectedSubjectIds.contains(e.subjectId);
      final past = e.date.isBefore(at);
      if (linked || (includeUnlinked && unlinked(e.subjectId) && past)) {
        examIds.add(e.id);
        if (!past) upcoming.add(e.id);
      }
    }
    return WrapUpPlan(
      subjectIds: selectedSubjectIds.toList(),
      gradeIds: gradeIds,
      examIds: examIds,
      upcomingExamIds: upcoming,
    );
  }
}

/// CRUD for users/{uid}/semesters plus the archive/restore tagging of
/// subjects, grades and exams.
class SemesterRepository {
  final FirebaseFirestore _db;
  final String uid;

  SemesterRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection(AppConstants.usersCollection).doc(uid);

  CollectionReference<Map<String, dynamic>> get _col =>
      _user.collection('semesters');

  CollectionReference<Map<String, dynamic>> get _subjects =>
      _user.collection(AppConstants.subjectsCollection);
  CollectionReference<Map<String, dynamic>> get _grades =>
      _user.collection('grades');
  CollectionReference<Map<String, dynamic>> get _exams =>
      _user.collection('exams');

  /// Newest wrap-up first (a just-written one has no server time yet).
  Stream<List<Semester>> watchSemesters() {
    return _col.snapshots().map((snap) {
      final list =
          parseDocsSafely(snap.docs, Semester.fromMap, context: 'semesters');
      list.sort((a, b) {
        final ad = a.wrappedAt, bd = b.wrappedAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return -1;
        if (bd == null) return 1;
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  /// Creates the semester and tags everything in [plan] with its id.
  /// Returns the new semester id.
  Future<String> wrapUp({
    required String name,
    DateTime? startDate,
    DateTime? endDate,
    double? officialSgpa,
    required WrapUpPlan plan,
  }) async {
    final ref = _col.doc();
    await ref.set(Semester(
      id: ref.id,
      name: name.trim().isEmpty ? 'Semester' : name.trim(),
      startDate: startDate,
      endDate: endDate,
      officialSgpa: officialSgpa,
    ).toMap());
    final tag = {'semesterId': ref.id};
    await _writeAll([
      for (final id in plan.subjectIds) (_subjects.doc(id), tag),
      for (final id in plan.gradeIds) (_grades.doc(id), tag),
      for (final id in plan.examIds) (_exams.doc(id), tag),
    ]);
    return ref.id;
  }

  /// Undo a wrap-up: everything tagged with [semesterId] returns to the current
  /// semester and the semester doc is removed. Nothing else is deleted.
  Future<void> restore(String semesterId) async {
    final untag = {'semesterId': FieldValue.delete()};
    final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[];
    for (final col in [_subjects, _grades, _exams]) {
      final snap = await col.where('semesterId', isEqualTo: semesterId).get();
      for (final d in snap.docs) {
        writes.add((d.reference, untag));
      }
    }
    await _writeAll(writes);
    await _col.doc(semesterId).delete();
  }

  Future<void> rename(String semesterId, String name) =>
      _col.doc(semesterId).update({'name': name.trim()});

  /// Sets (or clears, with null) the official university SGPA.
  Future<void> setOfficialSgpa(String semesterId, double? sgpa) =>
      _col.doc(semesterId).update({'officialSgpa': sgpa});

  /// Sets a subject's official final result. Null clears that field.
  Future<void> setFinalResult(
    String subjectId, {
    String? finalGrade,
    double? finalGradePoints,
    int? credits,
  }) {
    final grade = finalGrade?.trim();
    return _subjects.doc(subjectId).update({
      'finalGrade':
          (grade == null || grade.isEmpty) ? FieldValue.delete() : grade,
      'finalGradePoints': finalGradePoints ?? FieldValue.delete(),
      'credits': credits,
    });
  }

  /// Batched merge-writes, chunked under Firestore's 500-ops-per-batch limit.
  Future<void> _writeAll(
      List<(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>
          writes) async {
    const chunk = 400;
    for (var i = 0; i < writes.length; i += chunk) {
      final batch = _db.batch();
      for (final (ref, data) in writes.skip(i).take(chunk)) {
        batch.set(ref, data, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}
