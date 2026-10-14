import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/firestore_parsing.dart';
import '../domain/class_session.dart';

/// CRUD for users/{uid}/subjects/{subjectId}/sessions.
class SessionRepository {
  final FirebaseFirestore _db;
  final String uid;

  SessionRepository({required FirebaseFirestore db, required this.uid})
      : _db = db;

  CollectionReference<Map<String, dynamic>> _col(String subjectId) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection(AppConstants.subjectsCollection)
      .doc(subjectId)
      .collection(AppConstants.sessionsCollection);

  Stream<List<ClassSession>> watchForSubject(String subjectId) {
    // Parsed per-document so one corrupt session can't blank the timetable.
    return _col(subjectId).snapshots().map(
          (snap) => mapDocsSafely(
            snap.docs,
            (d) => ClassSession.fromMap(d.id, subjectId, d.data()),
            context: 'sessions',
          ),
        );
  }

  /// One-shot read of the current sessions for a subject (used to prevent
  /// creating duplicate identical sessions on save).
  Future<List<ClassSession>> getForSubject(String subjectId) async {
    final snap = await _col(subjectId).get();
    return mapDocsSafely(
      snap.docs,
      (d) => ClassSession.fromMap(d.id, subjectId, d.data()),
      context: 'sessions',
    );
  }

  Future<String> add(String subjectId, ClassSession session) async {
    final ref = await _col(subjectId).add(session.toMap());
    return ref.id;
  }

  /// Add with a known id (AI import batch writes).
  Future<void> setWithId(String subjectId, String id, ClassSession s) =>
      _col(subjectId).doc(id).set(s.toMap());

  Future<void> update(ClassSession session) =>
      _col(session.subjectId).doc(session.id).set(
            session.toMap(),
            SetOptions(merge: true),
          );

  Future<void> delete(String subjectId, String id) =>
      _col(subjectId).doc(id).delete();

  /// Add a cancellation-exception date to a recurring session.
  Future<void> cancelOn(ClassSession session, DateTime date) {
    final updated = [...session.cancelledOn, DateTime(date.year, date.month, date.day)];
    return _col(session.subjectId).doc(session.id).set(
      {'cancelledOn': updated.map((d) => Timestamp.fromDate(d)).toList()},
      SetOptions(merge: true),
    );
  }
}
